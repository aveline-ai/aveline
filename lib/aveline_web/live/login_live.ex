defmodule AvelineWeb.LoginLive do
  @moduledoc """
  Token paste form. The submit posts to /login (SessionController.create)
  which verifies the token, sets the session, and redirects to /.
  """
  use AvelineWeb, :live_view

  @impl true
  def mount(_params, session, socket) do
    if session["user_id"] do
      {:ok, push_navigate(socket, to: ~p"/")}
    else
      {:ok, assign(socket, page_title: "Aveline · Log in")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="auth-shell">
      <div class="auth-card">
        <div class="auth-brand">
          <span class="nav-brand-mark">A</span>
          <span class="auth-brand-name">aveline</span>
        </div>
        <h1 class="auth-title">Log in</h1>
        <p class="auth-subtitle">Paste your API token.</p>

        <form action={~p"/login"} method="post" class="auth-form">
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <label class="auth-label" for="token">API token</label>
          <input
            type="password"
            name="token"
            id="token"
            placeholder="avl_…"
            class="auth-input mono"
            autocomplete="off"
            spellcheck="false"
            autofocus
            required
          />
          <div class="auth-hint">Starts with <code>avl_</code> followed by 32 characters.</div>

          <button type="submit" class="auth-submit">Log in</button>
        </form>

        <div class="auth-footer">
          New here?
          <.link navigate={~p"/signup"} class="auth-link">Sign up</.link>
        </div>
      </div>
    </div>
    """
  end
end
