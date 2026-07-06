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
           usage: chart_usage(ws.id)
         )}

      :not_found ->
        {:ok, socket |> put_flash(:error, "Workspace not found.") |> push_navigate(to: ~p"/")}

      :forbidden ->
        {:ok, socket |> put_flash(:error, "Forbidden.") |> push_navigate(to: ~p"/")}
    end
  end

  # base_data_source_id => [%{slug, title, charts: n}] — which live docs
  # chart each source. Derived from block JSON at read time, so it can't
  # drift; nothing is stored.
  defp chart_usage(workspace_id) do
    workspace_id
    |> Docs.list_current()
    |> Enum.reduce(%{}, fn doc, acc ->
      doc.blocks
      |> List.wrap()
      |> Enum.filter(&(is_map(&1) and &1["type"] == "chart" and is_binary(&1["data_source_id"])))
      |> Enum.frequencies_by(& &1["data_source_id"])
      |> Enum.reduce(acc, fn {base_id, count}, inner ->
        entry = %{slug: doc.slug, title: doc.title, charts: count}
        Map.update(inner, base_id, [entry], &[entry | &1])
      end)
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
          <div :for={ds <- @sources} class={["ds-row", ds.deleted_at && "ds-row-deleted"]}>
            <div class="ds-row-main">
              <span class="ds-name">{ds.name}</span>
              <span class={["ds-adapter", "ds-adapter-" <> ds.adapter]}>{ds.adapter}</span>
              <span :if={ds.deleted_at} class="ds-deleted-badge">deleted · password destroyed</span>
            </div>
            <div class="ds-row-meta">
              <span class="ds-conn">{ds.url_template}</span>
              <span class="ds-dot">·</span>
              <span>connected by {(ds.created_by && ds.created_by.username) || "unknown"}</span>
              <span class="ds-dot">·</span>
              <span>{Calendar.strftime(ds.inserted_at, "%b %-d, %Y")}</span>
            </div>
            <div class="ds-row-usage">
              <%= case Map.get(@usage, ds.base_data_source_id, []) do %>
                <% [] -> %>
                  <span class="ds-unused">no charts yet</span>
                <% docs -> %>
                  <span class="ds-used">
                    {total_charts(docs)} {if total_charts(docs) == 1, do: "chart", else: "charts"} in
                  </span>
                  <.link
                    :for={d <- Enum.sort_by(docs, & &1.slug)}
                    navigate={~p"/w/#{@workspace.slug}/d/#{d.slug}"}
                    class="ds-doc-link"
                  >
                    {d.title}
                  </.link>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp total_charts(docs), do: docs |> Enum.map(& &1.charts) |> Enum.sum()
end
