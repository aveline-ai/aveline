defmodule AvelineWeb.ChatLive do
  use AvelineWeb, :live_view
  import AvelineWeb.ChatRoomListComponent

  alias Aveline.Chat

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user

    # CONTINUE(Arie): I just wired up the SQL.
    #  - Add `display_name` to user
    #  - Fetch that in: get_chat_rooms_with_last_message
    #  - Continue with the `async_async` below, we need to set the `default_desktop_chat_room_id` accordingly.
    #  - Maybe in handle params (?) we'll need to fetch the chat room with the `id` param (or the default)
    #  - Tidy up the loading screens which currently look terrible, just say "loading". Even blank would be better. Skeleton loader would be premo!
    #  - Use those new fetched fields in the chat room list component to properly render the badges.
    #  - Close the PR! Move on the chat itself.

    {:ok,
     socket
     |> stream_configure(:chat_rooms, [])
     |> assign(:selected_chat_room_id, nil)
     |> assign(:making_new_chat_room, false)
     |> assign(:default_desktop_chat_room_id, "1")
     |> assign_async(:chat_rooms, fn ->
       {:ok, %{chat_rooms: Chat.get_chat_rooms_with_last_message(%{user_id: current_user.id})}}
     end)}
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
        "border-r border-border-secondary w-full lg:w-80 lg:block",
        (@selected_chat_room_id || @making_new_chat_room) && "hidden"
      ]}>
        <.async_result :let={chat_rooms} assign={@chat_rooms}>
          <:loading>Loading chat rooms...</:loading>
          <:failed :let={_reason}>There was an error loading chat rooms</:failed>
          <.chat_room_list
            chat_rooms={chat_rooms}
            selected_chat_room_id={@selected_chat_room_id}
            default_desktop_chat_room_id={@default_desktop_chat_room_id}
            making_new_chat_room={@making_new_chat_room}
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
