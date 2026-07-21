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
  alias Aveline.Views.ViewShare

  defp base_query do
    from v in View, where: not v.superseded and is_nil(v.deleted_at)
  end

  # Pinned first, then name — the one ordering every surface uses
  # (title switcher, list-views, sidebar).
  def list_for_workspace(workspace_id, opts \\ []) do
    from(v in base_query(),
      where: v.workspace_id == ^workspace_id,
      order_by: [desc: v.pinned, asc: v.name]
    )
    |> where_usable(Keyword.get(opts, :viewer))
    |> Repo.all()
  end

  @doc """
  Narrows a views query to what `user_id` may use. Same rule as docs;
  `nil` fails closed (private views hidden).
  """
  def where_usable(query, nil) do
    from v in query, where: v.visibility != "private"
  end

  def where_usable(query, user_id) do
    shared =
      from s in ViewShare,
        where: s.user_id == ^user_id and is_nil(s.deleted_at),
        select: s.base_view_id

    from v in query,
      where:
        v.visibility != "private" or v.owner_id == ^user_id or
          v.base_view_id in subquery(shared)
  end

  @doc "May this member use the view? (Membership already checked.)"
  def member_can_use?(%View{visibility: "private"} = view, user_id),
    do: view.owner_id == user_id or share_role(view.base_view_id, user_id) != nil

  def member_can_use?(%View{}, _user_id), do: true

  @doc "May this member edit the view's config? Private needs owner or editor share."
  def member_can_edit?(%View{visibility: "private"} = view, user_id),
    do: view.owner_id == user_id or share_role(view.base_view_id, user_id) == "editor"

  def member_can_edit?(%View{}, _user_id), do: true

  defp share_role(base_view_id, user_id) do
    from(s in ViewShare,
      where: s.base_view_id == ^base_view_id and s.user_id == ^user_id and is_nil(s.deleted_at),
      select: s.role
    )
    |> Repo.one()
  end

  @doc """
  Change a view's visibility in place. Owner only; a pinned view can't
  go private (the sidebar is a team surface): unpin it first.
  """
  def set_visibility(%View{} = view, visibility, actor_user_id) do
    cond do
      visibility not in ~w(private workspace) ->
        {:error, "visibility must be one of: private, workspace"}

      view.owner_id != actor_user_id ->
        {:error, "only the view's owner can change its visibility"}

      visibility == "private" and view.pinned ->
        {:error, "unpin this view first: pinned views live in the shared sidebar and can't be private"}

      view.visibility == visibility ->
        {:ok, view}

      true ->
        view |> Ecto.Changeset.change(%{visibility: visibility}) |> Repo.update()
    end
  end

  @doc "Live shares on a view, user preloaded, oldest first."
  def list_shares(%View{} = view) do
    from(s in ViewShare,
      where: s.base_view_id == ^view.base_view_id and is_nil(s.deleted_at),
      order_by: [asc: s.inserted_at],
      preload: [:user, :granted_by]
    )
    |> Repo.all()
  end

  @doc "Grant (or re-role) a member's access. Owner only; target must be a member."
  def share_view(%View{} = view, user_id, role, actor_user_id) do
    cond do
      role not in ViewShare.roles() ->
        {:error, "role must be one of: #{Enum.join(ViewShare.roles(), ", ")}"}

      view.owner_id != actor_user_id ->
        {:error, "only the view's owner can share it"}

      user_id == view.owner_id ->
        {:error, "the owner already has full access"}

      not Aveline.Workspaces.member?(view.workspace_id, user_id) ->
        {:error, "that user is not a member of this workspace"}

      true ->
        existing =
          Repo.one(
            from s in ViewShare,
              where:
                s.base_view_id == ^view.base_view_id and s.user_id == ^user_id and
                  is_nil(s.deleted_at)
          )

        case existing do
          nil ->
            %ViewShare{}
            |> ViewShare.changeset(%{
              base_view_id: view.base_view_id,
              workspace_id: view.workspace_id,
              user_id: user_id,
              role: role,
              granted_by_id: actor_user_id
            })
            |> Repo.insert()

          %ViewShare{} = share ->
            share |> ViewShare.changeset(%{role: role}) |> Repo.update()
        end
    end
  end

  @doc "Revoke a member's share. Owner only; soft delete."
  def unshare_view(%View{} = view, user_id, actor_user_id) do
    with :owner <- if(view.owner_id == actor_user_id, do: :owner, else: :not_owner),
         %ViewShare{} = share <-
           Repo.one(
             from s in ViewShare,
               where:
                 s.base_view_id == ^view.base_view_id and s.user_id == ^user_id and
                   is_nil(s.deleted_at)
           ) do
      share
      |> Ecto.Changeset.change(%{deleted_at: DateTime.utc_now()})
      |> Repo.update()
    else
      :not_owner -> {:error, "only the view's owner can revoke shares"}
      nil -> {:error, "no live share for that user on this view"}
    end
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
        created_by_id: created_by_id,
        # The creator owns the view; ownership never moves with edits.
        owner_id: created_by_id
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
    # Config edits MERGE onto the current config so a partial update
    # (e.g. just --sub-group-by) doesn't drop the other keys. Callers
    # clear a key by sending it explicitly as nil.
    config =
      case Map.get(changes, :config) do
        nil -> current.config
        incoming -> Map.merge(current.config || %{}, incoming)
      end

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
            visibility: current.visibility,
            owner_id: current.owner_id,
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
  def set_pinned(%View{visibility: "private"} = _view, true),
    do: {:error, "private views can't be pinned; make the view workspace-visible first"}

  def set_pinned(%View{} = view, pinned?) when is_boolean(pinned?) do
    view |> Ecto.Changeset.change(pinned: pinned?) |> Repo.update()
  end

  def safe_map(%View{} = view) do
    %{
      "name" => view.name,
      "description" => view.description,
      "config" => view.config,
      "pinned" => view.pinned,
      "visibility" => view.visibility,
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
