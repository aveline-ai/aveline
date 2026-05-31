defmodule Aveline.Messages do
  @moduledoc """
  Thread messages, anchored to a specific item version. Optionally pinned
  to a block. Every mutation publishes a PubSub event on the
  `item:<base_item_id>:messages` topic so subscribed LVs update live.
  """

  import Ecto.Query

  alias Aveline.Items.Item
  alias Aveline.Messages.ItemMessage
  alias Aveline.Repo

  def base_query do
    from m in ItemMessage, where: is_nil(m.deleted_at)
  end

  @doc """
  All non-deleted messages on a logical item across ALL versions, oldest
  first. The base_item_id is used to JOIN items so a comment posted on v3
  still shows up on v4's page (just unresolved + visually marked
  "carried over from v3" if we want later).
  """
  def list_for_base_item(base_item_id) when is_binary(base_item_id) do
    from(m in base_query(),
      join: i in Item,
      on: i.id == m.item_id,
      where: i.base_item_id == ^base_item_id,
      order_by: [asc: m.inserted_at],
      preload: [:actor_user]
    )
    |> Repo.all()
  end

  def get_message(id) when is_binary(id) do
    Repo.get(ItemMessage, id) |> Repo.preload([:actor_user])
  end

  @doc """
  Create a message on a specific item version.
  Required attrs: item_id, body, actor_user_id, actor_type.
  Optional: block_id.
  """
  def create_message(attrs) do
    %ItemMessage{}
    |> ItemMessage.create_changeset(attrs)
    |> Repo.insert()
    |> preload_and_broadcast(:message_created)
  end

  def update_message(%ItemMessage{} = m, attrs) do
    m
    |> ItemMessage.update_changeset(attrs)
    |> Repo.update()
    |> preload_and_broadcast(:message_updated)
  end

  def soft_delete_message(%ItemMessage{} = m, deleted_by_id) do
    m
    |> Ecto.Changeset.change(%{deleted_at: DateTime.utc_now(), deleted_by_id: deleted_by_id})
    |> Repo.update()
    |> preload_and_broadcast(:message_deleted)
  end

  defp preload_and_broadcast({:ok, %ItemMessage{} = m}, event) do
    m = Repo.preload(m, [:actor_user])
    # Look up base_item_id for the PubSub topic
    base_item_id =
      Repo.one(from i in Item, where: i.id == ^m.item_id, select: i.base_item_id)

    if base_item_id do
      Phoenix.PubSub.broadcast(
        Aveline.PubSub,
        "item:" <> base_item_id <> ":messages",
        {event, m}
      )
    end

    {:ok, m}
  end

  defp preload_and_broadcast(other, _), do: other
end
