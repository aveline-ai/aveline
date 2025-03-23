defmodule AvelineWeb.Ui.Button do
  @moduledoc """
  A button component derived from Untitled UI.

  NOTE: I'll fill this out as I use it, atm only some sizes/hierarchies are ported from Untitled UI.
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

  attr :class, :string, default: nil

  attr :rest, :global

  def button(assigns) do
    ~H"""
    <button
      class={"w-fit flex #{get_button_classes(@size, @hierarchy)} #{@class}"}
      phx-click={@on_click}
      phx-disabled={@disabled}
      {@rest}
    >
      <.icon :if={@leading_icon} name={@leading_icon} class={"#{get_button_icon_classes(@size, @hierarchy)}"} />
      <span>
        {@label}
      </span>
      <.icon :if={@trailing_icon} name={@trailing_icon} class={"#{get_button_icon_classes(@size, @hierarchy)}"} />
    </button>
    """
  end

  # Private

  ## Button Class Helpers

  defp get_button_classes(size, hierarchy) do
    padding_classes = get_button_padding_classes(size)
    border_radius_classes = get_button_border_radius_classes(size)
    border_color_classes = get_button_border_color_classes(hierarchy)
    gap_classes = get_button_gap_classes(size)
    text_size_classes = get_button_text_size_classes(size)
    text_color_classes = get_button_text_color_classes(hierarchy)
    text_weight_classes = get_button_text_weight_classes(size)
    background_color_classes = get_button_background_color_classes(hierarchy)

    all_classes = [
      padding_classes,
      border_radius_classes,
      border_color_classes,
      gap_classes,
      text_size_classes,
      text_color_classes,
      text_weight_classes,
      background_color_classes
    ]

    Enum.join(all_classes, " ")
  end

  defp get_button_padding_classes("sm"), do: "py-2 px-3"

  defp get_button_border_radius_classes("sm"), do: "rounded-lg"

  defp get_button_border_color_classes("secondary_gray"),
    do: "border border-button-secondary-border hover:border-button-secondary-border-hover"

  defp get_button_gap_classes("sm"), do: "gap-1"

  defp get_button_text_size_classes("sm"), do: "text-sm"

  defp get_button_text_color_classes("secondary_gray"),
    do: "text-button-secondary-fg hover:text-button-secondary-fg-hover"

  defp get_button_text_weight_classes("sm"), do: "font-semibold"

  defp get_button_background_color_classes("secondary_gray"),
    do: "bg-button-secondary-bg hover:bg-button-secondary-bg-hover"

  ## Button Icon Class Helpers

  defp get_button_icon_classes(size, hierarchy) do
    button_icon_size_classes = get_button_icon_size_classes(size)
    button_icon_color_classes = get_button_icon_color_classes(hierarchy)

    all_classes = [
      button_icon_size_classes,
      button_icon_color_classes
    ]

    Enum.join(all_classes, " ")
  end

  defp get_button_icon_size_classes("sm"), do: "w-5 h-5"

  defp get_button_icon_color_classes("secondary_gray"), do: "color-button-secondary-fg"
end
