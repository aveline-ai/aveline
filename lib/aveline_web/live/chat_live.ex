defmodule AvelineWeb.ChatLive do
  alias Phoenix.LiveView.AsyncResult
  use AvelineWeb, :live_view
  require Aveline.Enums.AuthorKind
  require Aveline.Enums.ChatRoomMode
  import AvelineWeb.ChatRoomListComponent
  import AvelineWeb.ChatRoomListSkeletonComponent
  import AvelineWeb.Ui.ChatMessageComponent
  import AvelineWeb.Ui.LoadingSpinnerComponent
  alias Aveline.Chat
  alias Aveline.Enums
  alias Aveline.EventBus
  alias Aveline.OpenAi
  alias Aveline.Structs.EnrichedChatRoomMessage
  alias AvelineWeb.Helpers

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:chat_id_from_path, nil)
     |> assign(:active_chat_room_id, nil)
     |> assign(:making_new_chat_room, false)
     |> assign(:chat_rooms, AsyncResult.loading())
     |> assign(:active_chat_room, AsyncResult.loading())
     |> assign(:new_message_form, to_form(%{"message" => ""}))
     |> assign(:new_sent_message_ids, MapSet.new())}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    current_user = socket.assigns.current_user

    {:noreply,
     socket
     |> assign(chat_id_from_path: id)
     |> assign(:new_message_form, to_form(%{"message" => ""}))
     |> assign(making_new_chat_room: false)
     |> assign(:active_chat_room_last_enriched_message, nil)
     |> start_async(:get_chat_rooms, fn ->
       Chat.get_chat_rooms_with_last_message_for_user(current_user.id)
     end)
     |> start_async(:get_active_chat_room_with_enriched_messages, fn ->
       Chat.get_chat_room_with_enriched_messages_for_user(current_user.id, %{chat_room_id: id})
     end)}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    current_user = socket.assigns.current_user
    parsed_uri = URI.parse(uri)

    making_new_chat_room = parsed_uri.path == ~p"/chat/new"

    {:noreply,
     socket
     |> assign(:new_message_form, to_form(%{"message" => ""}))
     |> assign(:chat_id_from_path, nil)
     |> assign(making_new_chat_room: making_new_chat_room)
     |> start_async(:get_chat_rooms_and_set_active_chat_room_id_to_default_desktop_chatroom, fn ->
       Chat.get_chat_rooms_with_last_message_for_user(current_user.id)
     end)}
  end

  @impl true
  def handle_async(:get_chat_rooms, {:ok, fetched_chat_rooms}, socket) do
    %{chat_rooms: chat_rooms} = socket.assigns

    fetched_chat_rooms
    |> Enum.each(fn fetched_chat_room ->
      EventBus.subscribe({:chatroom, fetched_chat_room.id})
    end)

    {:noreply,
     socket
     |> assign(:chat_rooms, AsyncResult.ok(chat_rooms, fetched_chat_rooms))}
  end

  @impl true
  def handle_async(:get_chat_rooms, {:exit, reason}, socket) do
    %{chat_rooms: chat_rooms} = socket.assigns
    {:noreply, socket |> assign(:chat_rooms, AsyncResult.failed(chat_rooms, {:exit, reason}))}
  end

  @impl true
  def handle_async(
        :get_chat_rooms_and_set_active_chat_room_id_to_default_desktop_chatroom,
        {:ok, fetched_chat_rooms},
        socket
      ) do
    %{chat_rooms: chat_rooms, current_user: current_user} = socket.assigns
    [%{id: default_desktop_chat_room_id} | _] = fetched_chat_rooms

    fetched_chat_rooms
    |> Enum.each(fn fetched_chat_room ->
      EventBus.subscribe({:chatroom, fetched_chat_room.id})
    end)

    {:noreply,
     socket
     |> assign(:chat_rooms, AsyncResult.ok(chat_rooms, fetched_chat_rooms))
     |> assign(:active_chat_room_id, default_desktop_chat_room_id)
     |> start_async(:get_active_chat_room_with_enriched_messages, fn ->
       Chat.get_chat_room_with_enriched_messages_for_user(current_user.id, %{chat_room_id: default_desktop_chat_room_id})
     end)}
  end

  @impl true
  def handle_async(
        :get_chat_rooms_and_set_active_chat_room_id_to_default_desktop_chatroom,
        {:exit, reason},
        socket
      ) do
    %{chat_rooms: chat_rooms} = socket.assigns
    {:noreply, socket |> assign(:chat_rooms, AsyncResult.failed(chat_rooms, {:exit, reason}))}
  end

  @impl true
  def handle_async(
        :get_active_chat_room_with_enriched_messages,
        {:ok, %{chat_room: fetched_chat_room, enriched_messages: fetched_enriched_messages}},
        socket
      ) do
    %{active_chat_room: active_chat_room, current_user: %{id: current_user_id}} = socket.assigns

    %{streamable_ui_elements: streamable_ui_elements, last_enriched_message: last_enriched_message} =
      get_streamable_ui_elements_and_last_enriched_messsage(
        :initial_fetched_enriched_messages,
        fetched_enriched_messages,
        current_user_id
      )

    {:noreply,
     socket
     |> assign(:active_chat_room, AsyncResult.ok(active_chat_room, fetched_chat_room))
     |> assign(:active_chat_room_id, fetched_chat_room.id)
     |> assign(:active_chat_room_last_enriched_message, last_enriched_message)
     |> stream(:active_chat_room_streamable_ui_elements, streamable_ui_elements, reset: true)}
  end

  @impl true
  def handle_async(:get_active_chat_room_with_enriched_messages, {:exit, reason}, socket) do
    %{active_chat_room: active_chat_room} = socket.assigns
    {:noreply, socket |> assign(:active_chat_room, AsyncResult.failed(active_chat_room, {:exit, reason}))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-full w-full">
      <div class={[
        "border-r border-border-secondary w-full lg:w-80 xl:w-96 lg:block flex-shrink-0",
        (@chat_id_from_path || @making_new_chat_room) && "hidden"
      ]}>
        <.async_result :let={chat_rooms} assign={@chat_rooms}>
          <:loading><.chat_room_list_skeleton /></:loading>
          <:failed :let={_reason}>There was an error loading chat rooms</:failed>
          <.chat_room_list
            chat_rooms={chat_rooms}
            active_chat_room_id={@active_chat_room_id}
            making_new_chat_room={@making_new_chat_room}
            current_user_id={@current_user.id}
            on_chat_room_click="select_chat_room"
            on_new_chat_room_click="new_chat_room"
          />
        </.async_result>
      </div>
      <div
        :if={!@making_new_chat_room}
        class={[
          "h-full w-full bg-white block lg:!block",
          !@chat_id_from_path && "hidden"
        ]}
      >
        <div class="flex flex-col h-full px-6 pt-4 justify-between">
          <.async_result :let={active_chat_room} :if={!@making_new_chat_room} assign={@active_chat_room}>
            <:loading><.loading_spinner /></:loading>
            <:failed :let={_reason}>There was an error loading chat</:failed>
            <%!-- Stream messages --%>
            <div
              id="message-container"
              phx-update="stream"
              phx-hook="ScrollToBottom"
              class="flex flex-col gap-1 overflow-y-auto hide-desktop-scrollbar"
            >
              <div
                :for={{dom_id, streamable_ui_element} <- @streams.active_chat_room_streamable_ui_elements}
                id={dom_id}
                class={"w-fit max-w-[80%] #{streamable_ui_element.chat_message_self_alignment}"}
              >
                <.chat_message
                  side={streamable_ui_element.chat_message_side}
                  message={streamable_ui_element.content}
                  author_display_name={streamable_ui_element.author_display_name}
                  should_display_author_display_name={streamable_ui_element.should_display_author_display_name}
                  should_display_learn_action={streamable_ui_element.should_display_learn_action}
                />
              </div>
            </div>
          </.async_result>
          <div id="message-input-container" class="pb-4 mt-4">
            <.form
              id={"new-message-form-#{@chat_id_from_path}"}
              phx-submit="on_new_message_submit"
              phx-change="on_new_message_change"
              for={@new_message_form}
              class="flex"
            >
              <textarea
                id={"new-message-textarea-#{@chat_id_from_path}-#{Enum.count(@new_sent_message_ids)}"}
                type="text"
                name="message"
                class="flex-1 rounded-lg min-h-24 max-h-96 hide-desktop-scrollbar pr-16 border-gray-300 focus:border-gray-300 focus:ring-0 resize-y disabled:opacity-50 disabled:cursor-not-allowed"
                placeholder="Send a message"
                autocomplete="off"
                phx-update="ignore"
                phx-hook="EnhancedTextarea"
                autofocus
              >{Phoenix.HTML.Form.normalize_value("textarea", @new_message_form[:message].value)}</textarea>
              <button
                type="submit"
                disabled={@new_message_form[:message].value == ""}
                class="absolute right-9 bottom-7 px-4 py-2 bg-brand-600 text-white rounded-lg hover:bg-brand-700 disabled:opacity-50 disabled:cursor-not-allowed"
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

  @impl true
  def handle_event("on_new_message_submit", _, socket) do
    %{
      current_user: current_user,
      active_chat_room_id: active_chat_room_id,
      active_chat_room: active_chat_room,
      new_message_form: new_message_form,
      new_sent_message_ids: new_sent_message_ids
    } = socket.assigns

    new_message = new_message_form[:message].value
    new_message_trimmed_length = new_message |> String.trim() |> String.length()

    if new_message_trimmed_length == 0 do
      {:noreply, socket}
    else
      enriched_chat_room_message =
        Chat.insert_chat_message_for_user_and_broadcast_enriched_message!(
          %{user_id: current_user.id, chat_room_id: active_chat_room_id},
          new_message
        )

      new_streamable_ui_element =
        get_streamable_ui_element_from_enriched_chat_message(%{
          enriched_chat_room_message: enriched_chat_room_message,
          last_enriched_message: socket.assigns.active_chat_room_last_enriched_message,
          current_user_id: current_user.id
        })

      conditionally_start_async_task_to_generate_ai_response(%{
        active_chat_room: active_chat_room,
        enriched_chat_room_message: enriched_chat_room_message,
        current_user: current_user
      })

      {:noreply,
       socket
       |> assign(:new_sent_message_ids, MapSet.put(new_sent_message_ids, enriched_chat_room_message.id))
       |> assign(:new_message_form, to_form(%{"message" => ""}))
       |> assign(:active_chat_room_last_enriched_message, enriched_chat_room_message)
       |> stream_insert(:active_chat_room_streamable_ui_elements, new_streamable_ui_element)}
    end
  end

  @impl true
  def handle_event("on_new_message_change", %{"message" => message}, socket) do
    {:noreply, socket |> assign(:new_message_form, to_form(%{"message" => message}))}
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

  # Handle Event Bus messages

  @impl true
  def handle_info(
        %{
          kind: :new_message,
          chat_room_id: chat_room_id,
          enriched_chat_room_message: enriched_chat_room_message = %EnrichedChatRoomMessage{}
        },
        socket
      ) do
    %{
      current_user: current_user,
      active_chat_room_id: active_chat_room_id,
      chat_rooms: chat_rooms,
      new_sent_message_ids: new_sent_message_ids,
      active_chat_room_last_enriched_message: active_chat_room_last_enriched_message
    } = socket.assigns

    # Handle inserting the message into the chat room.
    socket =
      cond do
        # Ignore messages from other chat rooms, we only want to stream messages for the active chat room.
        active_chat_room_id != chat_room_id ->
          socket

        # Ignore new messages we sent because those get added to the UI immediately after `on_new_message_submit`.
        MapSet.member?(new_sent_message_ids, enriched_chat_room_message.id) ->
          socket

        # For messages from the AI or other users, we need to update the UI but we don't need to trigger an AI response.
        true ->
          new_streamable_ui_element =
            get_streamable_ui_element_from_enriched_chat_message(%{
              enriched_chat_room_message: enriched_chat_room_message,
              last_enriched_message: active_chat_room_last_enriched_message,
              current_user_id: current_user.id
            })

          socket
          |> stream_insert(:active_chat_room_streamable_ui_elements, new_streamable_ui_element)
          |> assign(:active_chat_room_last_enriched_message, enriched_chat_room_message)
      end

    # Handle updating the last message for each chat room
    socket =
      case chat_rooms do
        %AsyncResult{ok?: true, result: chat_rooms} ->
          chat_rooms = update_chat_room_last_enriched_message(chat_rooms, chat_room_id, enriched_chat_room_message)

          socket
          |> assign(:chat_rooms, AsyncResult.ok(chat_rooms))

        _ ->
          socket
      end

    {:noreply, socket}
  end

  # Private

  ## AI Helpers

  defp conditionally_start_async_task_to_generate_ai_response(%{
         active_chat_room: %AsyncResult{ok?: true, result: active_chat_room},
         enriched_chat_room_message: enriched_chat_room_message,
         current_user: current_user
       }) do
    if should_generate_ai_response?(active_chat_room.mode) do
      Task.Supervisor.start_child(Aveline.TaskSupervisor, fn ->
        generate_ai_response_for_message_and_broadcast_enriched_message!(%{
          chat_room_id: active_chat_room.id,
          chat_room_mode: active_chat_room.mode,
          chat_room_base_language: active_chat_room.base_language,
          chat_room_learning_language: active_chat_room.learning_language,
          message_id: enriched_chat_room_message.id,
          user_id: current_user.id,
          user_local_timezone: current_user.local_timezone
        })
      end)

      true
    end
  end

  defp conditionally_start_async_task_to_generate_ai_response(_), do: false

  defp generate_ai_response_for_message_and_broadcast_enriched_message!(%{
         chat_room_id: chat_room_id,
         chat_room_mode: chat_room_mode,
         chat_room_base_language: chat_room_base_language,
         chat_room_learning_language: chat_room_learning_language,
         message_id: message_id,
         user_id: user_id,
         user_local_timezone: user_local_timezone
       }) do
    open_ai_response =
      OpenAi.generate_chat_completion!(%{
        chat_room_id: chat_room_id,
        chat_room_mode: chat_room_mode,
        chat_room_base_language: chat_room_base_language,
        chat_room_learning_language: chat_room_learning_language,
        message_id: message_id,
        user_id: user_id,
        user_local_timezone: user_local_timezone
      })

    Chat.insert_chat_message_for_ai_and_broadcast_enriched_message!(%{
      chat_room_id: chat_room_id,
      content: open_ai_response
    })
  end

  # Checks that the mode is one that warrants an AI response.
  defp should_generate_ai_response?(mode) do
    Enums.ChatRoomMode.map!(mode, %{
      Enums.ChatRoomMode.group_chat() => true,
      Enums.ChatRoomMode.private_chat() => true
    })
  end

  ## Streamable UI element helpers

  defp get_streamable_ui_elements_and_last_enriched_messsage(
         :initial_fetched_enriched_messages,
         fetched_enriched_messages,
         current_user_id
       ) do
    %{last_enriched_message: last_enriched_message, streamable_ui_elements: streamable_ui_elements} =
      fetched_enriched_messages
      |> Enum.reduce(
        %{streamable_ui_elements: [], last_enriched_message: nil},
        fn enriched_chat_room_message = %EnrichedChatRoomMessage{}, acc ->
          new_streamable_ui_element =
            get_streamable_ui_element_from_enriched_chat_message(%{
              enriched_chat_room_message: enriched_chat_room_message,
              last_enriched_message: acc.last_enriched_message,
              current_user_id: current_user_id
            })

          # Insert into front of list for effeciency, note this will reverse the order.
          %{
            last_enriched_message: enriched_chat_room_message,
            streamable_ui_elements: [new_streamable_ui_element | acc.streamable_ui_elements]
          }
        end
      )

    # While we construct the streamable UI elements, we build the list in reverse order, therefore we reverse it again.
    %{streamable_ui_elements: Enum.reverse(streamable_ui_elements), last_enriched_message: last_enriched_message}
  end

  defp get_streamable_ui_element_from_enriched_chat_message(%{
         enriched_chat_room_message: enriched_chat_room_message,
         last_enriched_message: last_enriched_message,
         current_user_id: current_user_id
       }) do
    chat_message_side = get_chat_message_side(current_user_id, enriched_chat_room_message.user_id)
    chat_message_self_alignment = get_chat_message_self_alignment(chat_message_side)

    author_display_name =
      Helpers.get_display_name(
        enriched_chat_room_message.author_kind,
        enriched_chat_room_message.user_id == current_user_id,
        enriched_chat_room_message.user_display_name
      )

    should_display_author_display_name =
      !Helpers.same_author?(last_enriched_message, enriched_chat_room_message)

    should_display_learn_action =
      enriched_chat_room_message.author_kind == Enums.AuthorKind.ai()

    %{
      id: enriched_chat_room_message.id,
      author_kind: enriched_chat_room_message.author_kind,
      author_display_name: author_display_name,
      should_display_author_display_name: should_display_author_display_name,
      content: enriched_chat_room_message.content,
      chat_message_side: chat_message_side,
      chat_message_self_alignment: chat_message_self_alignment,
      should_display_learn_action: should_display_learn_action
    }
  end

  defp get_chat_message_side(current_user_id, message_user_id) when message_user_id == current_user_id, do: "right"
  defp get_chat_message_side(_current_user_id, _message_user_id), do: "left"

  defp get_chat_message_self_alignment("left"), do: "self-start"
  defp get_chat_message_self_alignment("right"), do: "self-end"

  defp update_chat_room_last_enriched_message(chat_rooms, chat_room_id, enriched_chat_room_message) do
    chat_rooms
    |> Enum.map(fn chat_room ->
      if chat_room.id == chat_room_id do
        %{
          chat_room
          | last_message: enriched_chat_room_message.content,
            last_message_author_kind: enriched_chat_room_message.author_kind,
            last_message_user_display_name: enriched_chat_room_message.user_display_name,
            last_message_user_id: enriched_chat_room_message.user_id,
            last_message_inserted_at: enriched_chat_room_message.inserted_at
        }
      else
        chat_room
      end
    end)
  end
end
