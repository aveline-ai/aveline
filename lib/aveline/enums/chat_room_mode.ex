defmodule Aveline.Enums.ChatRoomMode do
  @moduledoc """
  A wrapper around the chat room modes we support.
  """
  @chat_room_modes ~w(book_buddy chat_companion)a

  @doc """
  Returns a list of all supported chat room modes.
  """
  def chat_room_modes, do: @chat_room_modes

  @doc """
  Converts a string to a chat room mode atom.
  """
  def from_string!(string) when is_binary(string) do
    string
    |> String.to_existing_atom()
    |> case do
      chat_room_mode when chat_room_mode in @chat_room_modes -> chat_room_mode
      _ -> raise "Invalid chat room mode: #{string}"
    end
  end
end
