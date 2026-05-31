defmodule AvelineWeb.BlockRenderer do
  @moduledoc """
  Renders the v0 block model — heading / paragraph / code / list / table +
  inline spans with marks + optional links.

  Each block ends up as a top-level element with its `id` as the DOM id so
  deep links like `#b_abc` work natively.
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
        <h1 id={@block["id"]} class="blk-h1">{@block["text"]}</h1>
      <% 2 -> %>
        <h2 id={@block["id"]} class="blk-h2">{@block["text"]}</h2>
      <% _ -> %>
        <h3 id={@block["id"]} class="blk-h3">{@block["text"]}</h3>
    <% end %>
    """
  end

  def block(%{block: %{"type" => "paragraph"}} = assigns) do
    ~H"""
    <p id={@block["id"]} class="blk-p">
      <.spans content={@block["content"] || []} />
    </p>
    """
  end

  def block(%{block: %{"type" => "code"}} = assigns) do
    lang = assigns.block["language"] || ""
    assigns = assign(assigns, lang: lang)

    ~H"""
    <pre id={@block["id"]} class="blk-code" data-lang={@lang}><code>{@block["content"]}</code></pre>
    """
  end

  def block(%{block: %{"type" => "list", "ordered" => true}} = assigns) do
    ~H"""
    <ol id={@block["id"]} class="blk-list">
      <li :for={item <- @block["items"] || []} id={item["id"]}>
        <.spans content={item["content"] || []} />
      </li>
    </ol>
    """
  end

  def block(%{block: %{"type" => "list"}} = assigns) do
    ~H"""
    <ul id={@block["id"]} class="blk-list">
      <li :for={item <- @block["items"] || []} id={item["id"]}>
        <.spans content={item["content"] || []} />
      </li>
    </ul>
    """
  end

  def block(%{block: %{"type" => "table"}} = assigns) do
    ~H"""
    <div class="blk-table-wrap">
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
