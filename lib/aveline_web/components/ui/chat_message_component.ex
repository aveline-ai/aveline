defmodule AvelineWeb.Ui.ChatMessageComponent do
  @moduledoc """
  This component is used to display a chat message.
  """
  use Phoenix.Component

  import AvelineWeb.Ui.Button

  attr :message_id, :string, required: true
  attr :message, :string, required: true
  attr :author_display_name, :string, required: true
  attr :side, :string, required: true, values: ["left", "right"]
  attr :should_display_author_display_name, :boolean, required: true

  attr :should_display_learn_action, :boolean, required: true
  attr :on_learn_action, :string, required: true

  def chat_message(assigns) do
    ~H"""
    <div class="flex flex-col gap-1.5 w-fit min-w-64">
      <div :if={@should_display_author_display_name} class="text-xs font-medium text-text-secondary pt-3">
        {@author_display_name}
      </div>
      <div class={"text-sm text-text-tertiary py-2.5 px-3.5 #{get_chat_message_color_scheme(@side)} rounded-lg #{get_square_border_side(@side)}"}>
        <span class="whitespace-pre-wrap">{@message}</span>
      </div>
      <.button
        :if={@should_display_learn_action}
        size="sm"
        hierarchy="secondary_gray"
        label="Learn"
        on_click={@on_learn_action}
        disabled={false}
        leading_icon="hero-academic-cap"
        phx-value-message-id={@message_id}
        class="self-end"
      />
    </div>
    """
  end

  # Private

  defp get_chat_message_color_scheme(side) do
    case side do
      "left" -> "bg-background-active text-text-primary border border-border-secondary"
      "right" -> "bg-brand-600 text-white"
    end
  end

  defp get_square_border_side(side) do
    case side do
      "left" -> "rounded-tl-none"
      "right" -> "rounded-tr-none"
    end
  end
end
