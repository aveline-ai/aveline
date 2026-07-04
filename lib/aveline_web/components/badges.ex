defmodule AvelineWeb.Badges do
  @moduledoc """
  Reusable badge components for tags and authors. One underlying shape
  with per-kind palette so categories scan instantly: tags are warm
  orange, authors are calm teal.

  Use `<.tag>` / `<.author>` for non-interactive display (doc card meta,
  Tags page rows). For interactive filter chips that need to be buttons
  or links, compose the same CSS classes on your wrapper:

      <button class="chip chip-tag" phx-click="toggle_tag">
        <span class="chip-text">{tag}</span>
        <span class="chip-meta">{count}</span>
      </button>
  """
  use Phoenix.Component

  attr :text, :string, required: true
  attr :meta, :any, default: nil
  # Optional #rrggbb — overrides the default tag palette per chip by
  # rebinding the chip's CSS variables (hex+alpha for dim/border).
  attr :color, :string, default: nil
  attr :rest, :global
  slot :icon

  def tag(assigns) do
    assigns =
      assigns
      |> assign(:kind, "tag")
      |> assign(
        :style,
        assigns.color &&
          "--tag: #{assigns.color}; --tag-dim: #{assigns.color}14; --tag-border: #{assigns.color}40"
      )

    badge(assigns)
  end

  attr :text, :string, required: true
  attr :meta, :any, default: nil
  attr :rest, :global
  slot :icon

  def author(assigns) do
    assigns = assigns |> assign(:kind, "author") |> assign(:style, nil)
    badge(assigns)
  end

  defp badge(assigns) do
    ~H"""
    <span class={"chip chip-#{@kind}"} style={@style} {@rest}>
      {render_slot(@icon)}
      <span class="chip-text">{@text}</span>
      <span :if={@meta != nil} class="chip-meta">{@meta}</span>
    </span>
    """
  end
end
