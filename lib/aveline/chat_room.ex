defmodule Aveline.Chat do
  @moduledoc """
  The ChatRoom context handles chat room management, memberships, and messages.
  """

  import Ecto.Query
  alias Aveline.Chat.ChatRoom
  alias Aveline.Chat.ChatRoomMembership
  alias Aveline.Chat.Message
  alias Aveline.Repo

  def get_chat_room(%{user_id: user_id, chat_room_id: id}) do
    ChatRoom
    |> user_chat_rooms_query(user_id)
    |> Repo.get(id)
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

  defp user_chat_rooms_query(query, user_id) do
    from(cr in query,
      join: crm in ChatRoomMembership,
      on: cr.id == crm.chat_room_id,
      where: crm.user_id == ^user_id
    )
  end
end
