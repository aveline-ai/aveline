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
         )}

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
             )}

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
               result: nil
             )}
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

  def handle_event("validate", %{"username" => raw}, socket) do
    {username, error} = check_username(raw)
    {:noreply, assign(socket, username: username, error: error)}
  end

  def handle_event("submit", %{"username" => raw}, socket) do
    {username, error} = check_username(raw)

    cond do
      error != nil ->
        {:noreply, assign(socket, username: username, error: error)}

      true ->
        case Accounts.signup(%{"username" => username, "invite_code" => socket.assigns.code}) do
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
      <div class="auth-card">
        <div class="auth-brand">
          <span class="nav-brand-mark">A</span>
          <span class="auth-brand-name">aveline</span>
        </div>
        <h1 class="auth-title">Invite link expired</h1>
        <p class="auth-subtitle">
          This invite link is no longer valid. Ask whoever sent it to share a fresh one.
        </p>
      </div>
    </div>
    """
  end

  def render(%{state: :signed_in} = assigns) do
    ~H"""
    <div class="auth-shell">
      <div class="auth-card">
        <div class="auth-brand">
          <span class="nav-brand-mark">A</span>
          <span class="auth-brand-name">aveline</span>
        </div>
        <h1 class="auth-title">Join {@workspace.name}?</h1>
        <p class="auth-subtitle">
          You're signed in as <strong>{@current_user.username}</strong>. Click below
          to add this workspace to your sidebar.
        </p>

        <button phx-click="accept" class="auth-submit">Join workspace</button>
      </div>
    </div>
    """
  end

  def render(%{state: :signup} = assigns) do
    ~H"""
    <div class="auth-shell">
      <div class="auth-card">
        <div class="auth-brand">
          <span class="nav-brand-mark">A</span>
          <span class="auth-brand-name">aveline</span>
        </div>
        <h1 class="auth-title">Join {@workspace.name}</h1>
        <p class="auth-subtitle">
          Pick a username. You'll get an API key (your password), and you'll be added
          to <strong>{@workspace.name}</strong> immediately.
        </p>

        <form phx-change="validate" phx-submit="submit" class="auth-form">
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
            placeholder="e.g. trevor"
            class={"auth-input " <> if @error, do: "auth-input-error", else: ""}
            phx-debounce="250"
            autofocus
          />
          <div class="auth-hint">Lowercase letters, digits, and hyphens. 2–60 chars.</div>
          <%= if @error do %>
            <div class="auth-error">{@error}</div>
          <% end %>

          <button type="submit" class="auth-submit" disabled={@username == "" or @error != nil}>
            Create account & join
          </button>
        </form>
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
      <div class="auth-card auth-card-wide">
        <div class="auth-brand">
          <span class="nav-brand-mark">A</span>
          <span class="auth-brand-name">aveline</span>
        </div>
        <h1 class="auth-title">Save your API key</h1>
        <p class="auth-subtitle">
          You're signed up as <strong>{@user.username}</strong> and have been added to
          <strong>{@workspace.name}</strong>. This is the only time you'll see your
          token — stash it in 1Password now.
        </p>

        <div class="token-display">
          <code id="token-value" class="token-value">{@plaintext}</code>
        </div>

        <div class="auth-actions">
          <button
            type="button"
            id="copy-token-btn"
            class="auth-secondary"
            phx-hook="CopyToken"
            data-target="#token-value"
          >
            Copy token
          </button>

          <form action={~p"/login?next=#{@next_path}"} method="post" id="continue-form">
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <input type="hidden" name="token" value={@plaintext} />
            <button id="continue-btn" type="submit" class="auth-submit" disabled>
              I saved it — go to {@workspace.name}
            </button>
          </form>
        </div>
      </div>
    </div>
    """
  end
end
