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
      <div class="auth-card auth-card-spare">
        <div class="auth-brand auth-brand-hero">
          <span class="nav-brand-mark" style="width:36px;height:36px">A</span>
          <span class="auth-brand-name" style="font-size:26px">aveline</span>
        </div>

        <form action={~p"/login"} method="post" class="auth-form">
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <label class="auth-label" for="token">API key</label>
          <input
            type="text"
            name="token"
            id="token"
            placeholder="avl_…"
            class="auth-input auth-input-hero mono"
            autocomplete="off"
            autocapitalize="none"
            autocorrect="off"
            spellcheck="false"
            data-1p-ignore
            data-lpignore="true"
            data-bwignore
            autofocus
            required
          />

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
