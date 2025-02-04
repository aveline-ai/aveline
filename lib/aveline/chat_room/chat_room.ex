defmodule Aveline.ChatRoom.ChatRoom do
  @moduledoc "Schema for chat rooms"
  use Aveline.Schema
  import Ecto.Changeset

  alias Aveline.ChatRoom.ChatRoomMembership
  alias Aveline.ChatRoom.Message

  schema "chat_rooms" do
    field :name, :string
    field :ai_settings, :map

    # Chat rooms can be nested
    belongs_to :parent_chat_room, __MODULE__
    has_many :child_chat_rooms, __MODULE__, foreign_key: :parent_chat_room_id
    has_many :messages, Message
    has_many :chat_room_memberships, ChatRoomMembership
    has_many :users, through: [:chat_room_memberships, :user]

    timestamps()
  end

  def changeset(chat_room, attrs) do
    chat_room
    |> cast(attrs, [:name, :parent_chat_room_id])
    |> validate_required([:name])
  end
end
