defmodule AvelineWeb.ChatRoomListComponent do
  @moduledoc """
  This component is used to display a list of chat rooms.
  """
  use Phoenix.Component

  require Aveline.Enums.ChatRoomMode
  require Aveline.Enums.Language
  require Aveline.Enums.AuthorKind

  import AvelineWeb.Ui.BadgeComponent, only: [badge_color_with_icon: 1]
  import AvelineWeb.Ui.IconButton, only: [icon_button: 1]

  alias Aveline.Enums

  attr :chat_rooms, :list, required: true
  attr :selected_chat_room_id, :string, default: nil
  attr :default_desktop_chat_room_id, :string, default: nil
  attr :making_new_chat_room, :boolean, default: false
  attr :on_chat_room_click, :any, required: true
  attr :on_new_chat_room_click, :any, required: true
  attr :current_user_id, :string, required: true

  def chat_room_list(assigns) do
    ~H"""
    <div class="relative flex flex-col h-full">
      <div class="overflow-y-auto flex-1">
        <%= for chat_room <- @chat_rooms do %>
          <div
            phx-click={@on_chat_room_click}
            phx-value-id={chat_room.id}
            class={[
              "flex flex-col gap-4 w-full p-4 text-left border-b border-border-secondary",
              @selected_chat_room_id == chat_room.id && "bg-gray-100",
              !@selected_chat_room_id && !@making_new_chat_room && @default_desktop_chat_room_id == chat_room.id &&
                "lg:bg-gray-100"
            ]}
          >
            <div class="flex flex-col items-start gap-1">
              <div class="font-medium text-sm">{chat_room.name}</div>
              <div class="flex flex-row gap-1">
                <.badge_color_with_icon
                  label={badge_pretty_print!(chat_room.learning_language, :capitalize)}
                  color="gray"
                  icon="hero-language"
                />
                <.badge_color_with_icon
                  label={badge_pretty_print!(chat_room.chat_room_mode, :capitalize)}
                  color={get_chat_room_mode_badge_color_scheme(chat_room.chat_room_mode)}
                  icon={get_chat_room_mode_badge_icon(chat_room.chat_room_mode)}
                />
              </div>
            </div>
            <div class="text-sm text-text-tertiary">
              <span :if={chat_room.last_message_author_kind == Enums.AuthorKind.user()}>
                <span :if={chat_room.last_message_user_id == @current_user_id} class="font-bold">
                  You:
                </span>
                <span :if={chat_room.last_message_user_id != @current_user_id} class="font-bold">
                  {chat_room.last_message_user_display_name}:
                </span>
                <span>{chat_room.last_message}</span>
              </span>
              <span :if={chat_room.last_message_author_kind == Enums.AuthorKind.ai()}>
                <span class="font-bold">Aveline:</span>
                <span>{chat_room.last_message}</span>
              </span>
            </div>
          </div>
        <% end %>
      </div>

      <.icon_button
        icon="hero-pencil-square"
        class="absolute bottom-4 right-4 p-3"
        on_click={@on_new_chat_room_click}
        hierarchy="primary"
      />
    </div>
    """
  end

  # Private

  defp get_chat_room_mode_badge_color_scheme(chat_room_mode) do
    case chat_room_mode do
      Enums.ChatRoomMode.book_buddy() -> "orange"
      Enums.ChatRoomMode.chat_companion() -> "blue-light"
    end
  end

  defp badge_pretty_print!(Enums.ChatRoomMode.book_buddy(), :capitalize), do: "Book Buddy"
  defp badge_pretty_print!(Enums.ChatRoomMode.chat_companion(), :capitalize), do: "Chat Companion"
  defp badge_pretty_print!(Enums.Language.english(), :capitalize), do: "English"
  defp badge_pretty_print!(Enums.Language.french(), :capitalize), do: "French"
  defp badge_pretty_print!(Enums.Language.spanish(), :capitalize), do: "Spanish"
  defp badge_pretty_print!(Enums.Language.german(), :capitalize), do: "German"
  defp badge_pretty_print!(Enums.Language.italian(), :capitalize), do: "Italian"
  defp badge_pretty_print!(Enums.Language.japanese(), :capitalize), do: "Japanese"
  defp badge_pretty_print!(Enums.Language.korean(), :capitalize), do: "Korean"

  defp get_chat_room_mode_badge_icon(Enums.ChatRoomMode.book_buddy()), do: "hero-book-open"
  defp get_chat_room_mode_badge_icon(Enums.ChatRoomMode.chat_companion()), do: "hero-chat-bubble-left-right"
end
