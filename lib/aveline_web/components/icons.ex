defmodule AvelineWeb.Icons do
  @moduledoc """
  Small inline SVG icons (Lucide-style — outlined, 2px stroke, currentColor).
  """
  use Phoenix.Component

  attr :type, :string, required: true, values: ["human", "agent"]
  attr :class, :string, default: "actor-icon"
  attr :title, :string, default: nil

  # Lucide "user" — person silhouette
  def actor(%{type: "human"} = assigns) do
    ~H"""
    <svg
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      <title :if={@title}>{@title}</title>
      <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
      <circle cx="12" cy="7" r="4" />
    </svg>
    """
  end

  # Lucide "bot" — rectangle face with antenna + eyes + side ports
  def actor(%{type: "agent"} = assigns) do
    ~H"""
    <svg
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      <title :if={@title}>{@title}</title>
      <path d="M12 8V4H8" />
      <rect width="16" height="12" x="4" y="8" rx="2" />
      <path d="M2 14h2" />
      <path d="M20 14h2" />
      <path d="M15 13v2" />
      <path d="M9 13v2" />
    </svg>
    """
  end

  def actor(assigns), do: ~H""
end
