defmodule AvelineWeb.ViewShowLive do
  @moduledoc false
  use AvelineWeb, :live_view

  alias Aveline.Docs
  alias Aveline.Views
  alias AvelineWeb.LiveSession

  @impl true
  def mount(%{"slug" => slug, "view_slug" => view_slug}, session, socket) do
    user = LiveSession.current_user(session)

    case LiveSession.fetch_workspace_for_user(slug, user) do
      {:ok, ws} ->
        case Views.get_by_slug(ws.id, view_slug) do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, "View not found.")
             |> push_navigate(to: ~p"/w/#{ws.slug}/views")}

          view ->
            items = Views.matching_items(view)
            all_items = Docs.list_current(ws.id)

            {:ok,
             assign(socket,
               page_title: "Aveline · View · #{view.name}",
               current_user: user,
               workspace: ws,
               personal_views: Views.list_personal_views(ws.id, user.id),
               team_views: Views.list_team_views(ws.id),
               total_count: length(all_items),
               pinned_count: Enum.count(all_items, & &1.pinned),
               nav_active: {:view, view.slug},
               topbar_title: view.name,
               view: view,
               items: items,
               pinned_only: false
             )}
        end

      :not_found ->
        {:ok, socket |> put_flash(:error, "Workspace not found.") |> push_navigate(to: ~p"/")}

      :forbidden ->
        {:ok, socket |> put_flash(:error, "Forbidden.") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("toggle_pinned", _params, socket) do
    {:noreply, update(socket, :pinned_only, &(!&1))}
  end

  @impl true
  def render(assigns) do
    pinned_count = Enum.count(assigns.items, & &1.pinned)
    shown = if assigns.pinned_only, do: Enum.filter(assigns.items, & &1.pinned), else: assigns.items

    assigns =
      assign(assigns, shown_items: shown, pinned_in_view: pinned_count)

    ~H"""
    <div class="content">
      <%= if @view.description && @view.description != "" do %>
        <p style="color:var(--text-secondary);font-size:14px;margin-bottom:14px">
          {@view.description}
        </p>
      <% end %>

      <div class="chip-row" style="margin-bottom:14px;align-items:center">
        <span style="font-size:12px;color:var(--text-muted);margin-right:2px">Filter:</span>
        <%= if @view.tag_filter == [] do %>
          <span class="chip">all notes</span>
        <% else %>
          <span :for={tag <- @view.tag_filter} class="chip chip-accent">{tag}</span>
        <% end %>
      </div>

      <div class="filter-status" style="margin-bottom:14px">
        <span>{length(@items)} matching · {@pinned_in_view} pinned</span>
        <span class="card-meta-dot">·</span>
        <button class="clear" phx-click="toggle_pinned">
          {if @pinned_only, do: "show all", else: "show pinned only"}
        </button>
      </div>

      <%= if @shown_items == [] do %>
        <div class="empty">No notes match this view.</div>
      <% else %>
        <ul class="card-list">
          <li :for={i <- @shown_items}>
            <.link navigate={~p"/w/#{@workspace.slug}/d/#{i.slug}"} class="card">
              <div class="card-title">
                <%= if i.pinned do %>
                  <span class="pin" title="Pinned">
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor">
                      <path d="M12 2l2.39 7.36H22l-6.18 4.49L18.21 22 12 17.27 5.79 22l2.39-8.15L2 9.36h7.61z" />
                    </svg>
                  </span>
                <% end %>
                {i.title}
              </div>
              <%= if i.summary do %>
                <div class="card-summary">{i.summary}</div>
              <% end %>
              <div class="card-meta">
                <%= if i.owner do %>
                  <span class="owner-chip">
                    <span
                      class="avatar-sm"
                      style={"background:hsl(#{avatar_hue(i.owner.username)},65%,18%);color:hsl(#{avatar_hue(i.owner.username)},75%,75%)"}
                    >
                      {initial(i.owner.username)}
                    </span>
                    {i.owner.username}
                  </span>
                  <span class="card-meta-dot">·</span>
                <% end %>
                <span title={absolute_time(i.updated_at)}>{relative_time(i.updated_at)}</span>
                <%= if i.tags != [] do %>
                  <span class="card-meta-dot">·</span>
                  <span style="display:flex;gap:4px;flex-wrap:wrap">
                    <span :for={t <- i.tags} class="chip">{t}</span>
                  </span>
                <% end %>
              </div>
            </.link>
          </li>
        </ul>
      <% end %>
    </div>
    """
  end
end
