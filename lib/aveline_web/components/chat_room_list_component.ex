defmodule AvelineWeb.ChatRoomListComponent do
  @moduledoc """
  This component is used to display a list of chat rooms.
  """
  use Phoenix.Component

  attr :chat_rooms, :list, required: true
  attr :selected_chat_room_id, :string, default: nil
  attr :default_desktop_chat_room_id, :string, default: nil
  attr :making_new_chat_room, :boolean, default: false
  attr :on_chat_room_click, :any, required: true
  attr :on_new_chat_room_click, :any, required: true

  def chat_room_list(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <div class="overflow-y-auto flex-1">
        <%= for chat_room <- @chat_rooms do %>
          <button
            phx-click={@on_chat_room_click}
            phx-value-id={chat_room.id}
            class={[
              "w-full p-4 text-left hover:bg-gray-50",
              @selected_chat_room_id == chat_room.id && "bg-gray-100",
              !@selected_chat_room_id && !@making_new_chat_room && @default_desktop_chat_room_id == chat_room.id &&
                "lg:bg-gray-100"
            ]}
          >
            <div class="font-medium">{chat_room.name}</div>
            <div class="text-sm text-gray-500">{chat_room.last_message}</div>
          </button>
        <% end %>
      </div>
      <button phx-click={@on_new_chat_room_click} class="w-full p-4 text-left">
        <div class="font-medium">New Chat</div>
      </button>
    </div>
    """
  end
end
