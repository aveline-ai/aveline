defmodule AvelineWeb.ChatLive do
  use AvelineWeb, :live_view
  import AvelineWeb.ChatRoomListComponent

  @impl true
  def mount(_params, _session, socket) do
    harcoded_chat_rooms = [
      %{id: "1", name: "Chat 1", last_message: "Hello, how are you?"},
      %{id: "2", name: "Chat 2", last_message: "Hello, how are you?"},
      %{id: "3", name: "Chat 3", last_message: "Hello, how are you?"}
    ]

    {:ok,
     socket
     |> assign(chat_rooms: harcoded_chat_rooms)
     |> assign(selected_chat_room_id: nil)
     |> assign(default_desktop_chat_room_id: "1")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-full w-full">
      <div class={[
        "border-r border-gray-200",
        @selected_chat_room_id && "hidden lg:block lg:w-96",
        !@selected_chat_room_id && "w-full lg:w-96"
      ]}>
        <.chat_room_list
          chat_rooms={@chat_rooms}
          selected_chat_room_id={@selected_chat_room_id}
          on_chat_room_click="select_chat_room"
          on_new_chat_room_click="new_chat_room"
        />
      </div>
      <div class="hidden lg:block h-full flex-1">
        <h1 class="text-2xl font-bold">Chat</h1>
      </div>
    </div>
    """
  end

  def handle_event("select_chat_room", %{"id" => id}, socket) do
    {:noreply, socket |> assign(selected_chat_room_id: id)}
  end

  def handle_event("new_chat_room", _params, socket) do
    {:noreply, socket}
  end
end
