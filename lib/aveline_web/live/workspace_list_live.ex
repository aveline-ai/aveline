defmodule AvelineWeb.WorkspaceListLive do
  @moduledoc """
  `/` lands users on a workspace. Most people have one (their Personal),
  so we just push_navigate there. Signed-out visitors see the auth
  landing. If a user somehow has zero workspaces, the no-workspaces
  state is rendered.

  Future: prefer the most recently visited workspace (cookie / DB).
  """
  use AvelineWeb, :live_view

  alias Aveline.Workspaces
  alias AvelineWeb.LiveSession

  @impl true
  def mount(_params, session, socket) do
    user = LiveSession.current_user(session)

    cond do
      is_nil(user) ->
        {:ok, assign(socket, page_title: "Aveline", current_user: nil, no_workspaces: false)}

      true ->
        case Workspaces.list_for_user(user.id) do
          [%{slug: slug} | _] ->
            {:ok, push_navigate(socket, to: ~p"/w/#{slug}")}

          [] ->
            {:ok,
             assign(socket,
               page_title: "Aveline",
               current_user: user,
               no_workspaces: true
             )}
        end
    end
  end

  @impl true
  def render(assigns) do
    if is_nil(assigns.current_user) do
      render_signed_out(assigns)
    else
      render_no_workspaces(assigns)
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

  defp render_no_workspaces(assigns) do
    ~H"""
    <div class="auth-shell">
      <div class="auth-card">
        <div class="auth-brand">
          <span class="nav-brand-mark">A</span>
          <span class="auth-brand-name">aveline</span>
        </div>
        <h1 class="auth-title">No workspaces</h1>
        <p class="auth-subtitle">
          You're signed in as <strong>{@current_user.username}</strong> but aren't a
          member of any workspace. Ask someone to share an invite link.
        </p>
        <.link navigate={~p"/logout"} class="auth-secondary" style="display:flex;align-items:center;justify-content:center;text-decoration:none;margin-top:8px">
          Log out
        </.link>
      </div>
    </div>
    """
  end
end
