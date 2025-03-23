defmodule AvelineWeb.Ui.Button do
  @moduledoc """
  A button component derived from Untitled UI.
  """
  use Phoenix.Component

  import AvelineWeb.CoreComponents, only: [icon: 1]

  attr :size, :string, required: true, values: ["sm", "md", "lg", "xl", "2xl"]

  attr :hierarchy, :string,
    required: true,
    values: ["primary", "secondary_gray", "secondary_gray", "tertiary_gray", "tertiary_color"]

  attr :leading_icon, :string, default: nil
  attr :trailing_icon, :string, default: nil

  attr :label, :string, required: true
  attr :on_click, :string, required: true
  attr :disabled, :boolean, required: true

  attr :rest, :global

  def button(assigns) do
    ~H"""
    <button class="flex" phx-click={@on_click} phx-disabled={@disabled} {@rest}>
      <.icon :if={@leading_icon} name={@leading_icon} />
      <span>
        {@label}
      </span>
      <.icon :if={@trailing_icon} name={@trailing_icon} />
    </button>
    """
  end
end
