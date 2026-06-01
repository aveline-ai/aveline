defmodule AvelineWeb.Icons do
  @moduledoc """
  Small inline SVG icons. Monochrome, sized 14px by default, render in
  `currentColor` so the parent's color controls them (use `var(--text-muted)`
  for the modern grey look).
  """
  use Phoenix.Component

  attr :type, :string, required: true, values: ["human", "agent"]
  attr :class, :string, default: "actor-icon"
  attr :title, :string, default: nil

  def actor(%{type: "human"} = assigns) do
    ~H"""
    <svg class={@class} viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
      <title :if={@title}>{@title}</title>
      <circle cx="8" cy="5.5" r="2.5" />
      <path d="M2.5 13.5c0-2.8 2.4-4.4 5.5-4.4s5.5 1.6 5.5 4.4" />
    </svg>
    """
  end

  def actor(%{type: "agent"} = assigns) do
    ~H"""
    <svg class={@class} viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
      <title :if={@title}>{@title}</title>
      <rect x="3" y="5.5" width="10" height="7.5" rx="1.6" />
      <path d="M8 3v2.5" />
      <circle cx="6.2" cy="9" r="0.85" fill="currentColor" stroke="none" />
      <circle cx="9.8" cy="9" r="0.85" fill="currentColor" stroke="none" />
      <path d="M6.5 11.5h3" />
    </svg>
    """
  end

  def actor(assigns), do: ~H""
end
