defmodule AvelineWeb.WorkspaceShowLive do
  @moduledoc false
  use AvelineWeb, :live_view

  alias Aveline.Docs
  alias Aveline.Views
  alias AvelineWeb.LiveSession

  @impl true
  def mount(%{"slug" => slug}, session, socket) do
    user = LiveSession.current_user(session)

    case LiveSession.fetch_workspace_for_user(slug, user) do
      {:ok, ws} ->
        items = Docs.list_current(ws.id)
        pinned_count = Enum.count(items, & &1.pinned)

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
           personal_views: Views.list_personal_views(ws.id, user.id),
           team_views: Views.list_team_views(ws.id),
           total_count: length(items),
           pinned_count: pinned_count,
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
  def handle_params(params, _uri, socket) do
    pinned_only = params["pinned"] == "true"

    {:noreply,
     assign(socket,
       selected_tag: params["tag"],
       pinned_only: pinned_only,
       search: params["q"] || "",
       nav_active: if(pinned_only, do: :pinned, else: :all),
       topbar_title: if(pinned_only, do: "Pinned", else: "All docs")
     )}
  end

  @impl true
  def handle_event("toggle_tag", %{"tag" => tag}, socket) do
    new_tag = if socket.assigns.selected_tag == tag, do: nil, else: tag
    {:noreply, push_patch(socket, to: build_path(socket, %{tag: new_tag}))}
  end

  def handle_event("search", %{"value" => v}, socket) do
    {:noreply, push_patch(socket, to: build_path(socket, %{q: v}))}
  end

  def handle_event("clear_filters", _, socket) do
    base = if socket.assigns.pinned_only, do: %{pinned: "true"}, else: %{}
    target =
      if base == %{},
        do: ~p"/w/#{socket.assigns.workspace.slug}",
        else: ~p"/w/#{socket.assigns.workspace.slug}?#{base}"

    {:noreply, push_patch(socket, to: target)}
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
    any_filter = assigns.selected_tag != nil or assigns.search != ""
    total = if assigns.pinned_only, do: assigns.pinned_count, else: length(assigns.items)
    assigns = assign(assigns, shown_items: shown, any_filter: any_filter, total: total)

    ~H"""
    <div class="content">
      <div class="filter-bar">
        <form phx-change="search">
          <input
            type="text"
            name="value"
            value={@search}
            placeholder="Search docs…"
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
          <span>Showing {length(@shown_items)} of {@total}</span>
          <span class="card-meta-dot">·</span>
          <button class="clear" phx-click="clear_filters">clear filters</button>
        </div>
      <% end %>

      <%= if @shown_items == [] do %>
        <div class="empty">
          <%= if @pinned_only do %>
            Nothing pinned yet. Pin a doc from the CLI:
            <code style="margin-left:4px">aveline edit &lt;slug&gt; --pin</code>.
          <% else %>
            No docs match the current filter.
          <% end %>
        </div>
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
                <%= if i.actor_user do %>
                  <span style="display:inline-flex;align-items:center;gap:5px">
                    <AvelineWeb.Icons.actor type={i.actor_type} class="actor-icon" title={i.actor_type} />
                    {i.actor_user.username}
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
