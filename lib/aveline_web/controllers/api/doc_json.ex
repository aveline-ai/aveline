defmodule AvelineWeb.Api.DocJSON do
  @moduledoc false

  alias AvelineWeb.Api.UserJSON

  def index(%{items: items}), do: %{items: Enum.map(items, &one/1)}
  def show(%{item: item}), do: one(item)

  def one(i) do
    %{
      id: i.id,
      base_doc_id: i.base_doc_id,
      version_number: i.version_number,
      slug: i.slug,
      title: i.title,
      summary: i.summary,
      blocks: i.blocks || [],
      tags: i.tags || [],
      pin_slot: i.pin_slot,
      owner: UserJSON.summary(loaded(i.owner)),
      actor: %{
        user: UserJSON.summary(loaded(i.actor_user)),
        type: i.actor_type
      },
      operations: i.operations || [],
      intent: i.intent,
      resolves_comment_ids: i.resolves_comment_ids || [],
      inserted_at: i.inserted_at,
      updated_at: i.updated_at,
      deleted_at: i.deleted_at
    }
  end

  defp loaded(%Ecto.Association.NotLoaded{}), do: nil
  defp loaded(other), do: other
end
