defmodule Aveline.Views do
  @moduledoc """
  Views context.
  """

  import Ecto.Query

  alias Aveline.Broadcasts
  alias Aveline.Docs
  alias Aveline.Repo
  alias Aveline.Views.View

  def base_query do
    from v in View, where: is_nil(v.deleted_at)
  end

  @doc """
  All non-deleted views in a workspace, no visibility filter. Reserved for
  admin / migration / test paths.
  """
  def list_views(workspace_id) do
    from(v in base_query(),
      where: v.workspace_id == ^workspace_id,
      order_by: [asc: v.name]
    )
    |> Repo.all()
  end

  @doc """
  Views visible to `user_id`: all team-scope views plus their own personal
  views. This is what every web/CLI list call should use.
  """
  def list_visible_views(workspace_id, user_id) do
    from(v in base_query(),
      where: v.workspace_id == ^workspace_id,
      where: v.scope == "team" or v.created_by_id == ^user_id,
      order_by: [asc: v.name]
    )
    |> Repo.all()
  end

  @doc """
  Only the user's own personal views.
  """
  def list_personal_views(workspace_id, user_id) do
    from(v in base_query(),
      where: v.workspace_id == ^workspace_id,
      where: v.scope == "personal" and v.created_by_id == ^user_id,
      order_by: [asc: v.name]
    )
    |> Repo.all()
  end

  @doc """
  All team-scope views in the workspace.
  """
  def list_team_views(workspace_id) do
    from(v in base_query(),
      where: v.workspace_id == ^workspace_id and v.scope == "team",
      order_by: [asc: v.name]
    )
    |> Repo.all()
  end

  @doc """
  True when `user_id` is allowed to see this view (team scope or creator).
  """
  def visible_to?(%View{scope: "team"}, _user_id), do: true
  def visible_to?(%View{scope: "personal", created_by_id: uid}, uid), do: true
  def visible_to?(_, _), do: false

  def get_by_slug(workspace_id, slug) when is_binary(slug) do
    from(v in View,
      where: v.workspace_id == ^workspace_id and v.slug == ^slug,
      order_by: [desc: v.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  def get_by_slug(_, _), do: nil

  def get_active_by_slug(workspace_id, slug) when is_binary(slug) do
    from(v in base_query(),
      where: v.workspace_id == ^workspace_id and v.slug == ^slug,
      limit: 1
    )
    |> Repo.one()
  end

  def get_active_by_slug(_, _), do: nil

  def create_view(attrs) do
    %View{}
    |> View.create_changeset(attrs)
    |> Repo.insert()
    |> broadcast(:view_created)
  end

  def update_view(%View{} = view, attrs) do
    view
    |> View.update_changeset(attrs)
    |> Repo.update()
    |> broadcast(:view_updated)
  end

  def soft_delete_view(%View{} = view, deleted_by_id) do
    view
    |> Ecto.Changeset.change(%{
      deleted_at: DateTime.utc_now(),
      deleted_by_id: deleted_by_id
    })
    |> Repo.update()
    |> broadcast(:view_deleted)
  end

  def restore_view(%View{} = view) do
    view
    |> Ecto.Changeset.change(%{deleted_at: nil, deleted_by_id: nil})
    |> Repo.update()
    |> broadcast(:view_restored)
  end

  defp broadcast({:ok, view}, event) do
    Broadcasts.publish_view_event(event, view)
    {:ok, view}
  end

  defp broadcast(other, _event), do: other

  @doc """
  Items matching a view's tag_filter.
  """
  def matching_items(%View{} = view, opts \\ []) do
    extra =
      case view.tag_filter do
        list when is_list(list) -> list
        _ -> []
      end

    Docs.list_current(view.workspace_id, Keyword.put(opts, :tags, extra))
  end
end
