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
  attr :ws_slug, :string, default: nil

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
      <.spans content={@block["content"] || []} ws_slug={@ws_slug} />
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
        <.spans content={item["content"] || []} ws_slug={@ws_slug} />
      </li>
    </ol>
    """
  end

  def block(%{block: %{"type" => "list"}} = assigns) do
    ~H"""
    <ul id={@block["id"]} class="blk-list blk-anchored">
      <.block_anchor id={@block["id"]} />
      <li :for={item <- @block["items"] || []} id={item["id"]}>
        <.spans content={item["content"] || []} ws_slug={@ws_slug} />
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
              <.spans content={cell || []} ws_slug={@ws_slug} />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  # doc_link — a stop on a story/trail. `target` is the read-time echo
  # merged in by Docs.enrich_blocks; without it (or with a deleted
  # target) we render a placeholder stop rather than break the chain.
  def block(%{block: %{"type" => "doc_link"}} = assigns) do
    target = assigns.block["target"]
    live? = is_map(target) and target["deleted"] != true and is_binary(target["slug"])
    assigns = assign(assigns, target: target, live?: live?)

    ~H"""
    <div id={@block["id"]} class="blk-doc-link blk-anchored">
      <.block_anchor id={@block["id"]} />
      <%= if @live? and @ws_slug do %>
        <.link navigate={"/w/#{@ws_slug}/d/#{@target["slug"]}"} class="doc-link-card">
          <div class="doc-link-card-title">{@target["title"]}</div>
          <div :if={@target["summary"]} class="doc-link-card-summary">{@target["summary"]}</div>
        </.link>
      <% else %>
        <div class="doc-link-card doc-link-card-dead">
          <div class="doc-link-card-title">
            {if is_map(@target), do: @target["title"] || "Removed doc", else: "Removed doc"}
          </div>
          <div class="doc-link-card-summary">This stop's doc was deleted. Restore it to bring the stop back.</div>
        </div>
      <% end %>
      <p :if={@block["note"]} class="doc-link-note">
        <.spans content={@block["note"] || []} ws_slug={@ws_slug} />
      </p>
    </div>
    """
  end

  # board — a live kanban over the workspace's tags. Read-only in the
  # web (humans comment; agents move cards by retagging via apply-ops).
  # `view` is the read-time echo merged in by Docs.enrich_blocks.
  def block(%{block: %{"type" => "board"}} = assigns) do
    view = assigns.block["view"] || %{}
    columns = view["columns"] || []
    colors = view["colors"] || %{}
    cards = view["cards"] || []
    grouped = Enum.group_by(cards, & &1["column"])
    unassigned = Map.get(grouped, nil, [])

    assigns =
      assign(assigns, columns: columns, colors: colors, grouped: grouped, unassigned: unassigned)

    ~H"""
    <div id={@block["id"]} class="blk-board blk-anchored">
      <.block_anchor id={@block["id"]} />
      <div class="blk-board-meta">
        <span class="blk-board-filter">
          <.scoped_tag :for={t <- @block["tags"] || []} slug={t} />
        </span>
        <span class="blk-board-by">by {@block["by"]}</span>
      </div>
      <div :if={@columns == []} class="blk-board-empty">
        No <code>{@block["by"]}:*</code> tags exist yet — create them
        (<code>aveline create-tag --name {@block["by"]}:todo ...</code>) and they become this board's columns.
      </div>
      <div :if={@columns != []} class="board">
        <div :for={col <- @columns} class="board-col" style={"--h: #{board_hue(col)}"}>
          <div class="board-col-head">
            <span
              class="board-col-dot"
              style={if c = @colors[col], do: "background: #{c}"}
              aria-hidden="true"
            >
            </span>
            <span class="board-col-name">{Aveline.Tags.value_of(col)}</span>
            <span class="board-col-count">{length(Map.get(@grouped, col, []))}</span>
          </div>
          <div class="board-col-cards">
            <div :for={card <- Map.get(@grouped, col, [])} class="board-card">
              <.link navigate={"/w/#{@ws_slug}/d/#{card["slug"]}"} class="board-card-title">{card["title"]}</.link>
              <div :if={card["summary"]} class="board-card-summary">{card["summary"]}</div>
              <div class="board-card-foot">
                <span :if={card["owner"]} class="board-card-owner">{card["owner"]}</span>
              </div>
            </div>
            <div :if={Map.get(@grouped, col, []) == []} class="board-col-empty">—</div>
          </div>
        </div>
        <div :if={@unassigned != []} class="board-col board-col-none">
          <div class="board-col-head">
            <span class="board-col-name">no {@block["by"]}</span>
            <span class="board-col-count">{length(@unassigned)}</span>
          </div>
          <div class="board-col-cards">
            <div :for={card <- @unassigned} class="board-card">
              <.link navigate={"/w/#{@ws_slug}/d/#{card["slug"]}"} class="board-card-title">{card["title"]}</.link>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def block(assigns) do
    ~H"""
    <div class="blk-unknown">Unknown block type: {@block["type"]}</div>
    """
  end

  defp board_hue(s), do: :erlang.phash2(s || "", 360)

  @doc """
  A tag chip that renders scoped tags (`status:todo`) two-tone — scope
  dim, value bright — and plain tags as ordinary chips.
  """
  attr :slug, :string, required: true

  def scoped_tag(assigns) do
    assigns = assign(assigns, scope: Aveline.Tags.scope_of(assigns.slug))

    ~H"""
    <span class="scoped-tag">
      <span :if={@scope} class="scoped-tag-scope">{@scope}:</span><span class="scoped-tag-value">{Aveline.Tags.value_of(@slug)}</span>
    </span>
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
  attr :ws_slug, :string, default: nil

  def spans(assigns) do
    ~H"""
    <span :for={s <- @content}>{render_span(s, @ws_slug)}</span>
    """
  end

  defp render_span(%{"text" => text} = s, ws_slug) do
    marks = s["marks"] || []
    link = s["link"]
    inner_html = safe_text_with_marks(text, marks)

    cond do
      is_map(link) and is_binary(link["doc_id"]) ->
        render_doc_mention(inner_html, link["target"], ws_slug)

      is_map(link) and is_binary(link["href"]) ->
        href = Phoenix.HTML.html_escape(link["href"]) |> Phoenix.HTML.safe_to_string()
        Phoenix.HTML.raw("<a class=\"blk-link\" href=\"" <> href <> "\">" <> inner_html <> "</a>")

      true ->
        Phoenix.HTML.raw(inner_html)
    end
  end

  defp render_span(_, _), do: ""

  # An inline mention of another doc. The text is the author's words;
  # the echoed target supplies the destination and the hover title. A
  # deleted target degrades to plain text — no broken-link click.
  defp render_doc_mention(inner_html, %{"deleted" => false, "slug" => slug} = target, ws_slug)
       when is_binary(slug) and is_binary(ws_slug) do
    href = esc("/w/#{ws_slug}/d/#{slug}")
    title = esc(target["title"] || "")

    Phoenix.HTML.raw(
      "<a class=\"blk-link blk-doc-mention\" data-phx-link=\"redirect\" data-phx-link-state=\"push\" " <>
        "href=\"" <> href <> "\" title=\"" <> title <> "\">" <> inner_html <> "</a>"
    )
  end

  defp render_doc_mention(inner_html, _target, _ws_slug), do: Phoenix.HTML.raw(inner_html)

  defp esc(s), do: Phoenix.HTML.html_escape(s) |> Phoenix.HTML.safe_to_string()

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
