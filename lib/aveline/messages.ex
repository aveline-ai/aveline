defmodule Aveline.Messages do
  @moduledoc """
  Thread messages attached to an item. Every mutation publishes a PubSub
  event so LiveViews can update in real time.
  """

  import Ecto.Query

  alias Aveline.Broadcasts
  alias Aveline.Messages.ItemMessage
  alias Aveline.Repo

  @doc """
  Base query excluding soft-deleted messages.
  """
  def base_query do
    from m in ItemMessage, where: is_nil(m.deleted_at)
  end

  @doc """
  Messages on an item, oldest first, with `:author` preloaded.
  """
  def list_for_item(item_id) when is_binary(item_id) do
    from(m in base_query(),
      where: m.item_id == ^item_id,
      order_by: [asc: m.inserted_at],
      preload: [:author]
    )
    |> Repo.all()
  end

  def get_message(id) when is_binary(id) do
    Repo.get(ItemMessage, id) |> Repo.preload([:author])
  end

  def create_message(attrs) do
    %ItemMessage{}
    |> ItemMessage.create_changeset(attrs)
    |> Repo.insert()
    |> preload_and_broadcast(:message_created)
  end

  def update_message(%ItemMessage{} = message, attrs) do
    message
    |> ItemMessage.update_changeset(attrs)
    |> Repo.update()
    |> preload_and_broadcast(:message_updated)
  end

  def soft_delete_message(%ItemMessage{} = message, deleted_by_id) do
    message
    |> Ecto.Changeset.change(%{
      deleted_at: DateTime.utc_now(),
      deleted_by_id: deleted_by_id
    })
    |> Repo.update()
    |> preload_and_broadcast(:message_deleted)
  end

  defp preload_and_broadcast({:ok, message}, event) do
    message = Repo.preload(message, [:author])
    Broadcasts.publish_message_event(event, message)
    {:ok, message}
  end

  defp preload_and_broadcast(other, _event), do: other
end
