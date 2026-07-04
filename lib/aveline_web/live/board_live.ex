defmodule AvelineWeb.BoardLive do
  @moduledoc """
  Tag-driven kanban. A board is defined by data that already exists:

    * a SCOPE tag (e.g. `kanban-feature`) — every doc carrying it is on
      the board
    * COLUMN tags (default: backlog / todo / in-progress / done) — a
      doc's column is the first column tag it carries; docs with none
      land in "No status"

  All board state lives in the URL (`?scope=...&cols=a,b,c`) — nothing
  is stored, so any tag combination is a shareable board. Moving a card
  swaps its column tag via the normal apply_ops path: every move is a
  new doc version with an intent, so the board's history IS the doc
  history. Agents move cards the same way (`apply-ops <slug> --tag ...`).
  """
  use AvelineWeb, :live_view

  alias Aveline.Docs
  alias Aveline.Workspaces
  alias AvelineWeb.LiveSession

  @default_columns ~w(backlog todo in-progress done)

  @impl true
  def mount(%{"slug" => slug}, session, socket) do
    user = LiveSession.current_user(session)

    case LiveSession.fetch_workspace_for_user(slug, user) do
      {:ok, ws} ->
        {:ok,
         assign(socket,
           page_title: "Aveline · Board · #{ws.name}",
           current_user: user,
           workspace: ws,
           sidebar_workspaces: Workspaces.list_for_user(user.id),
           workspace_tags: Docs.list_workspace_tags(ws.id),
           nav_active: :board,
           topbar_title: "Board"
         )}

      :not_found ->
        {:ok, socket |> put_flash(:error, "Workspace not found.") |> push_navigate(to: ~p"/")}

      :forbidden ->
        {:ok, socket |> put_flash(:error, "Forbidden.") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    ws_tags = socket.assigns.workspace_tags

    scope =
      case params["scope"] do
        s when is_binary(s) -> if s in ws_tags, do: s
        _ -> nil
      end

    columns = parse_columns(params["cols"], ws_tags)

    {:noreply,
     socket
     |> assign(scope: scope, columns: columns)
     |> load_board()}
  end

  # Column tags come from the URL (`cols=a,b,c`) so any tag set can be a
  # board; without the param, whichever of the conventional status tags
  # exist in the workspace are used, in canonical order.
  defp parse_columns(nil, ws_tags), do: Enum.filter(@default_columns, &(&1 in ws_tags))
  defp parse_columns("", ws_tags), do: parse_columns(nil, ws_tags)

  defp parse_columns(csv, ws_tags) when is_binary(csv) do
    csv
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 in ws_tags))
    |> Enum.uniq()
    |> case do
      [] -> parse_columns(nil, ws_tags)
      cols -> cols
    end
  end

  defp load_board(%{assigns: %{scope: nil}} = socket), do: assign(socket, board: %{})

  defp load_board(%{assigns: %{scope: scope, columns: columns, workspace: ws}} = socket) do
    board =
      ws.id
      |> Docs.list_current(tags: [scope])
      |> Enum.group_by(&(column_of(&1, columns) || :none))

    assign(socket, board: board)
  end

  defp column_of(doc, columns), do: Enum.find(columns, &(&1 in doc.tags))

  defp cards(board, col), do: Map.get(board, col, [])

  # Move = retag through the single write path. Every column tag is
  # stripped, the target added; scope and free tags survive. The move
  # becomes a doc version with an intent, so status history lives in the
  # version history like everything else.
  @impl true
  def handle_event("move", %{"slug" => slug, "to" => to}, socket) do
    %{workspace: ws, columns: columns, scope: scope, current_user: user} = socket.assigns

    with true <- to in columns,
         %_{} = doc <- Docs.get_current_by_slug(ws.id, slug),
         new_tags = Enum.uniq((doc.tags -- columns) ++ [to]),
         {:ok, _} <-
           Docs.apply_ops(
             doc,
             [],
             %{
               tags: new_tags,
               actor_user_id: user.id,
               actor_type: "human"
             },
             intent: "board #{scope}: moved to #{to}",
             dispositions: []
           ) do
      {:noreply, load_board(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not move the card.")}
    end
  end

  def handle_event("select_scope", %{"tag" => tag}, socket) do
    {:noreply, push_patch(socket, to: ~p"/w/#{socket.assigns.workspace.slug}/board?scope=#{tag}")}
  end

  def handle_event("clear_scope", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/w/#{socket.assigns.workspace.slug}/board")}
  end

  defp hue(s), do: :erlang.phash2(s || "", 360)

  defp neighbors(columns, col) do
    idx = Enum.find_index(columns, &(&1 == col))
    {idx && idx > 0 && Enum.at(columns, idx - 1), idx && Enum.at(columns, idx + 1)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="content board-content">
      <h1 class="page-title">Board</h1>
      <p class="page-subtitle">
        Tag-driven kanban — pick a scope tag; every doc carrying it becomes a card,
        grouped by status tag.
      </p>

      <%= if @scope == nil do %>
        <div class="board-picker">
          <div class="board-picker-title">Pick a scope tag</div>
          <p class="board-picker-hint">
            A board is just a tag. Tag docs with a scope (say
            <code>kanban-feature</code>) plus a status tag
            (<code>backlog</code>, <code>todo</code>, <code>in-progress</code>, <code>done</code>)
            and they show up here as cards. Agents move cards by retagging —
            <code>aveline apply-ops &lt;slug&gt; --tag &lt;scope&gt; --tag done --ops "[]"</code>.
          </p>
          <div class="chip-row">
            <button
              :for={tag <- @workspace_tags}
              phx-click="select_scope"
              phx-value-tag={tag}
              class="chip chip-tag"
            >
              <span class="chip-text">{tag}</span>
            </button>
          </div>
          <p :if={@columns == []} class="board-picker-hint board-picker-warn">
            No status tags exist here yet — create them first:
            <code>aveline create-tag --name todo --description "..."</code>
            (same for backlog / in-progress / done), or pass custom columns via
            <code>?cols=a,b,c</code>.
          </p>
        </div>
      <% else %>
        <div class="board-toolbar">
          <button phx-click="clear_scope" class="chip chip-tag chip-active" title="Change scope">
            <span class="chip-text">{@scope}</span>
            <span class="chip-meta">×</span>
          </button>
          <span class="board-toolbar-note">
            columns: {Enum.join(@columns, " · ")}
          </span>
        </div>

        <div class="board">
          <div :for={col <- @columns} class="board-col" style={"--h: #{hue(col)}"}>
            <div class="board-col-head">
              <span class="board-col-dot" aria-hidden="true"></span>
              <span class="board-col-name">{col}</span>
              <span class="board-col-count">{length(cards(@board, col))}</span>
            </div>
            <div class="board-col-cards">
              <div :for={doc <- cards(@board, col)} class="board-card">
                <.link navigate={~p"/w/#{@workspace.slug}/d/#{doc.slug}"} class="board-card-title">
                  {doc.title}
                </.link>
                <div :if={doc.summary} class="board-card-summary">{doc.summary}</div>
                <div class="board-card-foot">
                  <span :if={doc.owner} class="board-card-owner">{doc.owner.username}</span>
                  <span class="board-card-time">{relative_time(doc.updated_at)}</span>
                  <span :if={@current_user} class="board-card-actions">
                    <% {prev, next} = neighbors(@columns, col) %>
                    <button
                      :if={prev}
                      phx-click="move"
                      phx-value-slug={doc.slug}
                      phx-value-to={prev}
                      class="board-move"
                      title={"Move to #{prev}"}
                      aria-label={"Move to #{prev}"}
                    >
                      ‹
                    </button>
                    <button
                      :if={next}
                      phx-click="move"
                      phx-value-slug={doc.slug}
                      phx-value-to={next}
                      class="board-move"
                      title={"Move to #{next}"}
                      aria-label={"Move to #{next}"}
                    >
                      ›
                    </button>
                  </span>
                </div>
              </div>
              <div :if={cards(@board, col) == []} class="board-col-empty">—</div>
            </div>
          </div>

          <div :if={cards(@board, :none) != []} class="board-col board-col-none">
            <div class="board-col-head">
              <span class="board-col-name">No status</span>
              <span class="board-col-count">{length(cards(@board, :none))}</span>
            </div>
            <div class="board-col-cards">
              <div :for={doc <- cards(@board, :none)} class="board-card">
                <.link navigate={~p"/w/#{@workspace.slug}/d/#{doc.slug}"} class="board-card-title">
                  {doc.title}
                </.link>
                <div class="board-card-foot">
                  <span :if={doc.owner} class="board-card-owner">{doc.owner.username}</span>
                  <span class="board-card-time">{relative_time(doc.updated_at)}</span>
                  <span :if={@current_user && @columns != []} class="board-card-actions">
                    <button
                      phx-click="move"
                      phx-value-slug={doc.slug}
                      phx-value-to={List.first(@columns)}
                      class="board-move"
                      title={"Move to #{List.first(@columns)}"}
                    >
                      ›
                    </button>
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
