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
  alias Aveline.DocViews
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
           orientation: Docs.get_orientation(ws.id),
           jump_back_in: (user && DocViews.recent_for_user(ws.id, user.id, 3)) || [],
           pinned_docs: load_pinned(ws),
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

  # Start here = the workspace's pinned docs (GitHub-style: 6 slots,
  # the orientation doc permanently holds one and renders as its own
  # card above, so up to 5 show here). Docs with doc_link chains get
  # the trail treatment; plain docs render as plain cards.
  defp load_pinned(ws) do
    ws.id
    |> Docs.list_current(pinned: true)
    |> Enum.reject(&(&1.slug == Docs.orientation_slug()))
    |> Enum.map(fn doc ->
      stops =
        doc.blocks
        |> Docs.enrich_doc_links(ws.id)
        |> Enum.flat_map(fn
          %{"type" => "doc_link", "target" => t} -> [t]
          _ -> []
        end)

      %{doc: doc, stops: stops}
    end)
  end

  defp snippet(body, max \\ 110) do
    body = String.trim(body || "")
    if String.length(body) > max, do: String.slice(body, 0, max) <> "…", else: body
  end

  # Deterministic identity hue for a doc or user — hashed, never stored.
  # Gives every card/avatar a stable personal color, Notion-icon style.
  defp hue(s), do: :erlang.phash2(s || "", 360)

  defp display_name(user) do
    (user && (user.display_name || user.username)) || "there"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="content home-content">
      <div class="home-hero">
        <p class="home-greeting">Welcome back, {display_name(@current_user)}</p>
        <h1 class="page-title home-title">{@workspace.name}</h1>
      </div>

      <.link
        :if={@orientation}
        navigate={~p"/w/#{@workspace.slug}/d/#{@orientation.slug}"}
        class="orientation-card"
      >
        <span class="orientation-icon" aria-hidden="true">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
            <circle cx="12" cy="12" r="10"/>
            <polygon points="16.24 7.76 14.12 14.12 7.76 16.24 9.88 9.88 16.24 7.76"/>
          </svg>
        </span>
        <span class="orientation-body">
          <span class="orientation-title">{@orientation.title}</span>
          <span class="orientation-summary">
            What lives in this workspace and how the team works — for humans and agents alike.
          </span>
        </span>
        <span class="orientation-cta">Get oriented →</span>
      </.link>

      <section :if={@jump_back_in != []} class="shelf">
        <div class="shelf-head">
          <span class="shelf-icon" aria-hidden="true">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>
            </svg>
          </span>
          <span class="shelf-label">Jump back in</span>
        </div>
        <div class="jump-grid">
          <.link
            :for={{d, viewed_at} <- @jump_back_in}
            navigate={~p"/w/#{@workspace.slug}/d/#{d.slug}"}
            class="jump-card"
          >
            <span class="doc-tile doc-tile-sm" style={"--h: #{hue(d.slug)}"}>{initial(d.title)}</span>
            <span class="jump-card-body">
              <span class="jump-card-title">{d.title}</span>
              <span class="jump-card-time" title={absolute_time(viewed_at)}>
                opened {relative_time(viewed_at)}
              </span>
            </span>
          </.link>
        </div>
      </section>

      <section :if={@pinned_docs != []} class="shelf">
        <div class="shelf-head">
          <span class="shelf-icon" aria-hidden="true">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <path d="M12 17v5"/>
              <path d="M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z"/>
            </svg>
          </span>
          <span class="shelf-label">Start here</span>
          <span class="shelf-count">
            {length(@pinned_docs)}/{Docs.pin_limit()} pins
          </span>
        </div>
        <div class="story-grid">
          <.link
            :for={s <- @pinned_docs}
            navigate={~p"/w/#{@workspace.slug}/d/#{s.doc.slug}"}
            class="story-card"
            style={"--h: #{hue(s.doc.slug)}"}
          >
            <div class="story-card-top">
              <span class="doc-tile" style={"--h: #{hue(s.doc.slug)}"}>
                <%= if s.stops != [] do %>
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/>
                    <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>
                  </svg>
                <% else %>
                  {initial(s.doc.title)}
                <% end %>
              </span>
              <span class="story-card-title">{s.doc.title}</span>
              <span :if={s.stops != []} class="story-stops-badge">{length(s.stops)} stops</span>
            </div>
            <div :if={s.doc.summary} class="story-card-summary">{s.doc.summary}</div>
            <div :if={s.stops != []} class="story-card-path">
              <%= for {t, idx} <- Enum.with_index(s.stops) do %>
                <span :if={idx > 0} class="story-path-arrow">→</span>
                <span class={"story-path-stop" <> if t["deleted"], do: " story-path-dead", else: ""}>
                  {t["title"] || "removed"}
                </span>
              <% end %>
            </div>
            <div :if={s.doc.tags != []} class="story-card-tags">
              <span :for={t <- Enum.take(s.doc.tags, 3)} class="story-card-tag">{t}</span>
            </div>
          </.link>
        </div>
      </section>

      <section :if={@needs_you != []} class="shelf">
        <div class="shelf-head">
          <span class="shelf-icon shelf-icon-attn" aria-hidden="true">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
            </svg>
          </span>
          <span class="shelf-label">Needs you</span>
          <span class="shelf-count shelf-count-attn">{length(@needs_you)} open</span>
        </div>
        <div class="attn-list">
          <.link
            :for={{c, d} <- @needs_you}
            navigate={~p"/w/#{@workspace.slug}/d/#{d.slug}" <> if(c.block_id, do: "#" <> c.block_id, else: "")}
            class="attn-row"
          >
            <span
              class="avatar"
              style={"--h: #{hue(c.actor_user && c.actor_user.username)}"}
              aria-hidden="true"
            >
              {initial(c.actor_user && c.actor_user.username)}
            </span>
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
          <span class="shelf-icon" aria-hidden="true">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <polyline points="22 12 18 12 15 21 9 3 6 12 2 12"/>
            </svg>
          </span>
          <span class="shelf-label">Recently changed</span>
        </div>
        <div class="recent-list">
          <.link
            :for={d <- @recent_changes}
            navigate={~p"/w/#{@workspace.slug}/d/#{d.slug}"}
            class="recent-row"
          >
            <span class="doc-tile doc-tile-xs" style={"--h: #{hue(d.slug)}"}>{initial(d.title)}</span>
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

      <%= if @pinned_docs == [] and @needs_you == [] and @recent_changes == [] do %>
        <div class="empty">
          Nothing here yet — create a doc (or have your agent do it) and this
          page fills itself in.
        </div>
      <% end %>
    </div>
    """
  end
end
