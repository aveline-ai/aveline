defmodule AvelineWeb.WorkspaceShowLive do
  @moduledoc false
  use AvelineWeb, :live_view

  alias Aveline.Items
  alias AvelineWeb.LiveSession

  @impl true
  def mount(%{"slug" => slug}, session, socket) do
    user = LiveSession.current_user(session)

    case LiveSession.fetch_workspace_for_user(slug, user) do
      {:ok, ws} ->
        items = Items.list_items(ws.id)

        tag_counts =
          items
          |> Enum.flat_map(& &1.tags)
          |> Enum.frequencies()
          |> Enum.sort_by(fn {_t, c} -> -c end)

        {:ok,
         assign(socket,
           page_title: "Aveline · #{ws.name}",
           current_user: user,
           workspace: ws,
           items: items,
           tag_counts: tag_counts,
           selected_tag: nil,
           pinned_only: false,
           search: ""
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
  def handle_event("toggle_tag", %{"tag" => tag}, socket) do
    new_tag = if socket.assigns.selected_tag == tag, do: nil, else: tag
    {:noreply, assign(socket, :selected_tag, new_tag)}
  end

  def handle_event("toggle_pinned", _, socket) do
    {:noreply, assign(socket, :pinned_only, not socket.assigns.pinned_only)}
  end

  def handle_event("search", %{"value" => v}, socket) do
    {:noreply, assign(socket, :search, v)}
  end

  defp filtered(items, tag, pinned_only, search) do
    items
    |> Enum.filter(fn i -> not pinned_only or i.pinned end)
    |> Enum.filter(fn i -> is_nil(tag) or tag in i.tags end)
    |> Enum.filter(fn i ->
      case String.trim(search || "") do
        "" -> true
        s -> String.contains?(String.downcase(i.title), String.downcase(s))
      end
    end)
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        filtered_items:
          filtered(assigns.items, assigns.selected_tag, assigns.pinned_only, assigns.search),
        pinned_count: Enum.count(assigns.items, & &1.pinned)
      )

    ~H"""
    <div class="container">
      <div class="page-eyebrow">Workspace</div>
      <h1 class="page-title">{@workspace.name}</h1>
      <p class="page-subtitle">
        <span class="mono">{@workspace.slug}</span>
        · {length(@items)} notes
      </p>

      <div class="tabs">
        <button
          phx-click="toggle_pinned"
          class={"tab " <> if @pinned_only, do: "", else: "tab-active"}
        >
          All <span class="count">{length(@items)}</span>
        </button>
        <button
          phx-click="toggle_pinned"
          class={"tab " <> if @pinned_only, do: "tab-active", else: ""}
        >
          Pinned <span class="count">{@pinned_count}</span>
        </button>
        <.link navigate={~p"/w/#{@workspace.slug}/views"} class="tab">
          Views <span class="count">{length(Aveline.Views.list_views(@workspace.id))}</span>
        </.link>
      </div>

      <div class="filter-bar">
        <form phx-change="search">
          <input
            type="text"
            name="value"
            value={@search}
            placeholder="Search notes…"
            class="search-input"
          />
        </form>
        <%= if @tag_counts != [] do %>
          <div class="chip-row">
            <button
              :for={{tag, count} <- @tag_counts}
              phx-click="toggle_tag"
              phx-value-tag={tag}
              class={"chip " <> if @selected_tag == tag, do: "chip-active", else: ""}
            >
              {tag} <span style="opacity:0.55;margin-left:4px">{count}</span>
            </button>
          </div>
        <% end %>
      </div>

      <%= if @filtered_items == [] do %>
        <div class="empty">No notes match the current filter.</div>
      <% else %>
        <ul class="card-list">
          <li :for={i <- @filtered_items}>
            <.link navigate={~p"/w/#{@workspace.slug}/i/#{i.slug}"} class="card">
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
                <span class="card-slug">{i.slug}</span>
                <%= if i.tags != [] do %>
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
