defmodule Aveline.EventBus do
  @moduledoc """
  A simple event bus for the application powered by Phoenix.PubSub.
  """

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
        message = %{
          id: _id,
          content: _content,
          author_kind: _author_kind,
          inserted_at: _inserted_at,
          user_display_name: _user_display_name,
          user_id: _user_id
        }
      ) do
    Phoenix.PubSub.broadcast!(Aveline.PubSub, topic(:chatroom, chatroom_id), %{
      kind: kind,
      chat_room_id: chatroom_id,
      message: message
    })
  end

  # Private

  ## Topics

  defp topic(:chatroom, chatroom_id), do: "chatroom:#{chatroom_id}"
end
