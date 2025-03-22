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
  attr :active_chat_room_id, :string, default: nil
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
              @active_chat_room_id == chat_room.id && "lg:bg-background-active"
            ]}
          >
            <div class="flex flex-col items-start gap-1">
              <div class="font-medium text-sm">{chat_room.name}</div>
              <div class="flex flex-row gap-1">
                <.badge_color_with_icon
                  label={get_language_badge_label!(chat_room.learning_language)}
                  color="gray"
                  icon="hero-language"
                />
                <.badge_color_with_icon
                  label={get_chat_room_mode_badge_label!(chat_room.chat_room_mode)}
                  color={get_chat_room_mode_badge_color_scheme!(chat_room.chat_room_mode)}
                  icon={get_chat_room_mode_badge_icon!(chat_room.chat_room_mode)}
                />
              </div>
            </div>
            <div class="text-sm text-text-tertiary h-10">
              <span>
                <span class="font-bold">
                  {get_display_name(
                    chat_room.last_message_author_kind,
                    chat_room.last_message_user_id == @current_user_id,
                    chat_room.last_message_user_display_name
                  )}:
                </span>
                <span>{get_truncated_message(chat_room.last_message)}</span>
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

  defp get_display_name(_, true, _), do: "You"

  defp get_display_name(author_kind, _, user_display_name) do
    Enums.AuthorKind.map!(author_kind, %{
      Enums.AuthorKind.user() => user_display_name,
      Enums.AuthorKind.ai() => "Aveline"
    })
  end

  defp get_truncated_message(message) do
    truncate_length = 70

    if String.length(message) > truncate_length do
      message
      |> String.slice(0, truncate_length)
      |> String.trim()
      |> String.pad_trailing(truncate_length + 3, "...")
    else
      message
    end
  end

  defp get_chat_room_mode_badge_color_scheme!(chat_room_mode) do
    Enums.ChatRoomMode.map!(chat_room_mode, %{
      Enums.ChatRoomMode.group_chat() => "orange",
      Enums.ChatRoomMode.private_chat() => "blue-light"
    })
  end

  defp get_language_badge_label!(language) do
    Enums.Language.map!(language, %{
      Enums.Language.english() => "English",
      Enums.Language.french() => "French",
      Enums.Language.spanish() => "Spanish",
      Enums.Language.german() => "German",
      Enums.Language.italian() => "Italian",
      Enums.Language.japanese() => "Japanese",
      Enums.Language.korean() => "Korean"
    })
  end

  defp get_chat_room_mode_badge_label!(chat_room_mode) do
    Enums.ChatRoomMode.map!(chat_room_mode, %{
      Enums.ChatRoomMode.group_chat() => "Group Chat",
      Enums.ChatRoomMode.private_chat() => "Private Chat"
    })
  end

  defp get_chat_room_mode_badge_icon!(chat_room_mode) do
    Enums.ChatRoomMode.map!(chat_room_mode, %{
      Enums.ChatRoomMode.group_chat() => "hero-user-group",
      Enums.ChatRoomMode.private_chat() => "hero-chat-bubble-left-right"
    })
  end
end
