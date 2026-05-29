defmodule AvelineWeb.Api.ItemJSON do
  @moduledoc false

  alias AvelineWeb.Api.UserJSON

  def index(%{items: items}), do: %{items: Enum.map(items, &one/1)}
  def show(%{item: item}), do: one(item)

  def one(i) do
    %{
      id: i.id,
      slug: i.slug,
      title: i.title,
      body: i.body,
      summary: i.summary,
      tags: i.tags || [],
      pinned: i.pinned,
      owner: UserJSON.summary(loaded(i.owner)),
      created_by: UserJSON.summary(loaded(i.created_by)),
      created_via: i.created_via,
      inserted_at: i.inserted_at,
      updated_at: i.updated_at,
      deleted_at: i.deleted_at
    }
  end

  defp loaded(%Ecto.Association.NotLoaded{}), do: nil
  defp loaded(other), do: other
end
