defmodule AvelineWeb.ViewListLive do
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
        {:ok,
         assign(socket,
           page_title: "Aveline · Views · #{ws.name}",
           current_user: user,
           workspace: ws,
           views: Views.list_views(ws.id),
           item_count: length(Items.list_items(ws.id))
         )}

      :not_found ->
        {:ok, socket |> put_flash(:error, "Workspace not found.") |> push_navigate(to: ~p"/")}

      :forbidden ->
        {:ok, socket |> put_flash(:error, "Forbidden.") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <div class="page-eyebrow">Workspace</div>
      <h1 class="page-title">{@workspace.name}</h1>
      <p class="page-subtitle">
        <span class="mono">{@workspace.slug}</span>
        · {@item_count} notes
      </p>

      <div class="tabs">
        <.link navigate={~p"/w/#{@workspace.slug}"} class="tab">
          All <span class="count">{@item_count}</span>
        </.link>
        <.link navigate={~p"/w/#{@workspace.slug}"} class="tab">
          Pinned
        </.link>
        <span class="tab tab-active">
          Views <span class="count">{length(@views)}</span>
        </span>
      </div>

      <%= if @views == [] do %>
        <div class="empty">No saved views yet.</div>
      <% else %>
        <ul class="card-list">
          <li :for={v <- @views}>
            <.link navigate={~p"/w/#{@workspace.slug}/v/#{v.slug}"} class="card">
              <div class="card-title">{v.name}</div>
              <%= if v.description do %>
                <div class="card-summary">{v.description}</div>
              <% end %>
              <div class="card-meta">
                <span class="card-slug">{v.slug}</span>
                <%= if v.tag_filter != [] do %>
                  <span style="display:flex;gap:4px;flex-wrap:wrap">
                    <span :for={t <- v.tag_filter} class="chip chip-accent">{t}</span>
                  </span>
                <% else %>
                  <span class="card-slug">all notes</span>
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
