defmodule AvelineWeb.HomeLive do
  @moduledoc """
  Workspace home — the front door. Answers the three questions a human
  has when they open the wiki: where do I start (stories), what needs
  me (open threads), what changed (recent versions + intent). The full
  library lives on its own Docs tab; searching from here jumps there.
  """
  use AvelineWeb, :live_view

  alias Aveline.Comments
  alias Aveline.Docs
  alias Aveline.Workspaces
  alias AvelineWeb.LiveSession

  @impl true
  def mount(%{"slug" => slug}, session, socket) do
    user = LiveSession.current_user(session)

    case LiveSession.fetch_workspace_for_user(slug, user) do
      {:ok, ws} ->
        {:ok,
         assign(socket,
           page_title: "Aveline · #{ws.name}",
           current_user: user,
           workspace: ws,
           sidebar_workspaces: Workspaces.list_for_user(user.id),
           nav_active: :home,
           topbar_title: "Home",
           stories: load_stories(ws),
           needs_you: Comments.list_open_threads_for_workspace(ws.id, 5),
           recent_changes: Docs.list_current(ws.id, pin_mode: :interleave, sort: :recent, limit: 5)
         )}

      :not_found ->
        {:ok,
         socket
         |> put_flash(:error, "Workspace not found.")
         |> push_navigate(to: ~p"/")}

      :forbidden ->
        {:ok,
         socket
         |> put_flash(:error, "You are not a member of this workspace.")
         |> push_navigate(to: ~p"/")}
    end
  end

  # Stories with their stops' read-time targets, ready to render as
  # trail cards.
  defp load_stories(ws) do
    ws.id
    |> Docs.list_stories()
    |> Enum.map(fn story ->
      stops =
        story.blocks
        |> Docs.enrich_doc_links(ws.id)
        |> Enum.flat_map(fn
          %{"type" => "doc_link", "target" => t} -> [t]
          _ -> []
        end)

      %{doc: story, stops: stops}
    end)
  end

  defp snippet(body, max \\ 110) do
    body = String.trim(body || "")
    if String.length(body) > max, do: String.slice(body, 0, max) <> "…", else: body
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="content">
      <h1 class="page-title">{@workspace.name}</h1>
      <p class="page-subtitle">
        Start here, catch up on what needs you, and see what changed.
      </p>

      <section :if={@stories != []} class="shelf">
        <div class="shelf-head">
          <span class="shelf-label">Start here</span>
        </div>
        <div class="story-grid">
          <.link
            :for={s <- @stories}
            navigate={~p"/w/#{@workspace.slug}/d/#{s.doc.slug}"}
            class="story-card"
          >
            <div class="story-card-top">
              <span class="story-icon" aria-hidden="true">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/>
                  <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>
                </svg>
              </span>
              <span class="story-card-title">{s.doc.title}</span>
              <span class="story-stops-badge">{length(s.stops)} stops</span>
            </div>
            <div :if={s.doc.summary} class="story-card-summary">{s.doc.summary}</div>
            <div class="story-card-path">
              <%= for {t, idx} <- Enum.with_index(s.stops) do %>
                <span :if={idx > 0} class="story-path-arrow">→</span>
                <span class={"story-path-stop" <> if t["deleted"], do: " story-path-dead", else: ""}>
                  {t["title"] || "removed"}
                </span>
              <% end %>
            </div>
          </.link>
        </div>
      </section>

      <section :if={@needs_you != []} class="shelf">
        <div class="shelf-head">
          <span class="shelf-label">Needs you</span>
          <span class="shelf-count">{length(@needs_you)} open</span>
        </div>
        <div class="attn-list">
          <.link
            :for={{c, d} <- @needs_you}
            navigate={~p"/w/#{@workspace.slug}/d/#{d.slug}" <> if(c.block_id, do: "#" <> c.block_id, else: "")}
            class="attn-row"
          >
            <span class="attn-dot" aria-hidden="true"></span>
            <span class="attn-body">“{snippet(c.body)}”</span>
            <span class="attn-meta">
              <%= if c.actor_user do %>{c.actor_user.username}<% end %><%= if c.actor_type == "agent" do %>
                <span class="attn-via">via Claude</span>
              <% end %>
              on <span class="attn-doc">{d.title}</span>
              · {relative_time(c.inserted_at)}
            </span>
          </.link>
        </div>
      </section>

      <section :if={@recent_changes != []} class="shelf">
        <div class="shelf-head">
          <span class="shelf-label">Recently changed</span>
        </div>
        <div class="recent-list">
          <.link
            :for={d <- @recent_changes}
            navigate={~p"/w/#{@workspace.slug}/d/#{d.slug}"}
            class="recent-row"
          >
            <span class="recent-title">{d.title}</span>
            <span class="recent-version">v{d.version_number}</span>
            <span :if={d.intent} class="recent-intent">“{d.intent}”</span>
            <span class="recent-time">{relative_time(d.updated_at)}</span>
          </.link>
        </div>
        <div class="home-browse-all">
          <.link navigate={~p"/w/#{@workspace.slug}/docs"} class="home-browse-all-link">
            Browse all docs →
          </.link>
        </div>
      </section>

      <%= if @stories == [] and @needs_you == [] and @recent_changes == [] do %>
        <div class="empty">
          Nothing here yet — create a doc (or have your agent do it) and this
          page fills itself in.
        </div>
      <% end %>
    </div>
    """
  end
end
