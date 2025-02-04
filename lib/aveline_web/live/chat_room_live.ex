defmodule AvelineWeb.ChatRoomLive do
  use AvelineWeb, :live_view
  alias Aveline.ChatRoom

  @impl true
  def mount(%{"id" => chat_room_id}, _session, socket) do
    case ChatRoom.get_chat_room(chat_room_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Chat room not found")
         |> redirect(to: ~p"/")}

      chat_room ->
        connected = connected?(socket)

        {:ok,
         socket
         |> assign(chat_room: chat_room, connected: connected)
         |> assign_async(:messages, fn ->
           {:ok, %{messages: ChatRoom.get_messages(chat_room.id)}}
         end)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1>{@chat_room.name}</h1>
      <.async_result :let={messages} assign={@messages}>
        <:loading>
          <div class="animate-pulse">...</div>
        </:loading>
        <:failed :let={_failure}>
          <div class="text-red-500">Error loading messages</div>
        </:failed>
        <div>
          Messages:
          <%= for message <- messages do %>
            <div>{message.content}</div>
          <% end %>
        </div>
      </.async_result>
    </div>
    """
  end
end
