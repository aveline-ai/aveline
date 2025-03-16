defmodule Aveline.Chat.Message do
  @moduledoc "Schema for chat room messages"
  use Aveline.Schema
  import Ecto.Changeset

  require Aveline.Enums.AuthorKind

  alias Aveline.Account.User
  alias Aveline.Chat.ChatRoom
  alias Aveline.Enums

  schema "messages" do
    field :content, :string
    field :author_kind, Ecto.Enum, values: Enums.AuthorKind.author_kinds()

    belongs_to :chat_room, ChatRoom
    belongs_to :user, User

    timestamps()
  end

  def new_message_for_ai_changeset(%{chat_room_id: chat_room_id}, content) do
    %__MODULE__{}
    |> cast(%{"content" => content}, [:content])
    |> update_change(:content, &String.trim/1)
    |> put_change(:chat_room_id, chat_room_id)
    |> put_change(:author_kind, Enums.AuthorKind.ai())
    |> validate_length(:content, min: 1)
    |> validate_required([:content, :chat_room_id, :author_kind])
  end

  def new_message_for_user_id_changeset(%{user_id: user_id, chat_room_id: chat_room_id}, content) do
    %__MODULE__{}
    |> cast(%{"content" => content}, [:content])
    |> update_change(:content, &String.trim/1)
    |> put_change(:user_id, user_id)
    |> put_change(:chat_room_id, chat_room_id)
    |> put_change(:author_kind, Enums.AuthorKind.user())
    |> validate_length(:content, min: 1)
    |> validate_required([:content, :user_id, :chat_room_id, :author_kind])
  end
end
