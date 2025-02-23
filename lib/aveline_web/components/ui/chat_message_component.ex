defmodule AvelineWeb.Ui.ChatMessageComponent do
  @moduledoc """
  This component is used to display a chat message.
  """
  use Phoenix.Component

  attr :message, :string, required: true
  attr :author_display_name, :string, required: true
  attr :color_scheme, :string, required: true, values: ["brand", "gray"]

  def chat_message(assigns) do
    ~H"""
    <div class="flex flex-col gap-2">
      <div class="flex flex-row gap-2">
        <span class="text-sm font-medium">{@author_display_name}</span>
        <span class="text-sm text-text-tertiary">{@message}</span>
      </div>
    </div>
    """
  end
end
