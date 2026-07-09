defmodule AvelineWeb.DataSourceShowLive do
  @moduledoc """
  A single data source's detail page: the queries built on it (its
  lineage — "what's built on me"), and the docs that chart it. The
  workspace source shows its derived-query catalog instead of raw
  queries. Read-only, like the list page — humans look, agents wire.
  """
  use AvelineWeb, :live_view

  alias Aveline.DataSources
  alias Aveline.DataSources.Queries
  alias Aveline.Docs
  alias Aveline.Workspaces
  alias AvelineWeb.LiveSession

  @impl true
  def mount(%{"slug" => slug, "name" => name}, session, socket) do
    user = LiveSession.current_user(session)

    with {:ok, ws} <- LiveSession.fetch_workspace_for_user(slug, user),
         %{} = source <- DataSources.get_current_by_name(ws.id, name) do
      workspace? = source.adapter == "workspace"

      # Raw sources: the raw queries built on them. Workspace source:
      # the derived catalog. Each query carries the derived queries that
      # depend on it, so lineage reads both ways.
      queries =
        if workspace?,
          do: Enum.filter(Queries.list_for_workspace(ws.id), &(&1.kind == "derived")),
          else: Queries.list_for_source(ws.id, source.base_data_source_id)

      {:ok,
       assign(socket,
         page_title: "Aveline · #{source.name} · #{ws.name}",
         current_user: user,
         workspace: ws,
         sidebar_workspaces: Workspaces.list_for_user(user.id),
         sidebar_views: Aveline.Views.list_pinned(ws.id),
         nav_active: :data_sources,
         topbar_title: source.name,
         source: source,
         workspace?: workspace?,
         queries: queries,
         built_on: built_on_index(queries),
         dependents: dependents_index(ws.id),
         charting_docs: charting_docs(ws.id, source.base_data_source_id)
       )}
    else
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Data source not found.")
         |> push_navigate(to: ~p"/w/#{slug}/data-sources")}

      :not_found ->
        {:ok, socket |> put_flash(:error, "Workspace not found.") |> push_navigate(to: ~p"/")}

      :forbidden ->
        {:ok, socket |> put_flash(:error, "Forbidden.") |> push_navigate(to: ~p"/")}
    end
  end

  # query name => the catalog queries it's built on (its upstream refs).
  # This is what explains a query: what it composes. Raw queries read
  # their source's tables, not catalog queries, so they have none.
  defp built_on_index(queries) do
    Enum.reduce(queries, %{}, fn q, acc ->
      case q.kind == "derived" && Aveline.DataSources.Engine.parse(q.sql) do
        {:ok, refs} -> Map.put(acc, q.name, Enum.sort(refs))
        _ -> acc
      end
    end)
  end

  # query name => [derived query names that reference it] (downstream —
  # what breaks if you change it). Parsed from the live catalog.
  defp dependents_index(workspace_id) do
    derived = Enum.filter(Queries.list_for_workspace(workspace_id), &(&1.kind == "derived"))

    Enum.reduce(derived, %{}, fn dq, acc ->
      case Aveline.DataSources.Engine.parse(dq.sql) do
        {:ok, refs} ->
          Enum.reduce(refs, acc, fn ref, inner ->
            Map.update(inner, ref, [dq.name], &[dq.name | &1])
          end)

        {:error, _} ->
          acc
      end
    end)
  end

  # sql-formatter's closest supported dialect for a source's engine.
  defp formatter_dialect("mysql"), do: "mysql"
  defp formatter_dialect("redshift"), do: "redshift"
  defp formatter_dialect(_), do: "postgresql"

  # Which live docs chart this source, and how many charts each. Charts
  # reference named queries; map each query to its source.
  defp charting_docs(workspace_id, source_base_id) do
    ws_source = DataSources.workspace_source(workspace_id)
    ws_base = ws_source && ws_source.base_data_source_id

    q_source =
      Queries.list_for_workspace(workspace_id)
      |> Map.new(fn q -> {q.name, q.data_source_id || ws_base} end)

    charts_for = fn block ->
      case block do
        %{"type" => "chart", "query_ref" => ref} -> Map.get(q_source, ref) == source_base_id
        %{"type" => "chart", "data_source_id" => b} -> b == source_base_id
        _ -> false
      end
    end

    workspace_id
    |> Docs.list_current()
    |> Enum.flat_map(fn doc ->
      count = doc.blocks |> List.wrap() |> Enum.count(charts_for)
      if count > 0, do: [%{slug: doc.slug, title: doc.title, charts: count}], else: []
    end)
    |> Enum.sort_by(& &1.slug)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="content">
      <.link navigate={~p"/w/#{@workspace.slug}/data-sources"} class="ds-back">← Data sources</.link>

      <div class="ds-detail-head">
        <h1 class="page-title">{@source.name}</h1>
        <span class={["ds-adapter", "ds-adapter-" <> @source.adapter]}>
          {DataSources.dialect_label(@source.adapter)}
        </span>
        <span :if={@workspace?} class="ds-builtin-badge">built-in</span>
      </div>
      <p class="page-subtitle">
        <%= if @workspace? do %>
          The query catalog. These derived queries compose other queries in the analytics engine (DuckDB): regressions, window functions, and cross-source joins the source dialects can't express.
        <% else %>
          <span class="ds-conn">{@source.url_template}</span>
        <% end %>
      </p>

      <h2 class="ds-section-title">
        {if @workspace?, do: "Catalog queries", else: "Queries built on this source"}
      </h2>

      <%= if @queries == [] do %>
        <p class="ds-empty-copy">
          No queries yet. Your agent defines them: a named, versioned query is the reusable unit charts build on.
        </p>
      <% else %>
        <div class="q-list">
          <div :for={q <- @queries} class="q-row">
            <div class="q-row-main">
              <span class="q-name">{q.name}</span>
              <span class={["q-kind", "q-kind-" <> q.kind]}>{q.kind}</span>
              <span class="q-ver">v{q.version_number}</span>
            </div>
            <div :if={Map.get(@built_on, q.name, []) != []} class="q-deps">
              built on
              <span :for={dep <- Map.get(@built_on, q.name)} class="q-dep-chip">{dep}</span>
            </div>
            <pre
              id={"q-sql-" <> q.name}
              class="q-sql q-sql-loading"
              phx-hook="SqlFormat"
              phx-update="ignore"
              data-dialect={formatter_dialect(@source.adapter)}
            ><code class="language-sql">{q.sql}</code></pre>
            <div :if={Map.get(@dependents, q.name)} class="q-deps q-deps-feeds">
              feeds
              <span :for={dep <- Enum.sort(Map.get(@dependents, q.name))} class="q-dep-chip">{dep}</span>
            </div>
          </div>
        </div>
      <% end %>

      <h2 class="ds-section-title">Charted in</h2>
      <%= if @charting_docs == [] do %>
        <p class="ds-empty-copy">No docs chart this source yet.</p>
      <% else %>
        <div class="ds-doc-list">
          <.link
            :for={d <- @charting_docs}
            navigate={~p"/w/#{@workspace.slug}/d/#{d.slug}"}
            class="ds-doc-row"
          >
            <span>{d.title}</span>
            <span class="ds-count">{d.charts} {if d.charts == 1, do: "chart", else: "charts"}</span>
          </.link>
        </div>
      <% end %>
    </div>
    """
  end
end
