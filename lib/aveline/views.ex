defmodule Aveline.Views do
  @moduledoc """
  Views context.
  """

  import Ecto.Query

  alias Aveline.Items
  alias Aveline.Repo
  alias Aveline.Views.View

  def base_query do
    from v in View, where: is_nil(v.deleted_at)
  end

  def list_views(workspace_id) do
    from(v in base_query(),
      where: v.workspace_id == ^workspace_id,
      order_by: [asc: v.name]
    )
    |> Repo.all()
  end

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
  end

  def update_view(%View{} = view, attrs) do
    view
    |> View.update_changeset(attrs)
    |> Repo.update()
  end

  def soft_delete_view(%View{} = view, deleted_by_id) do
    view
    |> Ecto.Changeset.change(%{
      deleted_at: DateTime.utc_now(),
      deleted_by_id: deleted_by_id
    })
    |> Repo.update()
  end

  def restore_view(%View{} = view) do
    view
    |> Ecto.Changeset.change(%{deleted_at: nil, deleted_by_id: nil})
    |> Repo.update()
  end

  @doc """
  Items matching a view's tag_filter.
  """
  def matching_items(%View{} = view, opts \\ []) do
    Items.list_items(view.workspace_id, Keyword.put(opts, :view, view))
  end
end
