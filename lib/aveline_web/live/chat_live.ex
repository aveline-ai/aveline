defmodule AvelineWeb.ChatLive do
  alias Phoenix.LiveView.AsyncResult
  use AvelineWeb, :live_view
  import AvelineWeb.ChatRoomListComponent

  alias Aveline.Chat

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user

    # CONTINUE(Arie): I just wired up the SQL.
    #  - Continue with the `async_async` below, we need to set the `default_desktop_chat_room_id` accordingly.
    #  - Maybe in handle params (?) we'll need to fetch the chat room with the `id` param (or the default)
    #  - Tidy up the loading screens which currently look terrible, just say "loading". Even blank would be better. Skeleton loader would be premo!
    #  - Close the PR! Move on the chat itself.

    {:ok,
     socket
     |> assign(:selected_chat_room_id, nil)
     |> assign(:making_new_chat_room, false)
     |> assign(:current_user_id, current_user.id)
     |> assign(:chat_rooms, AsyncResult.loading())
     |> assign(:active_chat, AsyncResult.loading())}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    current_user = socket.assigns.current_user

    {:noreply,
     socket
     |> assign(selected_chat_room_id: id)
     |> assign(making_new_chat_room: false)
     |> start_async(:get_chat_rooms, fn ->
       get_chatrooms_with_last_message_and_default_desktop_chatroom(current_user.id)
     end)
     |> start_async(:get_active_chat, fn ->
       Chat.get_chat_room(%{user_id: current_user.id, chat_room_id: id})
     end)}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    current_user = socket.assigns.current_user
    parsed_uri = URI.parse(uri)

    making_new_chat_room = parsed_uri.path == ~p"/chat/new"

    {:noreply,
     socket
     |> assign(selected_chat_room_id: nil)
     |> assign(making_new_chat_room: making_new_chat_room)
     |> start_async(:get_chat_rooms, fn ->
       get_chatrooms_with_last_message_and_default_desktop_chatroom(current_user.id)
     end)}
  end

  @impl true
  def handle_async(:get_chat_rooms, {:ok, {fetched_chat_rooms, default_desktop_chat_room_id}}, socket) do
    %{current_user: current_user, chat_rooms: chat_rooms} = socket.assigns

    socket =
      socket
      |> assign(:chat_rooms, AsyncResult.ok(chat_rooms, {fetched_chat_rooms, default_desktop_chat_room_id}))

    # If we have a selected chat room, then the chat room is already being loaded in `handle_params`.
    if socket.assigns.selected_chat_room_id do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> start_async(:get_active_chat, fn ->
         Chat.get_chat_room(%{user_id: current_user.id, chat_room_id: default_desktop_chat_room_id})
       end)}
    end
  end

  @impl true
  def handle_async(:get_chat_rooms, {:exit, reason}, socket) do
    %{chat_rooms: chat_rooms} = socket.assigns
    {:noreply, socket |> assign(:chat_rooms, AsyncResult.failed(chat_rooms, {:exit, reason}))}
  end

  @impl true
  def handle_async(:get_active_chat, {:ok, fetched_active_chat}, socket) do
    %{active_chat: active_chat} = socket.assigns
    {:noreply, socket |> assign(:active_chat, AsyncResult.ok(active_chat, fetched_active_chat))}
  end

  @impl true
  def handle_async(:get_active_chat, {:exit, reason}, socket) do
    %{active_chat: active_chat} = socket.assigns
    {:noreply, socket |> assign(:active_chat, AsyncResult.failed(active_chat, {:exit, reason}))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-full w-full">
      <div class={[
        "border-r border-border-secondary w-full lg:w-80 lg:block",
        (@selected_chat_room_id || @making_new_chat_room) && "hidden"
      ]}>
        <.async_result :let={{chat_rooms, default_desktop_chat_room_id}} assign={@chat_rooms}>
          <:loading>Loading chat rooms...</:loading>
          <:failed :let={_reason}>There was an error loading chat rooms</:failed>
          <.chat_room_list
            chat_rooms={chat_rooms}
            selected_chat_room_id={@selected_chat_room_id}
            default_desktop_chat_room_id={default_desktop_chat_room_id}
            making_new_chat_room={@making_new_chat_room}
            current_user_id={@current_user_id}
            on_chat_room_click="select_chat_room"
            on_new_chat_room_click="new_chat_room"
          />
        </.async_result>
      </div>
      <div
        :if={!@making_new_chat_room}
        class={[
          "h-full flex-1",
          !@selected_chat_room_id && "hidden lg:block",
          @selected_chat_room_id && "block w-full"
        ]}
      >
        <.async_result :let={active_chat} :if={!@making_new_chat_room} assign={@active_chat}>
          <:loading>Loading chat...</:loading>
          <:failed :let={_reason}>There was an error loading chat</:failed>
          <h1 class="text-2xl font-bold">{active_chat.name}</h1>
        </.async_result>
      </div>
      <div :if={@making_new_chat_room} class="h-full flex-1">
        <h1 class="text-2xl font-bold">New Chat</h1>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("select_chat_room", %{"id" => id}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/chat/#{id}",
       replace: false
     )}
  end

  @impl true
  def handle_event("new_chat_room", _params, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/chat/new",
       replace: false
     )}
  end

  # Private

  defp get_chatrooms_with_last_message_and_default_desktop_chatroom(user_id) do
    chat_rooms = Chat.get_chat_rooms_with_last_message(%{user_id: user_id})
    default_desktop_chat_room_id = chat_rooms |> List.first() |> Map.get(:id)
    {chat_rooms, default_desktop_chat_room_id}
  end
end
