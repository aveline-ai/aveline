defmodule AvelineWeb.WorkspaceShowLive do
  @moduledoc false
  use AvelineWeb, :live_view

  alias Aveline.Items
  alias Aveline.Views
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
          |> Enum.sort_by(fn {t, c} -> {-c, t} end)

        {:ok,
         assign(socket,
           page_title: "Aveline · #{ws.name}",
           current_user: user,
           workspace: ws,
           items: items,
           view_count: length(Views.list_views(ws.id)),
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
  def handle_params(params, _uri, socket) do
    {:noreply,
     assign(socket,
       selected_tag: params["tag"],
       pinned_only: params["pinned"] == "true",
       search: params["q"] || ""
     )}
  end

  @impl true
  def handle_event("toggle_tag", %{"tag" => tag}, socket) do
    new_tag = if socket.assigns.selected_tag == tag, do: nil, else: tag
    {:noreply, push_patch(socket, to: build_path(socket, %{tag: new_tag}))}
  end

  def handle_event("toggle_pinned", _, socket) do
    {:noreply,
     push_patch(socket, to: build_path(socket, %{pinned: not socket.assigns.pinned_only}))}
  end

  def handle_event("search", %{"value" => v}, socket) do
    {:noreply, push_patch(socket, to: build_path(socket, %{q: v}))}
  end

  def handle_event("clear_filters", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/w/#{socket.assigns.workspace.slug}")}
  end

  defp build_path(socket, overrides) when is_map(overrides) do
    base = %{
      tag: socket.assigns.selected_tag,
      pinned: if(socket.assigns.pinned_only, do: "true"),
      q: nz(socket.assigns.search)
    }

    query =
      base
      |> Map.merge(overrides)
      |> Enum.reject(fn {_k, v} -> v in [nil, "", false] end)
      |> Map.new()

    if query == %{} do
      ~p"/w/#{socket.assigns.workspace.slug}"
    else
      ~p"/w/#{socket.assigns.workspace.slug}?#{query}"
    end
  end

  defp nz(""), do: nil
  defp nz(s), do: s

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
    shown = filtered(assigns.items, assigns.selected_tag, assigns.pinned_only, assigns.search)
    pinned_count = Enum.count(assigns.items, & &1.pinned)
    any_filter = assigns.selected_tag != nil or assigns.pinned_only or assigns.search != ""

    assigns =
      assign(assigns,
        shown_items: shown,
        pinned_count: pinned_count,
        any_filter: any_filter
      )

    ~H"""
    <div class="container">
      <h1 class="page-title">{@workspace.name}</h1>
      <p class="page-subtitle">
        <span class="mono">{@workspace.slug}</span>
        <span class="card-meta-dot">·</span>
        {length(@items)} notes
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
          Views <span class="count">{@view_count}</span>
        </.link>
      </div>

      <div class="filter-bar">
        <form phx-change="search">
          <input
            type="text"
            name="value"
            value={@search}
            placeholder="Search titles…"
            class="search-input"
            autocomplete="off"
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

      <%= if @any_filter do %>
        <div class="filter-status">
          <span>Showing {length(@shown_items)} of {length(@items)}</span>
          <span class="card-meta-dot">·</span>
          <button class="clear" phx-click="clear_filters">clear filters</button>
        </div>
      <% end %>

      <%= if @shown_items == [] do %>
        <div class="empty">No notes match the current filter.</div>
      <% else %>
        <ul class="card-list">
          <li :for={i <- @shown_items}>
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
                <span title={absolute_time(i.updated_at)}>
                  {relative_time(i.updated_at)}
                </span>
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
