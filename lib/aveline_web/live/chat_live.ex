defmodule AvelineWeb.ChatLive do
  alias Phoenix.LiveView.AsyncResult
  use AvelineWeb, :live_view
  require Aveline.Enums.AuthorKind
  import AvelineWeb.ChatRoomListComponent
  import AvelineWeb.Ui.ChatMessageComponent
  alias Aveline.Chat
  alias Aveline.Enums

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:selected_chat_room_id, nil)
     |> assign(:making_new_chat_room, false)
     |> assign(:current_user_id, current_user.id)
     |> assign(:chat_rooms, AsyncResult.loading())
     |> assign(:active_chat_room, AsyncResult.loading())
     |> assign(:new_message_form, to_form(%{"message" => ""}))}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    current_user = socket.assigns.current_user

    {:noreply,
     socket
     |> assign(selected_chat_room_id: id)
     |> assign(:new_message_form, to_form(%{"message" => ""}))
     |> assign(making_new_chat_room: false)
     |> start_async(:get_chat_rooms, fn ->
       get_chatrooms_with_last_message_and_default_desktop_chatroom(current_user.id)
     end)
     |> start_async(:get_active_chat_room_with_messages, fn ->
       Chat.get_chat_room_with_messages_for_user(current_user.id, %{chat_room_id: id})
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
     |> assign(:new_message_form, to_form(%{"message" => ""}))
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
       |> start_async(:get_active_chat_room_with_messages, fn ->
         Chat.get_chat_room_with_messages_for_user(current_user.id, %{chat_room_id: default_desktop_chat_room_id})
       end)}
    end
  end

  @impl true
  def handle_async(:get_chat_rooms, {:exit, reason}, socket) do
    %{chat_rooms: chat_rooms} = socket.assigns
    {:noreply, socket |> assign(:chat_rooms, AsyncResult.failed(chat_rooms, {:exit, reason}))}
  end

  @impl true
  def handle_async(:get_active_chat_room_with_messages, {:ok, %{chat_room: chat_room, messages: messages}}, socket) do
    %{active_chat_room: active_chat_room} = socket.assigns

    {:noreply,
     socket
     |> assign(:active_chat_room, AsyncResult.ok(active_chat_room, chat_room))
     |> stream(:active_chat_room_messages, messages, reset: true)}
  end

  @impl true
  def handle_async(:get_active_chat_room_with_messages, {:exit, reason}, socket) do
    %{active_chat_room: active_chat_room} = socket.assigns
    {:noreply, socket |> assign(:active_chat_room, AsyncResult.failed(active_chat_room, {:exit, reason}))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-full w-full">
      <div class={[
        "border-r border-border-secondary w-full lg:w-80 xl:w-96 lg:block",
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
          "h-full w-full bg-white",
          !@selected_chat_room_id && "hidden lg:block",
          @selected_chat_room_id && "block w-full"
        ]}
      >
        <div class="flex flex-col h-full px-6 pt-4 justify-between">
          <.async_result :let={active_chat_room} :if={!@making_new_chat_room} assign={@active_chat_room}>
            <:loading>Loading chat...</:loading>
            <:failed :let={_reason}>There was an error loading chat</:failed>

            <h1 class="text-2xl font-bold sm:hidden">{active_chat_room.name}</h1>
            <%!-- Stream messages --%>
            <div id="message-container" phx-update="stream" class="flex flex-col gap-4 overflow-y-auto">
              <div
                :for={{dom_id, message} <- @streams.active_chat_room_messages}
                id={dom_id}
                class={"w-fit #{get_chat_message_self_alignment(@current_user_id, message.user_id)}"}
              >
                <.chat_message
                  message={message.content}
                  author_display_name={get_chat_message_author_display_name(@current_user_id, message)}
                  side={get_chat_message_side(@current_user_id, message.user_id)}
                />
              </div>
            </div>
          </.async_result>
          <div id="message-input-container" class="pb-4">
            <.form
              id={"new-message-form-#{@selected_chat_room_id}"}
              phx-submit="on_new_message_submit"
              phx-change="on_new_message_change"
              phx-window-keydown="on_new_message_window_keydown"
              for={@new_message_form}
              class="flex"
            >
              <textarea
                id={"new-message-textarea-#{@selected_chat_room_id}"}
                type="text"
                name="message"
                class="flex-1 rounded-lg min-h-24 max-h-96 hide-desktop-scrollbar pr-16 border-gray-300 focus:border-gray-300 focus:ring-0 resize-y"
                placeholder="Send a message"
                autocomplete="off"
                phx-update="ignore"
                phx-hook="ClearableAutosizingTextarea"
                autofocus
              >{Phoenix.HTML.Form.normalize_value("textarea", @new_message_form[:message].value)}</textarea>
              <button
                type="submit"
                class="absolute right-9 bottom-7 px-4 py-2 bg-brand-600 text-white rounded-lg hover:bg-brand-700"
              >
                Send
              </button>
            </.form>
          </div>
        </div>
      </div>
      <div :if={@making_new_chat_room} class="h-full flex-1">
        <h1 class="text-2xl font-bold">New Chat</h1>
      </div>
    </div>
    """
  end

  def handle_event("recover", params, socket) do
    message = params["message"]

    if(message) do
      {:noreply,
       socket
       |> assign(:new_message_form, to_form(%{"message" => message}))
       |> push_event("set-value", %{value: message})}
    else
      {:noreply,
       socket
       |> assign(:new_message_form, to_form(%{"message" => ""}))
       |> push_event("clear-value", %{})}
    end
  end

  @impl true
  def handle_event("on_new_message_submit", %{"message" => message}, socket) do
    {:noreply, handle_submit_new_message(socket)}
  end

  @impl true
  def handle_event("on_new_message_change", %{"message" => message}, socket) do
    {:noreply, socket |> assign(:new_message_form, to_form(%{"message" => message}))}
  end

  @impl true
  def handle_event("on_new_message_window_keydown", event, socket) do
    if event["key"] == "Enter" && event["metaKey"] do
      {:noreply, handle_submit_new_message(socket)}
    else
      {:noreply, socket}
    end
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

  ## Reusable Socket Helpers

  defp handle_submit_new_message(socket) do
    socket
    |> assign(:new_message_form, to_form(%{"message" => ""}))
    |> push_event("clear-value", %{})
  end

  ## Chat Room Helpers

  defp get_chatrooms_with_last_message_and_default_desktop_chatroom(user_id) do
    chat_rooms = Chat.get_chat_rooms_with_last_message_for_user(user_id)
    default_desktop_chat_room_id = chat_rooms |> List.first() |> Map.get(:id)
    {chat_rooms, default_desktop_chat_room_id}
  end

  ## Chat Message Helpers

  defp get_chat_message_author_display_name(current_user_id, %{
         user_id: user_id,
         author_kind: author_kind,
         user_display_name: user_display_name
       }) do
    cond do
      user_id == current_user_id ->
        "You"

      author_kind == Enums.AuthorKind.user() ->
        user_display_name

      author_kind == Enums.AuthorKind.ai() ->
        "Aveline"
    end
  end

  defp get_chat_message_side(current_user_id, message_user_id) do
    if message_user_id == current_user_id do
      "right"
    else
      "left"
    end
  end

  defp get_chat_message_self_alignment(current_user_id, message_user_id) do
    case get_chat_message_side(current_user_id, message_user_id) do
      "right" -> "self-end"
      "left" -> "self-start"
    end
  end
end
