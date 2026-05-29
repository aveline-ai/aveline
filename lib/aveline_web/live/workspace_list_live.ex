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
    if is_nil(assigns.current_user) do
      render_signed_out(assigns)
    else
      render_signed_in(assigns)
    end
  end

  defp render_signed_out(assigns) do
    ~H"""
    <div class="auth-shell">
      <div class="auth-card">
        <div class="auth-brand">
          <span class="nav-brand-mark">A</span>
          <span class="auth-brand-name">aveline</span>
        </div>
        <h1 class="auth-title">A wiki you can easily understand.</h1>
        <p class="auth-subtitle">
          Sign up — pick a username, get an API key. That key is your password.
          Save it somewhere safe.
        </p>

        <div style="display:flex;flex-direction:column;gap:10px;margin-top:8px">
          <.link navigate={~p"/signup"} class="auth-submit" style="display:flex;align-items:center;justify-content:center;text-decoration:none">
            Sign up
          </.link>
          <.link navigate={~p"/login"} class="auth-secondary" style="display:flex;align-items:center;justify-content:center;text-decoration:none">
            I already have a token
          </.link>
        </div>
      </div>
    </div>
    """
  end

  defp render_signed_in(assigns) do
    ~H"""
    <div class="container-narrow">
      <h1 class="page-title">Workspaces</h1>
      <p class="page-subtitle">Pick one to get started.</p>

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
    </div>
    """
  end
end
