defmodule AvelineWeb.DataSourcesLive do
  @moduledoc """
  The workspace's data layer on one page: the external databases this
  workspace holds credentials for, and the catalog of named queries
  built on them. Mutations happen through the CLI like everything else —
  humans look, agents wire.

  Everything is inspected in place: clicking a source filters the
  catalog to it; clicking a query opens a modal with its description,
  SQL, and dependency graph (built on / feeds), whose chips jump from
  query to query. There is no per-source detail page anymore.

  Soft-deleted sources are listed too (dimmed): the card survives for
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

        queries =
          Queries.list_for_workspace(ws.id)
          |> Aveline.Repo.preload(:created_by)
          |> Enum.sort_by(& &1.name)

        {chart_counts, charted_in} = chart_index(ws.id)
        built_on = built_on_index(queries)

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
           source_by_base: Map.new(sources, &{&1.base_data_source_id, &1}),
           ws_base: ws_base(sources),
           queries: queries,
           query_by_name: Map.new(queries, &{&1.name, &1}),
           q: "",
           source_filter: nil,
           selected: nil,
           chart_counts: chart_counts,
           charted_in: charted_in,
           built_on: built_on,
           dependents: dependents_index(built_on),
           milestones: Aveline.Milestones.list_active(ws.id),
           usage: source_rollup(sources, queries, chart_counts)
         )}

      :not_found ->
        {:ok, socket |> put_flash(:error, "Workspace not found.") |> push_navigate(to: ~p"/")}

      :forbidden ->
        {:ok, socket |> put_flash(:error, "Forbidden.") |> push_navigate(to: ~p"/")}
    end
  end

  # The open query lives in the URL (?query=name): browser back/forward
  # walks the jump history through the dependency graph, and the modal
  # deep-links.
  @impl true
  def handle_params(params, _uri, socket) do
    selected =
      case params["query"] do
        nil -> nil
        name -> Map.get(socket.assigns[:query_by_name] || %{}, name)
      end

    {:noreply, assign(socket, selected: selected)}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, assign(socket, q: String.trim(q))}
  end

  def handle_event("filter_source", %{"base" => base}, socket) do
    next = if socket.assigns.source_filter == base, do: nil, else: base
    {:noreply, assign(socket, source_filter: next)}
  end

  def handle_event("open_query", %{"name" => name}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/w/#{socket.assigns.workspace.slug}/data-sources?query=#{name}")}
  end

  def handle_event("close_query", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/w/#{socket.assigns.workspace.slug}/data-sources")}
  end

  # ===== Indexes =====

  defp ws_base(sources) do
    Enum.find_value(sources, fn s ->
      s.adapter == "workspace" && s.base_data_source_id
    end)
  end

  # {query name => chart count, query name => [%{slug, title}]} across
  # live docs. Derived at read time from block JSON, so it can't drift.
  defp chart_index(workspace_id) do
    docs = Docs.list_current(workspace_id)

    refs_per_doc =
      Enum.flat_map(docs, fn doc ->
        for %{"type" => "chart", "query_ref" => ref} <- List.wrap(doc.blocks),
            is_binary(ref),
            do: {ref, doc}
      end)

    counts = refs_per_doc |> Enum.map(&elem(&1, 0)) |> Enum.frequencies()

    charted_in =
      Enum.reduce(refs_per_doc, %{}, fn {ref, doc}, acc ->
        entry = %{slug: doc.slug, title: doc.title}

        Map.update(acc, ref, [entry], fn list ->
          if Enum.any?(list, &(&1.slug == doc.slug)), do: list, else: [entry | list]
        end)
      end)

    {counts, charted_in}
  end

  # query name => the catalog queries it's built on (upstream refs).
  # Raw queries read their source's tables, not catalog queries: none.
  defp built_on_index(queries) do
    Enum.reduce(queries, %{}, fn q, acc ->
      case q.kind == "derived" && Aveline.DataSources.Engine.parse(q.sql) do
        {:ok, refs} -> Map.put(acc, q.name, Enum.sort(refs))
        _ -> acc
      end
    end)
  end

  # query name => [derived query names that reference it] — downstream,
  # what breaks if you change it. Inverted from built_on.
  defp dependents_index(built_on) do
    Enum.reduce(built_on, %{}, fn {name, refs}, acc ->
      Enum.reduce(refs, acc, fn ref, inner ->
        Map.update(inner, ref, [name], &Enum.sort([name | &1]))
      end)
    end)
  end

  # base_data_source_id => %{queries: n, charts: n}. Raw queries count
  # against their source; derived against the workspace catalog.
  defp source_rollup(sources, queries, chart_counts) do
    ws = ws_base(sources)

    Enum.reduce(queries, %{}, fn q, acc ->
      key = q.data_source_id || ws

      if key do
        charts = Map.get(chart_counts, q.name, 0)

        Map.update(acc, key, %{queries: 1, charts: charts}, fn e ->
          %{queries: e.queries + 1, charts: e.charts + charts}
        end)
      else
        acc
      end
    end)
  end

  # ===== Filtering =====

  defp visible_queries(assigns) do
    assigns.queries
    |> filter_by_source(assigns.source_filter, assigns.ws_base)
    |> filter_by_text(assigns.q)
  end

  defp filter_by_source(queries, nil, _ws_base), do: queries

  defp filter_by_source(queries, base, ws_base) do
    Enum.filter(queries, fn q -> (q.data_source_id || ws_base) == base end)
  end

  defp filter_by_text(queries, ""), do: queries

  defp filter_by_text(queries, q) do
    needle = String.downcase(q)

    Enum.filter(queries, fn query ->
      String.contains?(String.downcase(query.name), needle) or
        String.contains?(String.downcase(query.description || ""), needle) or
        String.contains?(String.downcase(query.sql || ""), needle)
    end)
  end

  defp source_chip(nil), do: {"derived", "workspace"}
  defp source_chip(%{name: name, adapter: adapter}), do: {name, adapter}

  # ===== Timeline strip =====

  # Each milestone's horizontal position (percent) along a span from the
  # earliest milestone to today, padded so edge dots don't clip. Labels
  # alternate between two rows (row 0/1) so near-neighbors don't collide.
  defp timeline_positions(milestones) do
    start = timeline_start(milestones)
    span = max(Date.diff(timeline_stop(milestones), start), 1)

    milestones
    |> Enum.with_index()
    |> Enum.map(fn {m, i} ->
      pct = 4.0 + Date.diff(m.date, start) / span * 92.0
      {m, Float.round(pct, 2), rem(i, 2)}
    end)
  end

  defp timeline_start(milestones) do
    milestones |> Enum.map(& &1.date) |> Enum.min(Date)
  end

  defp timeline_stop(milestones) do
    milestones
    |> Enum.map(& &1.date)
    |> Enum.max(Date)
    |> Date.compare(Date.utc_today())
    |> case do
      :gt -> milestones |> Enum.map(& &1.date) |> Enum.max(Date)
      _ -> Date.utc_today()
    end
  end

  # sql-formatter's closest supported dialect. Derived queries speak the
  # engine's dialect (DuckDB) — postgresql is the nearest profile.
  defp formatter_dialect(%{kind: "derived"}, _by_base), do: "postgresql"

  defp formatter_dialect(%{data_source_id: base}, by_base) do
    case Map.get(by_base, base) do
      %{adapter: "mysql"} -> "mysql"
      %{adapter: "redshift"} -> "redshift"
      _ -> "postgresql"
    end
  end

  @snippet ~s(aveline create-data-source --name prod \\\n  --url "postgres://metrics_ro:<password>@your-db-host:5432/your_db" \\\n  --password "...")

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :snippet, @snippet)

    ~H"""
    <div class="content">
      <h1 class="page-title">Data sources</h1>
      <p class="page-subtitle">
        External databases this workspace can chart from, and the named queries built on them.
        Connected and managed through the CLI; credentials are encrypted at rest and never shown.
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
        <div class="ds-grid">
          <button
            :for={ds <- @sources}
            type="button"
            phx-click="filter_source"
            phx-value-base={ds.base_data_source_id}
            class={[
              "ds-card",
              ds.deleted_at && "ds-card-deleted",
              @source_filter == ds.base_data_source_id && "ds-card-active"
            ]}
            title={if @source_filter == ds.base_data_source_id, do: "Show all queries", else: "Show only this source's queries"}
          >
            <div class="ds-card-head">
              <span class={["ds-glyph", "ds-glyph-" <> ds.adapter]} aria-hidden="true">
                <svg :if={ds.adapter != "workspace"} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">
                  <ellipse cx="12" cy="5" rx="9" ry="3"/>
                  <path d="M3 5v14a9 3 0 0 0 18 0V5"/>
                  <path d="M3 12a9 3 0 0 0 18 0"/>
                </svg>
                <svg :if={ds.adapter == "workspace"} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">
                  <rect x="3" y="3" width="7" height="7" rx="1.5"/>
                  <rect x="14" y="3" width="7" height="7" rx="1.5"/>
                  <rect x="3" y="14" width="7" height="7" rx="1.5"/>
                  <rect x="14" y="14" width="7" height="7" rx="1.5"/>
                </svg>
              </span>
              <span class="ds-card-name">{ds.name}</span>
              <span class={["ds-chip", "ds-chip-" <> ds.adapter]}>
                {DataSources.dialect_label(ds.adapter)}
              </span>
              <span :if={ds.adapter == "workspace"} class="ds-chip ds-chip-quiet">built-in</span>
              <span :if={ds.deleted_at} class="ds-chip ds-chip-danger">deleted</span>
            </div>
            <div class="ds-card-body">
              <%= if ds.adapter == "workspace" do %>
                Your named queries as tables, composed in the analytics engine.
              <% else %>
                <span class="ds-conn">{ds.url_template}</span>
              <% end %>
            </div>
            <div class="ds-card-foot">
              <% roll = Map.get(@usage, ds.base_data_source_id, %{queries: 0, charts: 0}) %>
              <span><strong>{roll.queries}</strong> {if roll.queries == 1, do: "query", else: "queries"}</span>
              <span class="ds-foot-dot">·</span>
              <span><strong>{roll.charts}</strong> {if roll.charts == 1, do: "chart", else: "charts"}</span>
              <span class="ds-foot-right">
                <span :if={ds.adapter != "workspace"}>
                  {(ds.created_by && ds.created_by.username) || "unknown"} · {Calendar.strftime(ds.inserted_at, "%b %-d")}
                </span>
                <span :if={@source_filter == ds.base_data_source_id} class="ds-filter-on">filtering ✕</span>
              </span>
            </div>
          </button>
        </div>

        <div class="section-label" style="margin-top:32px">
          Timeline <span class="count">{length(@milestones)}</span>
        </div>
        <%= if @milestones == [] do %>
          <div class="qc-none" style="padding:16px 0">
            No milestones yet. <span class="mono">aveline create-milestone --name "v1.4 shipped" --date 2026-07-06</span>
            marks one; every time-series chart in range annotates itself.
          </div>
        <% else %>
          <div class="tl-strip">
            <div class="tl-line" aria-hidden="true"></div>
            <div
              :for={{m, pct, row} <- timeline_positions(@milestones)}
              class={["tl-marker", row == 1 && "tl-marker-high"]}
              style={"left: #{pct}%"}
            >
              <span class="tl-marker-label">{m.name}</span>
              <span class="tl-marker-dot" aria-hidden="true"></span>
              <div class="tl-tip">
                <div class="tl-tip-name">{m.name}</div>
                <div class="tl-tip-date">{Calendar.strftime(m.date, "%b %-d, %Y")}</div>
                <div :if={m.description} class="tl-tip-desc">{m.description}</div>
              </div>
            </div>
            <span class="tl-edge tl-edge-left">{Calendar.strftime(timeline_start(@milestones), "%b %-d")}</span>
            <span class="tl-edge tl-edge-right">today</span>
          </div>
        <% end %>

        <div class="qc-header">
          <div class="section-label" style="margin:0">
            Query catalog <span class="count">{length(@queries)}</span>
            <button
              :if={@source_filter}
              type="button"
              class="qc-filter-chip"
              phx-click="filter_source"
              phx-value-base={@source_filter}
            >
              {(Map.get(@source_by_base, @source_filter) || %{name: "?"}).name} ✕
            </button>
          </div>
          <form phx-change="search" class="qc-search-form">
            <svg class="qc-search-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/>
            </svg>
            <input
              type="text"
              name="q"
              value={@q}
              placeholder="Search queries…"
              autocomplete="off"
              class="qc-search"
              phx-debounce="150"
            />
          </form>
        </div>

        <% shown = visible_queries(assigns) %>
        <%= if @queries == [] do %>
          <div class="qc-none">
            No queries yet. <span class="mono">aveline create-query --name … --description … --sql …</span> names the first one.
          </div>
        <% else %>
          <%= if shown == [] do %>
            <div class="qc-none">Nothing matches.</div>
          <% else %>
            <div class="qc-grid">
              <button
                :for={query <- shown}
                type="button"
                phx-click="open_query"
                phx-value-name={query.name}
                class="qc-card"
              >
                <div class="qc-card-head">
                  <span class="qc-name">{query.name}</span>
                  <% {label, adapter} = source_chip(query.data_source_id && Map.get(@source_by_base, query.data_source_id)) %>
                  <span class={["ds-chip", "ds-chip-" <> adapter]}>{label}</span>
                </div>
                <div class={["qc-desc", is_nil(query.description) && "qc-desc-missing"]}>
                  {query.description || "No description yet."}
                </div>
                <div class="qc-foot">
                  <span :if={Map.get(@chart_counts, query.name, 0) > 0}>
                    <strong>{Map.get(@chart_counts, query.name)}</strong> {if Map.get(@chart_counts, query.name) == 1, do: "chart", else: "charts"}
                  </span>
                  <span :if={Map.get(@chart_counts, query.name, 0) == 0} class="qc-unused">unused</span>
                  <span :if={Map.get(@built_on, query.name, []) != []}>
                    <span class="ds-foot-dot">·</span>
                    on <strong>{length(Map.get(@built_on, query.name))}</strong>
                  </span>
                  <span :if={Map.get(@dependents, query.name, []) != []}>
                    <span class="ds-foot-dot">·</span>
                    feeds <strong>{length(Map.get(@dependents, query.name))}</strong>
                  </span>
                  <span class="qc-foot-by">
                    {(query.created_by && query.created_by.username) || "unknown"} · {Calendar.strftime(query.inserted_at, "%b %-d")}
                  </span>
                </div>
              </button>
            </div>
          <% end %>
        <% end %>

      <% end %>

      <div
        :if={@selected}
        class="modal-backdrop"
        phx-click="close_query"
        phx-window-keydown="close_query"
        phx-key="escape"
      >
        <%!-- The no-op phx-click makes the card the closest click binding
             for clicks inside it, so they don't reach the backdrop's
             close — while the ✕'s own binding still wins over the card's. --%>
        <div class="modal-card qm-card" phx-click={Phoenix.LiveView.JS.dispatch("aveline:noop")}>
          <div class="qm-head">
            <span class="qc-name qm-name">{@selected.name}</span>
            <% {label, adapter} = source_chip(@selected.data_source_id && Map.get(@source_by_base, @selected.data_source_id)) %>
            <span class={["ds-chip", "ds-chip-" <> adapter]}>{label}</span>
            <span class="ds-chip ds-chip-quiet">v{@selected.version_number}</span>
            <button type="button" class="qm-close" phx-click="close_query" aria-label="Close">✕</button>
          </div>

          <p class={["qm-desc", is_nil(@selected.description) && "qc-desc-missing"]}>
            <%= if @selected.description do %>
              {@selected.description}
            <% else %>
              No description yet. <span class="mono">aveline edit-query {@selected.name} --description "…"</span>
            <% end %>
          </p>

          <div :if={Map.get(@built_on, @selected.name, []) != []} class="qm-deps">
            <span class="qm-deps-label">built on</span>
            <button
              :for={dep <- Map.get(@built_on, @selected.name)}
              type="button"
              class="qm-dep-chip"
              phx-click="open_query"
              phx-value-name={dep}
            >
              {dep}
            </button>
          </div>

          <div :if={Map.get(@dependents, @selected.name, []) != []} class="qm-deps">
            <span class="qm-deps-label">feeds</span>
            <button
              :for={dep <- Map.get(@dependents, @selected.name)}
              type="button"
              class="qm-dep-chip"
              phx-click="open_query"
              phx-value-name={dep}
            >
              {dep}
            </button>
          </div>

          <div :if={Map.get(@charted_in, @selected.name, []) != []} class="qm-deps">
            <span class="qm-deps-label">charted in</span>
            <.link
              :for={doc <- Enum.sort_by(Map.get(@charted_in, @selected.name), & &1.title)}
              navigate={~p"/w/#{@workspace.slug}/d/#{doc.slug}"}
              class="qm-doc-link"
            >
              {doc.title}
            </.link>
          </div>

          <pre
            id={"qm-sql-" <> @selected.name}
            class="q-sql q-sql-loading qm-sql"
            phx-hook="SqlFormat"
            phx-update="ignore"
            data-dialect={formatter_dialect(@selected, @source_by_base)}
          ><code class="language-sql">{@selected.sql}</code></pre>

          <div class="qm-meta">
            {@selected.kind} query · created by {(@selected.created_by && @selected.created_by.username) || "unknown"}
            · {Calendar.strftime(@selected.inserted_at, "%b %-d, %Y")}
          </div>
        </div>
      </div>
    </div>
    """
  end
end
