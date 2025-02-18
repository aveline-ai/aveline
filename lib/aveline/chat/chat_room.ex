defmodule Aveline.Chat.ChatRoom do
  @moduledoc "Schema for chat rooms"
  use Aveline.Schema
  import Ecto.Changeset

  alias Aveline.Chat.ChatRoomMembership
  alias Aveline.Chat.Message

  alias Aveline.Enums

  schema "chat_rooms" do
    field :name, :string
    field :learning_language, Ecto.Enum, values: Enums.Language.languages()
    field :base_language, Ecto.Enum, values: Enums.Language.languages()
    field :chat_room_mode, Ecto.Enum, values: Enums.ChatRoomMode.chat_room_modes()

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
    |> cast(attrs, [:name, :parent_chat_room_id, :learning_language, :base_language, :chat_room_mode])
    |> validate_required([:name, :learning_language, :base_language, :chat_room_mode])
  end
end
