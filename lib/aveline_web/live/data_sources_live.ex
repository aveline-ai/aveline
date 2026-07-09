defmodule AvelineWeb.DataSourcesLive do
  @moduledoc """
  Read-only audit page for the workspace's data sources: what external
  databases this workspace holds credentials for, who connected them,
  and which docs chart them. Mutations happen through the CLI like
  everything else — humans look, agents wire.

  Soft-deleted sources are listed too (dimmed): the row survives for
  audit (name, adapter, who, when) but its credential was hard-deleted
  at delete time. There is no restore — you connect a new source.
  """
  use AvelineWeb, :live_view

  alias Aveline.DataSources
  alias Aveline.DataSources.Queries
  alias Aveline.Docs
  alias Aveline.Workspaces
  alias AvelineWeb.LiveSession

  @impl true
  def mount(%{"slug" => slug}, session, socket) do
    user = LiveSession.current_user(session)

    case LiveSession.fetch_workspace_for_user(slug, user) do
      {:ok, ws} ->
        sources = DataSources.list_all_for_workspace(ws.id)

        {:ok,
         assign(socket,
           page_title: "Aveline · Data sources · #{ws.name}",
           current_user: user,
           workspace: ws,
           sidebar_workspaces: Workspaces.list_for_user(user.id),
           sidebar_views: Aveline.Views.list_pinned(ws.id),
           nav_active: :data_sources,
           topbar_title: "Data sources",
           sources: sources,
           usage: chart_usage(ws.id),
           query_counts: query_counts(ws.id)
         )}

      :not_found ->
        {:ok, socket |> put_flash(:error, "Workspace not found.") |> push_navigate(to: ~p"/")}

      :forbidden ->
        {:ok, socket |> put_flash(:error, "Forbidden.") |> push_navigate(to: ~p"/")}
    end
  end

  # base_data_source_id => [%{slug, title, charts: n}] — which live docs
  # chart each source. A chart references a named query; the query maps
  # to its source (raw → its DB, derived → the workspace catalog).
  # Derived at read time from block JSON, so it can't drift.
  defp chart_usage(workspace_id) do
    q_source = query_source_index(workspace_id)

    workspace_id
    |> Docs.list_current()
    |> Enum.reduce(%{}, fn doc, acc ->
      doc.blocks
      |> List.wrap()
      |> Enum.flat_map(&chart_source_ids(&1, q_source))
      |> Enum.frequencies()
      |> Enum.reduce(acc, fn {base_id, count}, inner ->
        entry = %{slug: doc.slug, title: doc.title, charts: count}
        Map.update(inner, base_id, [entry], &[entry | &1])
      end)
    end)
  end

  # query name => the data source base id it charts.
  defp query_source_index(workspace_id) do
    ws_source = DataSources.workspace_source(workspace_id)
    ws_base = ws_source && ws_source.base_data_source_id

    Queries.list_for_workspace(workspace_id)
    |> Map.new(fn q -> {q.name, q.data_source_id || ws_base} end)
  end

  # The source base id(s) a chart block charts (via its query_ref, or a
  # legacy inline chart's data_source_id).
  defp chart_source_ids(%{"type" => "chart", "query_ref" => ref}, q_source) do
    case Map.get(q_source, ref) do
      nil -> []
      base -> [base]
    end
  end

  defp chart_source_ids(%{"type" => "chart", "data_source_id" => base}, _q) when is_binary(base),
    do: [base]

  defp chart_source_ids(_block, _q), do: []

  # base_data_source_id => query count. Raw queries count against their
  # source; derived queries are the workspace source's catalog.
  defp query_counts(workspace_id) do
    ws_source = DataSources.workspace_source(workspace_id)

    Queries.list_for_workspace(workspace_id)
    |> Enum.reduce(%{}, fn q, acc ->
      key = q.data_source_id || (ws_source && ws_source.base_data_source_id)
      if key, do: Map.update(acc, key, 1, &(&1 + 1)), else: acc
    end)
  end

  @snippet ~s(aveline create-data-source --name prod \\\n  --url "postgres://metrics_ro:<password>@your-db-host:5432/your_db" \\\n  --password "...")

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :snippet, @snippet)

    ~H"""
    <div class="content">
      <h1 class="page-title">Data sources</h1>
      <p class="page-subtitle">
        External databases this workspace can chart from. Connected and managed through the CLI; credentials are encrypted at rest and never shown.
      </p>

      <%= if @sources == [] do %>
        <div class="ds-empty">
          <div class="ds-empty-icon" aria-hidden="true">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">
              <ellipse cx="12" cy="5" rx="9" ry="3"/>
              <path d="M3 5v14a9 3 0 0 0 18 0V5"/>
              <path d="M3 12a9 3 0 0 0 18 0"/>
            </svg>
          </div>
          <div class="ds-empty-title">Chart your data, right in your docs</div>
          <p class="ds-empty-copy">
            Connect a Postgres or MySQL database and any doc can carry live charts over it.
            Your agent writes the SQL; the doc stays current on every read. Ask your agent to run:
          </p>
          <pre class="blk-code ds-empty-code"><code>{@snippet}</code></pre>
          <p class="ds-empty-copy ds-empty-fine">
            Use a read-only database user, and put the literal placeholder in the template where the
            password goes. The template stays visible so you always know where a source points; the
            password is encrypted at rest and can never be read back. Queries are forced read-only
            and time-capped server-side either way.
          </p>
        </div>
      <% else %>
        <div class="ds-list">
          <.link
            :for={ds <- @sources}
            navigate={~p"/w/#{@workspace.slug}/data-sources/#{ds.name}"}
            class={["ds-row", "ds-row-link", ds.deleted_at && "ds-row-deleted"]}
          >
            <div class="ds-row-main">
              <span class="ds-name">{ds.name}</span>
              <span class={["ds-adapter", "ds-adapter-" <> ds.adapter]}>
                {DataSources.dialect_label(ds.adapter)}
              </span>
              <span :if={ds.adapter == "workspace"} class="ds-builtin-badge">built-in</span>
              <span :if={ds.deleted_at} class="ds-deleted-badge">deleted · password destroyed</span>
            </div>
            <div class="ds-row-meta">
              <%= if ds.adapter == "workspace" do %>
                <span>The query catalog. Its tables are your named queries, composed in the analytics engine.</span>
              <% else %>
                <span class="ds-conn">{ds.url_template}</span>
                <span class="ds-dot">·</span>
                <span>connected by {(ds.created_by && ds.created_by.username) || "unknown"}</span>
                <span class="ds-dot">·</span>
                <span>{Calendar.strftime(ds.inserted_at, "%b %-d, %Y")}</span>
              <% end %>
            </div>
            <div class="ds-row-usage">
              <span class="ds-count">
                {pluralize(Map.get(@query_counts, ds.base_data_source_id, 0), "query", "queries")}
              </span>
              <span class="ds-dot">·</span>
              <span class="ds-count">
                {pluralize(total_charts(Map.get(@usage, ds.base_data_source_id, [])), "chart", "charts")}
              </span>
              <span class="ds-row-arrow" aria-hidden="true">→</span>
            </div>
          </.link>
        </div>
      <% end %>
    </div>
    """
  end

  defp total_charts(docs), do: docs |> Enum.map(& &1.charts) |> Enum.sum()

  defp pluralize(n, singular, plural), do: "#{n} #{if n == 1, do: singular, else: plural}"
end
