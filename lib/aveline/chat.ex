defmodule Aveline.Chat do
  @moduledoc """
  The ChatRoom context handles chat room management, memberships, and messages.
  """

  import Ecto.Query
  alias Aveline.Account.User
  alias Aveline.Chat.ChatRoom
  alias Aveline.Chat.ChatRoomMembership
  alias Aveline.Chat.Message
  alias Aveline.EventBus
  alias Aveline.Repo
  alias Aveline.Structs.EnrichedChatRoomMessage

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

  def get_chat_room_with_enriched_messages_for_user(user_id, %{chat_room_id: id}) do
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
        order_by: [asc: m.inserted_at],
        select: %{
          chat_room: %{
            id: cr.id,
            name: cr.name,
            mode: cr.chat_room_mode,
            base_language: cr.base_language,
            learning_language: cr.learning_language
          },
          enriched_message: %{
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

    enriched_messages =
      result
      |> Enum.map(fn %{enriched_message: enriched_message} ->
        %EnrichedChatRoomMessage{
          id: enriched_message.id,
          content: enriched_message.content,
          author_kind: enriched_message.author_kind,
          inserted_at: enriched_message.inserted_at,
          user_display_name: enriched_message.user_display_name,
          user_id: enriched_message.user_id
        }
      end)

    %{chat_room: chat_room, enriched_messages: enriched_messages}
  end

  def get_messages_for_ai_completion(%{message_id: message_id, message_limit: message_limit}) do
    # Use a subquery to get messages older than the reference message in a single query
    from(m in Message,
      join:
        ref in subquery(
          from rm in Message,
            where: rm.id == ^message_id,
            select: %{
              chat_room_id: rm.chat_room_id,
              inserted_at: rm.inserted_at
            }
        ),
      on: m.chat_room_id == ref.chat_room_id and m.inserted_at <= ref.inserted_at,
      left_join: u in User,
      on: m.user_id == u.id,
      order_by: [desc: m.inserted_at],
      limit: ^message_limit,
      select: %{
        content: m.content,
        author_kind: m.author_kind,
        inserted_at: m.inserted_at,
        user_display_name: u.display_name,
        user_id: u.id
      }
    )
    |> Repo.all()
  end

  def insert_chat_message_for_ai_and_broadcast_enriched_message!(%{chat_room_id: chat_room_id, content: content}) do
    message =
      Message.new_message_for_ai_changeset(%{chat_room_id: chat_room_id}, content)
      |> Repo.insert!()

    enriched_chat_room_message = %EnrichedChatRoomMessage{
      id: message.id,
      content: message.content,
      author_kind: message.author_kind,
      inserted_at: message.inserted_at,
      user_id: nil,
      user_display_name: nil
    }

    EventBus.broadcast!(
      {:chatroom, chat_room_id},
      :new_message,
      enriched_chat_room_message
    )

    {:ok, enriched_chat_room_message}
  end

  def insert_chat_message_for_user_and_broadcast_enriched_message!(
        %{user_id: user_id, chat_room_id: chat_room_id},
        content
      ) do
    message =
      Message.new_message_for_user_id_changeset(%{user_id: user_id, chat_room_id: chat_room_id}, content)
      |> Repo.insert!()

    user = Repo.get!(User, user_id)

    enriched_chat_room_message = %EnrichedChatRoomMessage{
      id: message.id,
      content: message.content,
      author_kind: message.author_kind,
      inserted_at: message.inserted_at,
      user_display_name: user.display_name,
      user_id: user.id
    }

    EventBus.broadcast!(
      {:chatroom, chat_room_id},
      :new_message,
      enriched_chat_room_message
    )

    enriched_chat_room_message
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
end
