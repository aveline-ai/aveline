defmodule Aveline.ChatRoom.ChatRoomMembership do
  @moduledoc "Schema for managing user memberships in chat rooms"
  use Aveline.Schema
  import Ecto.Changeset
  alias Aveline.Account.User
  alias Aveline.ChatRoom.ChatRoom

  schema "chat_room_memberships" do
    belongs_to :chat_room, ChatRoom
    belongs_to :user, User

    timestamps()
  end

  def changeset(chat_room_membership, attrs) do
    chat_room_membership
    |> cast(attrs, [:chat_room_id, :user_id])
    |> validate_required([:chat_room_id, :user_id])
    |> unique_constraint([:chat_room_id, :user_id])
  end
end
