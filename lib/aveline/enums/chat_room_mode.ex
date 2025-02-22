defmodule Aveline.Enums.ChatRoomMode do
  @moduledoc """
  A wrapper around the chat room modes we support.
  """

  @doc """
  Returns a list of all supported chat room modes.
  """
  def chat_room_modes, do: [book_buddy(), chat_companion()]

  def book_buddy, do: :book_buddy
  def chat_companion, do: :chat_companion

  @doc """
  Converts a string to a chat room mode atom.
  """
  def from_string!("book_buddy"), do: book_buddy()
  def from_string!("chat_companion"), do: chat_companion()
  def from_string!(string), do: raise("Invalid chat room mode: #{string}")
end
