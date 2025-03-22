defmodule Aveline.EventBus do
  @moduledoc """
  A simple event bus for the application powered by Phoenix.PubSub.
  """

  alias Aveline.Structs.EnrichedChatRoomMessage

  # Chatroom Events

  @doc """
  Subscribe to all chatroom events.

  Does NOT authenticate access. You must verify a user has access to the chatroom before subscribing.
  """
  def subscribe({:chatroom, chatroom_id}) do
    Phoenix.PubSub.subscribe(Aveline.PubSub, topic(:chatroom, chatroom_id))
  end

  @doc """
  Broadcast a message to all subscribers of a chatroom.
  """
  def broadcast!(
        {:chatroom, chatroom_id},
        kind = :new_message,
        enriched_chat_room_message = %EnrichedChatRoomMessage{}
      ) do
    Phoenix.PubSub.broadcast!(Aveline.PubSub, topic(:chatroom, chatroom_id), %{
      kind: kind,
      chat_room_id: chatroom_id,
      enriched_chat_room_message: enriched_chat_room_message
    })
  end

  # Private

  ## Topics

  defp topic(:chatroom, chatroom_id), do: "chatroom:#{chatroom_id}"
end
