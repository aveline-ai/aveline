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
     |> assign(:making_new_chat_room, false)
     |> assign(default_desktop_chat_room_id: "1")}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    {:noreply,
     socket
     |> assign(selected_chat_room_id: id)
     |> assign(making_new_chat_room: false)}
  end

  def handle_params(_params, uri, socket) do
    parsed_uri = URI.parse(uri)

    if parsed_uri.path == ~p"/chat/new" do
      {:noreply,
       socket
       |> assign(selected_chat_room_id: nil)
       |> assign(making_new_chat_room: true)}
    else
      {:noreply,
       socket
       |> assign(selected_chat_room_id: nil)
       |> assign(making_new_chat_room: false)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-full w-full">
      <div class={[
        "border-r border-gray-200 w-full lg:w-80 lg:block",
        (@selected_chat_room_id || @making_new_chat_room) && "hidden"
      ]}>
        <.chat_room_list
          chat_rooms={@chat_rooms}
          selected_chat_room_id={@selected_chat_room_id}
          default_desktop_chat_room_id={@default_desktop_chat_room_id}
          making_new_chat_room={@making_new_chat_room}
          on_chat_room_click="select_chat_room"
          on_new_chat_room_click="new_chat_room"
        />
      </div>
      <div
        :if={!@making_new_chat_room}
        class={[
          "h-full flex-1",
          !@selected_chat_room_id && "hidden lg:block",
          @selected_chat_room_id && "block w-full"
        ]}
      >
        <h1 class="text-2xl font-bold">Chat ID: {@selected_chat_room_id || @default_desktop_chat_room_id}</h1>
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
end
