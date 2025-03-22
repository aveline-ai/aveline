defmodule Aveline.Enums.ChatRoomMode do
  @moduledoc """
  A wrapper around the chat room modes we support.
  """

  alias Aveline.Enums.Helpers

  # All chat room modes as macros so it can be used in pattern matching
  defmacro group_chat, do: quote(do: :group_chat)
  defmacro private_chat, do: quote(do: :private_chat)

  @doc """
  Returns a list of all supported chat room modes.
  """
  def chat_room_modes, do: [group_chat(), private_chat()]

  @doc """
  Converts a string to a chat room mode atom.
  """
  def from_string!("group_chat"), do: group_chat()
  def from_string!("private_chat"), do: private_chat()
  def from_string!(string), do: raise("Invalid chat room mode: #{string}")

  @doc """
  A type-smart enum mapper. Raises an error if the chat room mode is invalid.
  """
  def map!(chat_room_mode, %{
        group_chat() => group_chat_value_or_fn,
        private_chat() => private_chat_value_or_fn
      }) do
    case chat_room_mode do
      group_chat() -> Helpers.run_fn_or_return_value(group_chat_value_or_fn)
      private_chat() -> Helpers.run_fn_or_return_value(private_chat_value_or_fn)
      _ -> raise("Invalid chat room mode: #{chat_room_mode}")
    end
  end
end
