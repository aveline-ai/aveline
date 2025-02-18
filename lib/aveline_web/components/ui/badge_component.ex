defmodule AvelineWeb.Ui.BadgeComponent do
  @moduledoc """
  This component is used to display different badges.
  """
  use Phoenix.Component
  import AvelineWeb.CoreComponents, only: [icon: 1]

  attr :label, :string, required: true
  attr :color, :string, required: true
  attr :icon, :string, required: true

  def badge_color_with_icon(assigns) do
    ~H"""
    <div class={"py-0.5 pr-1.5 pl-1 flex gap-0.5 items-center border rounded #{get_badge_border_color_class(@color)} #{get_badge_background_color_class(@color)}"}>
      <.icon name={@icon} class={"w-3 h-3 #{get_icon_color_class(@color)}"} />
      <span class={"text-xs text-center #{get_label_color_class(@color)}"}>{@label}</span>
    </div>
    """
  end

  # Private

  ## Color scheme helpers

  defp get_icon_color_class(color) do
    case color do
      "gray" -> "text-gray-600"
      "orange" -> "text-orange-500"
      "blue-light" -> "text-blue-light-500"
      _ -> ""
    end
  end

  defp get_label_color_class(color) do
    case color do
      "gray" -> "text-gray-700"
      "orange" -> "text-orange-700"
      "blue-light" -> "text-blue-light-700"
      _ -> ""
    end
  end

  defp get_badge_border_color_class(color) do
    case color do
      "gray" -> "border-gray-200"
      "orange" -> "border-orange-200"
      "blue-light" -> "border-blue-light-200"
      _ -> ""
    end
  end

  defp get_badge_background_color_class(color) do
    case color do
      "gray" -> "bg-gray-50"
      "orange" -> "bg-orange-50"
      "blue-light" -> "bg-blue-light-50"
      _ -> ""
    end
  end
end
