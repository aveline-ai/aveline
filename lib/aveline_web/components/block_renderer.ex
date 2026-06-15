defmodule AvelineWeb.BlockRenderer do
  @moduledoc """
  Renders the v0 block model — heading / paragraph / code / list / table +
  inline spans with marks + optional links.

  Each block ends up as a top-level element with its `id` as the DOM id so
  deep links like `#b_abc` work natively. The anchor button is rendered
  *inside* each block so it inherits that block's font-size / line-height,
  letting CSS center it on the first line via `1lh`.
  """
  use Phoenix.Component

  attr :blocks, :list, required: true

  def render(assigns) do
    ~H"""
    <div class="blocks">
      <.block :for={b <- @blocks} block={b} />
    </div>
    """
  end

  attr :block, :map, required: true

  def block(%{block: %{"type" => "heading"}} = assigns) do
    ~H"""
    <%= case @block["level"] do %>
      <% 1 -> %>
        <h1 id={@block["id"]} class="blk-h1 blk-anchored">
          <.block_anchor id={@block["id"]} />
          {@block["text"]}
        </h1>
      <% 2 -> %>
        <h2 id={@block["id"]} class="blk-h2 blk-anchored">
          <.block_anchor id={@block["id"]} />
          {@block["text"]}
        </h2>
      <% _ -> %>
        <h3 id={@block["id"]} class="blk-h3 blk-anchored">
          <.block_anchor id={@block["id"]} />
          {@block["text"]}
        </h3>
    <% end %>
    """
  end

  def block(%{block: %{"type" => "paragraph"}} = assigns) do
    ~H"""
    <p id={@block["id"]} class="blk-p blk-anchored">
      <.block_anchor id={@block["id"]} />
      <.spans content={@block["content"] || []} />
    </p>
    """
  end

  def block(%{block: %{"type" => "code"}} = assigns) do
    lang = assigns.block["language"] || ""
    code_class = if lang == "", do: "", else: "language-" <> lang
    assigns = assign(assigns, lang: lang, code_class: code_class)

    ~H"""
    <div class="blk-code-wrap blk-anchored">
      <.block_anchor id={@block["id"]} />
      <pre
        id={@block["id"]}
        class="blk-code"
        data-lang={@lang}
        phx-hook="HighlightCode"
        phx-update="ignore"
      ><code class={@code_class}>{@block["content"]}</code></pre>
    </div>
    """
  end

  def block(%{block: %{"type" => "list", "ordered" => true}} = assigns) do
    ~H"""
    <ol id={@block["id"]} class="blk-list blk-anchored">
      <.block_anchor id={@block["id"]} />
      <li :for={item <- @block["items"] || []} id={item["id"]}>
        <.spans content={item["content"] || []} />
      </li>
    </ol>
    """
  end

  def block(%{block: %{"type" => "list"}} = assigns) do
    ~H"""
    <ul id={@block["id"]} class="blk-list blk-anchored">
      <.block_anchor id={@block["id"]} />
      <li :for={item <- @block["items"] || []} id={item["id"]}>
        <.spans content={item["content"] || []} />
      </li>
    </ul>
    """
  end

  def block(%{block: %{"type" => "table"}} = assigns) do
    ~H"""
    <div class="blk-table-wrap blk-anchored">
      <.block_anchor id={@block["id"]} />
      <table id={@block["id"]} class="blk-table">
        <thead>
          <tr>
            <th :for={h <- @block["headers"] || []}>{h}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @block["rows"] || []}>
            <td :for={cell <- row}>
              <.spans content={cell || []} />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  def block(assigns) do
    ~H"""
    <div class="blk-unknown">Unknown block type: {@block["type"]}</div>
    """
  end

  attr :id, :string, required: true

  defp block_anchor(assigns) do
    ~H"""
    <span :if={@id} class="block-gutter" contenteditable="false">
      <a
        href={"#" <> @id}
        class="block-anchor"
        phx-hook="CopyBlockLink"
        id={"anchor-" <> @id}
        data-block-id={@id}
        title="Copy link to this block"
        aria-label="Copy link to this block"
      >
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/>
          <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>
        </svg>
      </a>
      <button
        type="button"
        class="block-comment-btn"
        phx-click="start_block_comment"
        phx-value-block-id={@id}
        title="Comment on this block"
        aria-label="Comment on this block"
      >
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
        </svg>
      </button>
    </span>
    """
  end

  attr :content, :list, required: true

  def spans(assigns) do
    ~H"""
    <span :for={s <- @content}>{render_span(s)}</span>
    """
  end

  defp render_span(%{"text" => text} = s) do
    marks = s["marks"] || []
    link = s["link"]
    inner_html = safe_text_with_marks(text, marks)

    if is_map(link) and is_binary(link["href"]) do
      href = Phoenix.HTML.html_escape(link["href"]) |> Phoenix.HTML.safe_to_string()
      Phoenix.HTML.raw("<a class=\"blk-link\" href=\"" <> href <> "\">" <> inner_html <> "</a>")
    else
      Phoenix.HTML.raw(inner_html)
    end
  end

  defp render_span(_), do: ""

  defp safe_text_with_marks(text, marks) do
    escaped = Phoenix.HTML.html_escape(text) |> Phoenix.HTML.safe_to_string()

    Enum.reduce(marks, escaped, fn
      "bold", acc -> "<strong>" <> acc <> "</strong>"
      "italic", acc -> "<em>" <> acc <> "</em>"
      "code", acc -> "<code class=\"blk-inline-code\">" <> acc <> "</code>"
      "strike", acc -> "<s>" <> acc <> "</s>"
      _, acc -> acc
    end)
  end
end
