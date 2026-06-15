defmodule AvelineWeb.UsageLive do
  @moduledoc """
  Workspace stats — designed to read at a glance.

  Two storytelling layers:
    * **Hero strip** with the four numbers that tell the workspace's
      story: docs built, reads delivered, kudos earned, edits made.
      Supporting line below for members / tags / comments.
    * **Contributors leaderboard** with avatars and horizontal share
      bars so it's instantly obvious who's done the most.
  """
  use AvelineWeb, :live_view

  alias Aveline.Stats
  alias Aveline.Workspaces
  alias AvelineWeb.LiveSession

  @impl true
  def mount(%{"slug" => slug}, session, socket) do
    user = LiveSession.current_user(session)

    case LiveSession.fetch_workspace_for_user(slug, user) do
      {:ok, ws} ->
        contributors = Stats.contributors(ws.id)

        {:ok,
         assign(socket,
           page_title: "Aveline · Usage · #{ws.name}",
           current_user: user,
           workspace: ws,
           sidebar_workspaces: Workspaces.list_for_user(user.id),
           topbar_title: "Usage",
           nav_active: :usage,
           totals: Stats.workspace_totals(ws.id),
           contributors: contributors,
           # Per-column max, used to render a trophy next to the leader of
           # each metric — visible regardless of current sort.
           column_maxes: column_maxes(contributors),
           sort_by: :docs_owned,
           sort_dir: :desc,
           columns: columns()
         )}

      :not_found ->
        {:ok, socket |> put_flash(:error, "Workspace not found.") |> push_navigate(to: ~p"/")}

      :forbidden ->
        {:ok, socket |> put_flash(:error, "Forbidden.") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("sort", %{"by" => by}, socket) do
    col = String.to_existing_atom(by)
    {new_by, new_dir} =
      if socket.assigns.sort_by == col do
        # Toggle direction when clicking the same column.
        {col, flip(socket.assigns.sort_dir)}
      else
        # New column: start descending (most "interesting first" is almost
        # always desc on a numeric leaderboard).
        {col, :desc}
      end

    {:noreply, assign(socket, sort_by: new_by, sort_dir: new_dir)}
  end

  defp flip(:desc), do: :asc
  defp flip(:asc), do: :desc

  defp column_maxes(rows) do
    [:docs_owned, :reads_earned, :kudos_earned, :edits_made, :comments_posted, :kudos_given]
    |> Map.new(fn k -> {k, rows |> Enum.map(&Map.get(&1, k, 0)) |> Enum.max(fn -> 0 end)} end)
  end

  # Sortable columns the table exposes — atom → row field used for sorting
  # and rendering header click events. Username sort goes alpha.
  defp columns,
    do: [
      {:user, "Contributor"},
      {:docs_owned, "Docs"},
      {:reads_earned, "Views"},
      {:kudos_earned, "Kudos"},
      {:edits_made, "Edits"},
      {:comments_posted, "Comments"}
    ]

  defp sort_rows(rows, :user, dir) do
    Enum.sort_by(rows, & &1.user.username, if(dir == :desc, do: :desc, else: :asc))
  end

  defp sort_rows(rows, col, dir) do
    Enum.sort_by(rows, fn r -> {Map.get(r, col, 0), r.user.username} end, dir_to_sorter(dir))
  end

  defp dir_to_sorter(:desc), do: :desc
  defp dir_to_sorter(_), do: :asc

  defp sort_indicator(col, sort_by, sort_dir) when col == sort_by do
    if sort_dir == :desc, do: "↓", else: "↑"
  end

  defp sort_indicator(_, _, _), do: ""

  @impl true
  def render(assigns) do
    ~H"""
    <div class="content">
      <h1 class="page-title">Usage</h1>
      <p class="page-subtitle">
        What <span class="mono">{@workspace.slug}</span> has built — and who's keeping it alive.
      </p>

      <div class="hero-grid">
        <.hero_card label="Documents" value={@totals.active_docs}>
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">
            <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
            <polyline points="14 2 14 8 20 8"/>
            <line x1="8" y1="13" x2="16" y2="13"/>
            <line x1="8" y1="17" x2="14" y2="17"/>
          </svg>
        </.hero_card>

        <.hero_card label="Views" value={@totals.reads}>
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">
            <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/>
            <circle cx="12" cy="12" r="3"/>
          </svg>
        </.hero_card>

        <.hero_card label="Comments" value={@totals.comments}>
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">
            <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
          </svg>
        </.hero_card>
      </div>

      <div class="hero-grid">
        <.hero_card label="Edits" value={@totals.total_edits}>
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">
            <path d="M12 20h9"/>
            <path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4 12.5-12.5z"/>
          </svg>
        </.hero_card>

        <.hero_card label="Kudos" value={@totals.kudos}>
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">
            <path d="M6 9H4.5a2.5 2.5 0 0 1 0-5H6"/>
            <path d="M18 9h1.5a2.5 2.5 0 0 0 0-5H18"/>
            <path d="M4 22h16"/>
            <path d="M10 14.66V17c0 .55-.47.98-.97 1.21C7.85 18.75 7 20.24 7 22"/>
            <path d="M14 14.66V17c0 .55.47.98.97 1.21C16.15 18.75 17 20.24 17 22"/>
            <path d="M18 2H6v7a6 6 0 0 0 12 0V2z"/>
          </svg>
        </.hero_card>

        <.hero_card label="Users" value={@totals.members}>
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">
            <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/>
            <circle cx="9" cy="7" r="4"/>
            <path d="M23 21v-2a4 4 0 0 0-3-3.87"/>
            <path d="M16 3.13a4 4 0 0 1 0 7.75"/>
          </svg>
        </.hero_card>
      </div>

      <%= if @contributors == [] do %>
        <div class="empty">No members yet.</div>
      <% else %>
        <% rows = sort_rows(@contributors, @sort_by, @sort_dir) %>
        <table class="leader-table">
          <thead>
            <tr>
              <%= for {col, label} <- @columns do %>
                <th class={"leader-th " <> if col == :user, do: "leader-th-text", else: "leader-th-num"}>
                  <button
                    type="button"
                    phx-click="sort"
                    phx-value-by={Atom.to_string(col)}
                    class={"leader-sort " <> if col == @sort_by, do: "is-active", else: ""}
                  >
                    {label}
                    <span class="leader-sort-arrow">{sort_indicator(col, @sort_by, @sort_dir)}</span>
                  </button>
                </th>
              <% end %>
            </tr>
          </thead>
          <tbody>
            <%= for row <- rows do %>
              <tr class="leader-tr">
                <td class="leader-td leader-td-user">
                  <div
                    class="leader-avatar"
                    style={"background: hsl(#{avatar_hue(row.user.username)}, 55%, 28%); color: hsl(#{avatar_hue(row.user.username)}, 70%, 80%)"}
                  >
                    {initial(row.user.username)}
                  </div>
                  <div class="leader-name-block">
                    <div class="leader-name">{row.user.username}</div>
                    <%= if row.user.display_name && row.user.display_name != "" do %>
                      <div class="leader-display">{row.user.display_name}</div>
                    <% end %>
                  </div>
                </td>
                <.metric_cell value={row.docs_owned} max={@column_maxes.docs_owned} title="Most docs" />
                <.metric_cell value={row.reads_earned} max={@column_maxes.reads_earned} title="Most views" />
                <.metric_cell value={row.kudos_earned} max={@column_maxes.kudos_earned} title="Most kudos" />
                <.metric_cell value={row.edits_made} max={@column_maxes.edits_made} title="Most edits" />
                <.metric_cell value={row.comments_posted} max={@column_maxes.comments_posted} title="Most comments" />
              </tr>
            <% end %>
          </tbody>
        </table>
      <% end %>
    </div>
    """
  end

  # ===== Function components =====

  attr :value, :integer, required: true
  attr :max, :integer, required: true
  attr :title, :string, required: true
  attr :muted, :boolean, default: false

  defp metric_cell(assigns) do
    assigns = assign(assigns, :winner?, assigns.max > 0 and assigns.value == assigns.max)

    ~H"""
    <td class={"leader-td leader-td-num " <> if @muted, do: "leader-td-muted", else: ""}>
      <%= if @winner? do %>
        <span class="leader-trophy" title={@title}>
          <svg viewBox="0 0 24 24" fill="currentColor">
            <path d="M6 9H4.5a2.5 2.5 0 0 1 0-5H6V2h12v2h1.5a2.5 2.5 0 0 1 0 5H18v1a6 6 0 0 1-5 5.92V19h3v2H8v-2h3v-3.08A6 6 0 0 1 6 10V9zm0-3v1h.5a.5.5 0 0 0 0-1H6zm12 0v1h.5a.5.5 0 0 0 0-1H18z"/>
          </svg>
        </span>
      <% end %>
      {format_number(@value)}
    </td>
    """
  end


  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :accent, :boolean, default: false
  slot :inner_block, required: true

  defp hero_card(assigns) do
    ~H"""
    <div class={"hero-card " <> if @accent, do: "hero-card-accent", else: ""}>
      <div class="hero-icon">
        {render_slot(@inner_block)}
      </div>
      <div class="hero-value">{format_number(@value)}</div>
      <div class="hero-label">{@label}</div>
    </div>
    """
  end


  # Compact number formatter — "1,234" or "12.3k" for big values so cards stay readable.
  defp format_number(n) when n < 1000, do: Integer.to_string(n)
  defp format_number(n) when n < 10_000, do: comma(n)

  defp format_number(n) when n < 1_000_000 do
    case rem(n, 1000) do
      0 -> "#{div(n, 1000)}k"
      r when r < 100 -> "#{div(n, 1000)}k"
      r -> "#{div(n, 1000)}.#{div(r, 100)}k"
    end
  end

  defp format_number(n), do: "#{div(n, 1_000_000)}M"

  defp comma(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
