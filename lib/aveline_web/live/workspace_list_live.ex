defmodule AvelineWeb.WorkspaceListLive do
  @moduledoc false
  use AvelineWeb, :live_view

  alias Aveline.Workspaces
  alias AvelineWeb.LiveSession

  @impl true
  def mount(_params, session, socket) do
    user = LiveSession.current_user(session)

    workspaces =
      case user do
        nil -> []
        u -> Workspaces.list_for_user(u.id)
      end

    {:ok,
     assign(socket,
       page_title: "Aveline · Workspaces",
       current_user: user,
       workspaces: workspaces
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container-narrow">
      <h1 class="page-title">Workspaces</h1>
      <p class="page-subtitle">
        <%= if @current_user do %>
          A wiki you can easily understand.
        <% else %>
          Not signed in.
        <% end %>
      </p>

      <%= if is_nil(@current_user) do %>
        <div class="banner">
          Visit <code>/login/&lt;your-token&gt;</code> to sign in.
          Local tokens are printed by <code>mix ecto.setup</code>.
        </div>
      <% else %>
        <%= if @workspaces == [] do %>
          <div class="empty">No workspaces yet.</div>
        <% else %>
          <ul class="card-list">
            <li :for={w <- @workspaces}>
              <.link navigate={~p"/w/#{w.slug}"} class="card">
                <div class="card-title">{w.name}</div>
                <div class="card-meta">
                  <span class="card-slug">{w.slug}</span>
                </div>
              </.link>
            </li>
          </ul>
        <% end %>
      <% end %>
    </div>
    """
  end
end
