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
          {:ok, %{user: user, joined_workspace: ws, token: plaintext}} when ws != nil ->
            {:noreply,
             assign(socket,
               state: :show_token,
               result: %{user: user, workspace: ws, token: plaintext}
             )}

          {:ok, %{user: user, workspace: ws, token: plaintext}} ->
            # Shouldn't happen (we passed an invite_code), but fall back safely.
            {:noreply,
             assign(socket,
               state: :show_token,
               result: %{user: user, workspace: ws, token: plaintext}
             )}

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
          You've been invited to <strong>{@workspace.name}</strong>. Pick a username and you're in.
        </p>

        <form
          phx-change="validate"
          phx-submit="submit"
          class="auth-form"
          id="invite-signup-form"
          phx-hook="TrackCopy"
          data-target="#preview-token-value"
          data-flag="#copied-flag"
        >
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
          <.link navigate={~p"/login"} class="auth-link">Log in</.link>
        </div>
      </div>
    </div>
    """
  end

  def render(%{state: :show_token, result: %{user: user, workspace: ws, token: plaintext}} = assigns) do
    assigns =
      assign(assigns,
        user: user,
        workspace: ws,
        plaintext: plaintext,
        next_path: "/w/" <> ws.slug
      )

    ~H"""
    <div class="auth-shell" id="show-token-shell" phx-hook="UnsavedTokenGuard">
      <AvelineWeb.AuthBg.split />
      <div class="auth-card auth-card-wide">
        <div class="auth-brand">
          <span class="nav-brand-mark">A</span>
          <span class="auth-brand-name">aveline</span>
        </div>
        <h1 class="auth-title">Save your API key</h1>
        <p class="auth-subtitle">
          You're signed up as <strong>{@user.username}</strong> and have been added to
          <strong>{@workspace.name}</strong>. This is the only time you'll see your
          token. Stash it in 1Password now.
        </p>

        <div class="token-field">
          <input
            type="text"
            id="token-value"
            class="token-field-input"
            value={@plaintext}
            readonly
            onfocus="this.select()"
          />
          <button
            type="button"
            id="copy-token-btn"
            class="token-field-copy"
            phx-hook="CopyToken"
            data-target="#token-value"
            title="Copy"
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">
              <rect x="9" y="9" width="12" height="12" rx="2" />
              <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
            </svg>
            <span class="token-field-copy-label">Copy</span>
          </button>
        </div>

        <form action={~p"/login?next=#{@next_path}"} method="post" id="continue-form" style="margin-top:16px">
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <input type="hidden" name="token" value={@plaintext} />
          <button id="continue-btn" type="submit" class="auth-submit" disabled>
            I saved it, go to {@workspace.name}
          </button>
        </form>
      </div>
    </div>
    """
  end
end
