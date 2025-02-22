defmodule Aveline.Enums.ChatRoomMode do
  @moduledoc """
  A wrapper around the chat room modes we support.
  """

  # All chat room modes as macros so it can be used in pattern matching
  defmacro book_buddy, do: quote(do: :book_buddy)
  defmacro chat_companion, do: quote(do: :chat_companion)

  @doc """
  Returns a list of all supported chat room modes.
  """
  def chat_room_modes, do: [book_buddy(), chat_companion()]

  @doc """
  Converts a string to a chat room mode atom.
  """
  def from_string!("book_buddy"), do: book_buddy()
  def from_string!("chat_companion"), do: chat_companion()
  def from_string!(string), do: raise("Invalid chat room mode: #{string}")
end
