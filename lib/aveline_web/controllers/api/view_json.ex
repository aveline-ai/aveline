defmodule AvelineWeb.Api.ViewJSON do
  @moduledoc false

  alias AvelineWeb.Api.DocJSON

  def index(%{views: views}), do: %{views: Enum.map(views, &one/1)}
  def show(%{view: view}), do: one(view)

  def show_with_items(%{view: view, items: items}) do
    %{
      view: one(view),
      items: Enum.map(items, &DocJSON.one/1)
    }
  end

  def one(v) do
    %{
      id: v.id,
      slug: v.slug,
      name: v.name,
      tag_filter: v.tag_filter || [],
      description: v.description,
      scope: v.scope,
      created_by_id: v.created_by_id,
      inserted_at: v.inserted_at,
      updated_at: v.updated_at,
      deleted_at: v.deleted_at
    }
  end
end
