defmodule AvelineWeb.InviteLive do
  @moduledoc """
  Landing page for invite links — `/invite/:code`.

    * If the visitor is signed in: shows a "Join {workspace}" confirm button.
      Clicking it adds them to the workspace and redirects to /w/:slug.
    * If they're not signed in: shows the signup form. Successful signup
      creates the user, joins the workspace, and lands them on /w/:slug
      (with their freshly-shown API token in the way of a copy gate).
  """
  use AvelineWeb, :live_view

  alias Aveline.Accounts
  alias Aveline.Tokens
  alias Aveline.Workspaces
  alias AvelineWeb.LiveSession

  @impl true
  def mount(%{"code" => code}, session, socket) do
    user = LiveSession.current_user(session)

    case Workspaces.get_active_invite_by_code(code) do
      nil ->
        {:ok,
         assign(socket,
           page_title: "Aveline · Invite",
           state: :invalid,
           code: code,
           current_user: user
         ), layout: false}

      invite ->
        workspace = invite.workspace

        already_member? =
          user != nil && Workspaces.member?(workspace.id, user.id)

        cond do
          already_member? ->
            {:ok,
             socket
             |> put_flash(:info, "You're already a member.")
             |> push_navigate(to: ~p"/w/#{workspace.slug}")}

          user ->
            {:ok,
             assign(socket,
               page_title: "Aveline · Join #{workspace.name}",
               state: :signed_in,
               code: code,
               invite: invite,
               workspace: workspace,
               current_user: user
             ), layout: false}

          true ->
            {:ok,
             assign(socket,
               page_title: "Aveline · Join #{workspace.name}",
               state: :signup,
               code: code,
               invite: invite,
               workspace: workspace,
               current_user: nil,
               username: "",
               error: nil,
               result: nil,
               # has_token? toggles the modal between "create new account"
               # (default — username + API key preview) and "paste an
               # existing token" (single API key input). Keeps the invite
               # subtitle visible in both modes.
               has_token?: false,
               # When true, the form fires a real HTML POST to /login
               # next render (via phx-trigger-action). We flip this on
               # AFTER a successful signup so the freshly-minted token
               # gets sent to /login, which sets the session cookie and
               # redirects to the workspace.
               trigger_submit: false,
               # Pre-generate the real plaintext token so it can be shown
               # directly in the form (matches signup's pattern). Only
               # persisted (hashed) once they submit.
               preview_token: Tokens.generate_plaintext()
             ), layout: false}
        end
    end
  end

  @impl true
  def handle_event("accept", _, socket) do
    %{current_user: user, workspace: ws} = socket.assigns
    {:ok, _} = Workspaces.ensure_member(ws.id, user.id)

    {:noreply,
     socket
     |> put_flash(:info, "Joined #{ws.name}.")
     |> push_navigate(to: ~p"/w/#{ws.slug}")}
  end

  def handle_event("toggle_has_token", _, socket) do
    {:noreply,
     assign(socket,
       has_token?: not socket.assigns.has_token?,
       error: nil
     )}
  end

  def handle_event("validate", params, socket) do
    {username, error} = check_username(params["username"] || "")
    {:noreply, assign(socket, username: username, error: error)}
  end

  def handle_event("submit", params, socket) do
    {username, username_err} = check_username(params["username"] || "")
    copied = params["copied"] == "true"

    copy_err =
      if copied,
        do: nil,
        else: "Copy the API key first. You will not be able to see it again."

    first_error = username_err || copy_err

    cond do
      first_error != nil ->
        {:noreply, assign(socket, username: username, error: first_error)}

      true ->
        case Accounts.signup(%{
               "username" => username,
               "invite_code" => socket.assigns.code,
               "plaintext_token" => socket.assigns.preview_token
             }) do
          {:ok, _} ->
            # Account exists and the token is in the DB. Trigger the
            # form's regular HTML POST to /login on the next render —
            # /login verifies the token, sets the session cookie, and
            # redirects to the workspace (via next param).
            {:noreply, assign(socket, trigger_submit: true)}

          {:error, %Ecto.Changeset{} = cs} ->
            {:noreply, assign(socket, error: format_changeset(cs))}

          {:error, other} ->
            {:noreply, assign(socket, error: "Signup failed: #{inspect(other)}")}
        end
    end
  end

  defp check_username(raw) do
    username =
      raw
      |> to_string()
      |> String.trim()
      |> String.downcase()

    cond do
      username == "" -> {username, nil}
      String.length(username) < 2 -> {username, "Too short (minimum 2 characters)."}
      String.length(username) > 60 -> {username, "Too long (max 60 characters)."}
      not Regex.match?(~r/^[a-z0-9][a-z0-9-]*$/, username) ->
        {username, "Use lowercase letters, digits, and hyphens. Must start with a letter or digit."}

      Accounts.get_user_by_username(username) ->
        {username, "Username taken."}

      true ->
        {username, nil}
    end
  end

  defp format_changeset(%Ecto.Changeset{} = cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
  end

  @impl true
  def render(%{state: :invalid} = assigns) do
    ~H"""
    <div class="auth-shell">
      <AvelineWeb.AuthBg.split />
      <div class="auth-card auth-card-spare">
        <div class="auth-brand auth-brand-hero">
          <span class="nav-brand-mark" style="width:36px;height:36px">A</span>
          <span class="auth-brand-name" style="font-size:26px">aveline</span>
        </div>
        <h1 class="auth-title" style="text-align:center">Invite link expired</h1>
        <p class="auth-subtitle" style="text-align:center">
          This invite link is no longer valid. Ask whoever sent it to share a fresh one.
        </p>
      </div>
    </div>
    """
  end

  def render(%{state: :signed_in} = assigns) do
    ~H"""
    <div class="auth-shell">
      <AvelineWeb.AuthBg.split />
      <div class="auth-card auth-card-spare">
        <div class="auth-brand auth-brand-hero">
          <span class="nav-brand-mark" style="width:36px;height:36px">A</span>
          <span class="auth-brand-name" style="font-size:26px">aveline</span>
        </div>
        <p class="auth-subtitle" style="text-align:center;margin-bottom:24px">
          You've been invited to <strong>{@workspace.name}</strong>.
          You're signed in as <strong>{@current_user.username}</strong>.
        </p>

        <button phx-click="accept" class="auth-submit">Join {@workspace.name}</button>
      </div>
    </div>
    """
  end

  def render(%{state: :signup} = assigns) do
    can_submit = String.trim(assigns.username || "") != ""
    assigns = assign(assigns, can_submit: can_submit)

    ~H"""
    <div class="auth-shell">
      <AvelineWeb.AuthBg.split />
      <div class="auth-card auth-card-spare">
        <div class="auth-brand auth-brand-hero">
          <span class="nav-brand-mark" style="width:36px;height:36px">A</span>
          <span class="auth-brand-name" style="font-size:26px">aveline</span>
        </div>

        <p class="auth-subtitle" style="text-align:center;margin-bottom:24px">
          You've been invited to <strong>{@workspace.name}</strong>.
          <%= if @has_token? do %>
            Sign in with your API key to accept.
          <% else %>
            Pick a username and you're in.
          <% end %>
        </p>

        <%= if @has_token? do %>
          <form
            action={~p"/login?next=#{"/invite/#{@code}"}"}
            method="post"
            class="auth-form"
            id="invite-login-form"
          >
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <label class="auth-label" for="token">Your API key</label>
            <input
              type="password"
              name="token"
              id="token"
              autocomplete="off"
              autocapitalize="none"
              autocorrect="off"
              spellcheck="false"
              placeholder="avl_…"
              class="auth-input auth-input-hero"
              autofocus
            />
            <div class="auth-hint">Paste the token you saved when you signed up.</div>

            <button type="submit" class="auth-submit">
              Sign in and join {@workspace.name}
            </button>
          </form>

          <div class="auth-footer">
            New to Aveline?
            <button type="button" phx-click="toggle_has_token" class="auth-link">
              Create an account
            </button>
          </div>
        <% else %>
          <form
            action={~p"/login?next=#{"/w/#{@workspace.slug}"}"}
            method="post"
            phx-change="validate"
            phx-submit="submit"
            phx-trigger-action={@trigger_submit}
            class="auth-form"
            id="invite-signup-form"
            phx-hook="TrackCopy"
            data-target="#preview-token-value"
            data-flag="#copied-flag"
          >
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <input type="hidden" name="token" value={@preview_token} />
            <input type="hidden" name="copied" id="copied-flag" value="false" />
            <label class="auth-label" for="username">Username</label>
            <input
              type="text"
              name="username"
              id="username"
              value={@username}
              autocomplete="off"
              autocapitalize="none"
              autocorrect="off"
              spellcheck="false"
              placeholder="arie"
              class="auth-input auth-input-hero"
              phx-debounce="250"
              autofocus
            />

            <label class="auth-label" style="margin-top:18px">Your API key</label>
            <div class="token-field">
              <input
                type="text"
                id="preview-token-value"
                class="token-field-input"
                value={@preview_token}
                readonly
                onfocus="this.select()"
              />
              <button
                type="button"
                id="preview-copy-btn"
                class="token-field-copy"
                phx-hook="CopyToken"
                data-target="#preview-token-value"
                title="Copy"
              >
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">
                  <rect x="9" y="9" width="12" height="12" rx="2" />
                  <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
                </svg>
                <span class="token-field-copy-label">Copy</span>
              </button>
            </div>
            <div class="auth-hint">
              Copy this now. You will not be able to see it again.
            </div>

            <button type="submit" class="auth-submit" disabled={not @can_submit}>
              Join {@workspace.name}
            </button>

            <%= if @error do %>
              <div class="auth-error" style="margin-top:14px;text-align:center">{@error}</div>
            <% end %>
          </form>

          <div class="auth-footer">
            Already have a token?
            <button type="button" phx-click="toggle_has_token" class="auth-link">
              Sign in instead
            </button>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

end
