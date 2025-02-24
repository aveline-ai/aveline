defmodule Aveline.Chat do
  @moduledoc """
  The ChatRoom context handles chat room management, memberships, and messages.
  """

  import Ecto.Query
  alias Aveline.Account.User
  alias Aveline.Chat.ChatRoom
  alias Aveline.Chat.ChatRoomMembership
  alias Aveline.Chat.Message
  alias Aveline.Repo

  def get_chat_rooms_with_last_message_for_user(user_id) do
    from(cr in ChatRoom,
      as: :chat_room,
      join: crm in ChatRoomMembership,
      on: cr.id == crm.chat_room_id,
      where: crm.user_id == ^user_id,
      left_lateral_join:
        m in subquery(
          from m in Message,
            left_join: u in assoc(m, :user),
            where: m.chat_room_id == parent_as(:chat_room).id,
            order_by: [asc: :inserted_at],
            limit: 1,
            select: %{
              content: m.content,
              author_kind: m.author_kind,
              user_display_name: u.display_name,
              user_id: u.id,
              inserted_at: m.inserted_at
            }
        ),
      on: true,
      select: %{
        id: cr.id,
        name: cr.name,
        learning_language: cr.learning_language,
        base_language: cr.base_language,
        chat_room_mode: cr.chat_room_mode,
        last_message: m.content,
        last_message_author_kind: m.author_kind,
        last_message_user_display_name: m.user_display_name,
        last_message_user_id: m.user_id,
        last_message_inserted_at: m.inserted_at
      },
      order_by: [desc: m.inserted_at]
    )
    |> Repo.all()
  end

  def get_chat_room_with_messages_for_user(user_id, %{chat_room_id: id}) do
    result =
      [%{chat_room: chat_room} | _] =
      from(cr in ChatRoom,
        join: crm in ChatRoomMembership,
        on: cr.id == crm.chat_room_id,
        where: crm.user_id == ^user_id and cr.id == ^id,
        join: m in Message,
        on: m.chat_room_id == cr.id,
        left_join: u in User,
        on: m.user_id == u.id,
        order_by: [desc: m.inserted_at],
        select: %{
          chat_room: %{id: cr.id, name: cr.name},
          message: %{
            id: m.id,
            content: m.content,
            author_kind: m.author_kind,
            inserted_at: m.inserted_at,
            user_display_name: u.display_name,
            user_id: u.id
          }
        }
      )
      |> Repo.all()

    messages = result |> Enum.map(fn %{message: message} -> message end)

    %{chat_room: chat_room, messages: messages}
  end

  def get_messages(id) do
    Repo.all(from m in Message, where: m.chat_room_id == ^id, order_by: [asc: :inserted_at])
  end

  def create_chat_room(attrs) do
    %ChatRoom{}
    |> ChatRoom.changeset(attrs)
    |> Repo.insert()
  end

  def create_chat_room_membership(attrs) do
    %ChatRoomMembership{}
    |> ChatRoomMembership.changeset(attrs)
    |> Repo.insert()
  end

  def create_message(attrs) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
  end
end
