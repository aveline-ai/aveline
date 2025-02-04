defmodule Aveline.ChatRoom do
  @moduledoc """
  The ChatRoom context handles chat room management, memberships, and messages.
  """

  alias Aveline.ChatRoom.ChatRoom
  alias Aveline.ChatRoom.ChatRoomMembership
  alias Aveline.ChatRoom.Message
  alias Aveline.Repo

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
