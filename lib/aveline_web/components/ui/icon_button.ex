defmodule AvelineWeb.Ui.IconButton do
  @moduledoc """
  This component is used to display an icon button (pure icon, no text).
  """
  use Phoenix.Component
  import AvelineWeb.CoreComponents, only: [icon: 1]

  attr :icon, :string, required: true
  attr :class, :string, default: nil
  attr :on_click, :any, required: true
  attr :hierarchy, :string, required: true

  def icon_button(assigns) do
    ~H"""
    <button
      class={"flex items-center justify-center p-3 rounded-full #{get_hierarchy_class(@hierarchy)} #{@class}"}
      phx-click={@on_click}
    >
      <.icon name={@icon} class="w-5 h-5" />
    </button>
    """
  end

  defp get_hierarchy_class(hierarchy) do
    case hierarchy do
      "primary" -> "bg-brand-600 text-white"
    end
  end
end
