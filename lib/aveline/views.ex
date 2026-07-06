defmodule Aveline.Views do
  @moduledoc """
  Views — named, versioned snapshots of the Docs page's display knobs
  (see `Aveline.Views.View`). Ordinary config-tier lifecycle: create,
  versioned edit with intent trail, soft delete, restore. Pin/unpin is
  placement, updated in place on the current row (like doc pin slots),
  never a version.
  """

  import Ecto.Query, warn: false

  alias Aveline.Repo
  alias Aveline.Tags
  alias Aveline.Views.View

  defp base_query do
    from v in View, where: not v.superseded and is_nil(v.deleted_at)
  end

  # Pinned first, then name — the one ordering every surface uses
  # (title switcher, list-views, sidebar).
  def list_for_workspace(workspace_id) do
    from(v in base_query(),
      where: v.workspace_id == ^workspace_id,
      order_by: [desc: v.pinned, asc: v.name]
    )
    |> Repo.all()
  end

  def list_pinned(workspace_id) do
    from(v in base_query(), where: v.workspace_id == ^workspace_id and v.pinned, order_by: v.name)
    |> Repo.all()
  end

  def get_current_by_name(workspace_id, name) when is_binary(name) do
    from(v in base_query(), where: v.workspace_id == ^workspace_id and v.name == ^name)
    |> Repo.one()
  end

  def create(workspace_id, name, description, config, created_by_id) do
    with :ok <- validate_config_against_workspace(workspace_id, config) do
      %View{}
      |> View.insert_changeset(%{
        workspace_id: workspace_id,
        base_view_id: Ecto.UUID.generate(),
        name: name,
        description: description,
        config: config || %{},
        created_by_id: created_by_id
      })
      |> Repo.insert()
    end
  end

  @doc """
  Versioned edit: `changes` may carry `:name`, `:description`,
  `:config`. Mints v+1 on the same base id; supersede-then-insert.
  Pinned carries over (placement survives edits).
  """
  def edit(%View{} = current, changes, user_id) when is_map(changes) do
    config = Map.get(changes, :config, current.config)

    with :ok <- validate_config_against_workspace(current.workspace_id, config) do
      Repo.transaction(fn ->
        {1, _} =
          from(v in View, where: v.id == ^current.id)
          |> Repo.update_all(set: [superseded: true])

        insert =
          %View{}
          |> View.insert_changeset(%{
            workspace_id: current.workspace_id,
            base_view_id: current.base_view_id,
            version_number: current.version_number + 1,
            name: Map.get(changes, :name, current.name),
            description: Map.get(changes, :description, current.description),
            config: config,
            pinned: current.pinned,
            created_by_id: user_id
          })
          |> Repo.insert()

        case insert do
          {:ok, view} -> view
          {:error, cs} -> Repo.rollback(cs)
        end
      end)
    end
  end

  def delete(%View{} = view, user_id) do
    view
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(), deleted_by_id: user_id)
    |> Repo.update()
  end

  def restore(workspace_id, name) do
    deleted =
      from(v in View,
        where:
          v.workspace_id == ^workspace_id and v.name == ^name and not v.superseded and
            not is_nil(v.deleted_at)
      )
      |> Repo.one()

    case deleted do
      nil -> {:error, :not_user_deleted}
      view -> view |> Ecto.Changeset.change(deleted_at: nil, deleted_by_id: nil) |> Repo.update()
    end
  end

  @doc "Placement, not meaning: in-place update, no version minted."
  def set_pinned(%View{} = view, pinned?) when is_boolean(pinned?) do
    view |> Ecto.Changeset.change(pinned: pinned?) |> Repo.update()
  end

  def safe_map(%View{} = view) do
    %{
      "name" => view.name,
      "description" => view.description,
      "config" => view.config,
      "pinned" => view.pinned,
      "version_number" => view.version_number,
      "created_at" => DateTime.to_iso8601(view.inserted_at)
    }
  end

  # Filter tags must exist; group_by must be a scope with members. A
  # view over unknown tags is a typo, not an empty view (same spirit as
  # the old board-block validation).
  defp validate_config_against_workspace(workspace_id, config) when is_map(config) do
    tags = Map.get(config, "tags", [])
    group_by = Map.get(config, "group_by")

    with :ok <- Tags.ensure_all_exist(workspace_id, Enum.filter(tags, &is_binary/1)) do
      cond do
        is_nil(group_by) ->
          :ok

        not is_binary(group_by) or not Regex.match?(~r/^[a-z0-9][a-z0-9-]*$/, group_by) ->
          {:error, :view_invalid, "group_by must be a tag scope (a plain slug like \"status\")"}

        Tags.list_scope_members(workspace_id, group_by) == [] ->
          {:error, :view_invalid, "group_by scope has no tags in this workspace: #{group_by}"}

        true ->
          :ok
      end
    end
  end

  defp validate_config_against_workspace(_ws, nil), do: :ok
  defp validate_config_against_workspace(_ws, _), do: {:error, :view_invalid, "config must be an object"}
end
