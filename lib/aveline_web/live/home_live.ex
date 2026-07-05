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
  alias Aveline.Tags
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
           recently_viewed: (user && DocViews.recent_for_user(ws.id, user.id, 3)) || [],
           pinned_docs: Docs.list_pinned(ws.id),
           needs_you: (user && Comments.list_open_threads_for_owner(ws.id, user.id, 5)) || [],
           recent_changes: Docs.list_current(ws.id, sort: :recent, limit: 5),
           # All tags in the workspace tag order (sort_key override,
           # alphabetical otherwise): the glossary is the vocabulary,
           # not a popularity chart. Chips only; clicking one swaps the
           # hint line below for its description. Explains tags — does
           # not navigate.
           tag_stats: Tags.list_with_stats(ws.id),
           glossary_open: nil
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

  @impl true
  def handle_event("glossary_toggle", %{"slug" => slug}, socket) do
    open = if socket.assigns.glossary_open == slug, do: nil, else: slug
    {:noreply, assign(socket, glossary_open: open)}
  end

  defp open_glossary_row(_rows, nil), do: nil
  defp open_glossary_row(rows, slug), do: Enum.find(rows, &(&1.tag.slug == slug))

  defp snippet(body, max \\ 110) do
    body = String.trim(body || "")
    if String.length(body) > max, do: String.slice(body, 0, max) <> "…", else: body
  end

  defp display_name(user) do
    (user && (user.display_name || user.username)) || "there"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="content home-content">
      <h1 class="page-title home-title">Welcome back, {display_name(@current_user)}</h1>

      <section :if={@pinned_docs != [] or @orientation} class="shelf">
        <div class="shelf-head">
          <span class="shelf-icon" aria-hidden="true">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <path d="M12 17v5"/>
              <path d="M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z"/>
            </svg>
          </span>
          <span class="shelf-label">Pinned docs</span>
        </div>
        <div class="story-grid">
          <.link
            :if={@orientation}
            navigate={~p"/w/#{@workspace.slug}/d/#{@orientation.slug}"}
            class="orientation-card"
          >
            <span class="orientation-body">
              <span class="orientation-title">{@orientation.title}</span>
              <span :if={@orientation.summary} class="orientation-summary">{@orientation.summary}</span>
            </span>
            <span class="orientation-cta">Get oriented →</span>
          </.link>
          <.link
            :for={d <- @pinned_docs}
            navigate={~p"/w/#{@workspace.slug}/d/#{d.slug}"}
            class="story-card"
          >
            <div class="story-card-top">
              <span class="story-card-title">{d.title}</span>
            </div>
            <div :if={d.summary} class="story-card-summary">{d.summary}</div>
            <div :if={d.tags != []} class="story-card-tags">
              <span :for={t <- Enum.take(d.tags, 3)} class="story-card-tag">{t}</span>
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
          <span class="shelf-label">Open comments on your docs</span>
          <span class="shelf-count shelf-count-attn">{length(@needs_you)} open</span>
        </div>
        <div class="attn-list">
          <.link
            :for={{c, d} <- @needs_you}
            navigate={~p"/w/#{@workspace.slug}/d/#{d.slug}" <> if(c.block_id, do: "#" <> c.block_id, else: "")}
            class="attn-row"
          >
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

      <section :if={@recently_viewed != []} class="shelf">
        <div class="shelf-head">
          <span class="shelf-icon" aria-hidden="true">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>
            </svg>
          </span>
          <span class="shelf-label">Recently viewed by you</span>
        </div>
        <div class="jump-grid">
          <.link
            :for={{d, viewed_at} <- @recently_viewed}
            navigate={~p"/w/#{@workspace.slug}/d/#{d.slug}"}
            class="jump-card"
          >
            <span class="jump-card-title">{d.title}</span>
            <span class="jump-card-time" title={absolute_time(viewed_at)}>
              opened {relative_time(viewed_at)}
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
            <span class="recent-title">{d.title}</span>
            <span class="recent-version">v{d.version_number}</span>
            <span :if={d.intent} class="recent-intent">“{d.intent}”</span>
            <span class="recent-time">{relative_time(d.updated_at)}</span>
          </.link>
        </div>
      </section>

      <section :if={@tag_stats != []} class="shelf">
        <div class="shelf-head">
          <span class="shelf-icon" aria-hidden="true">
            <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5">
              <path d="M2 7l5-5h6v6l-5 5z" stroke-linejoin="round" />
              <circle cx="9.5" cy="6.5" r="0.9" fill="currentColor" />
            </svg>
          </span>
          <span class="shelf-label">Tags</span>
        </div>
        <div class="tag-glossary">
          <div class="tag-cloud">
            <button
              :for={row <- @tag_stats}
              type="button"
              phx-click="glossary_toggle"
              phx-value-slug={row.tag.slug}
              class={["chip", "chip-tag", @glossary_open == row.tag.slug && "chip-open"]}
              style={
                if c = row.tag.color do
                  "--tag: #{c}; --tag-dim: #{c}14; --tag-border: #{c}40"
                end
              }
            >
              <span class="chip-text">{row.tag.slug}</span>
            </button>
          </div>
          <div class="tag-info">
            <%= if open = open_glossary_row(@tag_stats, @glossary_open) do %>
              <span class="tag-info-desc">{open.tag.description}</span>
            <% else %>
              <span class="tag-info-hint">Click a tag to read what it means.</span>
            <% end %>
          </div>
        </div>
      </section>

      <%= if @pinned_docs == [] and @needs_you == [] and @recent_changes == [] do %>
        <div class="empty">
          Nothing here yet. Create a doc (or have your agent do it) and this
          page fills itself in.
        </div>
      <% end %>
    </div>
    """
  end
end
