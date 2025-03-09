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

  def new_message_for_user_id_changeset(%{user_id: user_id, chat_room_id: chat_room_id}, content) do
    %__MODULE__{}
    |> cast(%{"content" => content}, [:content])
    |> put_change(:user_id, user_id)
    |> put_change(:chat_room_id, chat_room_id)
    |> put_change(:author_kind, Enums.AuthorKind.user())
    |> validate_length(:content, min: 1)
    |> validate_required([:content, :user_id, :chat_room_id, :author_kind])
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:content, :author_kind, :chat_room_id, :user_id])
    |> validate_required([:content, :chat_room_id, :author_kind])
    |> validate_user_id_provided_for_user_messages()
  end

  # Private

  defp validate_user_id_provided_for_user_messages(changeset) do
    if get_field(changeset, :author_kind) == "user" do
      validate_required(changeset, [:user_id])
    else
      changeset
    end
  end
end
