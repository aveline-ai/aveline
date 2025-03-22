defmodule Aveline.Structs.EnrichedChatRoomMessage do
  @moduledoc """
  A struct that represents a chat room message with additional user information.
  """

  use Accessible

  @enforce_keys [:id, :content, :author_kind, :inserted_at, :user_display_name, :user_id]
  defstruct [:id, :content, :author_kind, :inserted_at, :user_display_name, :user_id]
end
