defmodule AvelineWeb.SignupLive do
  @moduledoc """
  Token-only signup. Pick a username + name your first workspace, get an
  API key. The key is the credential — save it like a password.

  Two states:
    * `:form` — collecting username + workspace name. A styled "preview"
      API key is shown right in the form so the user can see what
      they're about to receive.
    * `:show_token` — displaying the real plaintext token with a copy
      gate (with UnsavedTokenGuard JS hook).
  """
  use AvelineWeb, :live_view

  alias Aveline.Accounts
  alias Aveline.Slug
  alias Aveline.Tokens

  @impl true
  def mount(_params, session, socket) do
    # Resolve through LiveSession so a stale cookie (user_id pointing at
    # a deleted account) drops back to the signup form instead of looping.
    case AvelineWeb.LiveSession.current_user(session) do
      nil ->
        do_mount(socket)

      %{id: user_id} ->
        # Already signed in — bounce them into a workspace (or to the
        # new-workspace flow if they don't have one).
        target =
          case Aveline.Workspaces.list_for_user(user_id) do
            [%{slug: slug} | _] -> ~p"/w/#{slug}"
            [] -> ~p"/new-workspace"
          end

        {:ok, push_navigate(socket, to: target)}
    end
  end

  defp do_mount(socket) do
    {:ok,
     assign(socket,
       page_title: "Aveline · Sign up",
       state: :form,
       username: "",
       workspace_name: "",
       error: nil,
       result: nil,
       # Pre-generate the real token on mount so the user sees their actual
       # API key in the form. We only persist (hash) it when they submit.
       preview_token: Tokens.generate_plaintext()
     ), layout: false}
  end

  @impl true
  def handle_event("validate", params, socket) do
    # Pure input capture — no validation messages until submit. Any prior
    # error clears once the user starts editing again.
    username = params["username"] |> to_string() |> String.trim() |> String.downcase()
    workspace_name = params["workspace_name"] |> to_string()

    {:noreply,
     assign(socket,
       username: username,
       workspace_name: workspace_name,
       error: nil
     )}
  end

  def handle_event("submit", params, socket) do
    {username, username_err} = check_username(params["username"] || "")
    workspace_name = (params["workspace_name"] || "") |> to_string() |> String.trim()
    copied = params["copied"] == "true"

    workspace_err =
      cond do
        workspace_name == "" -> "Pick a workspace name."
        Slug.derive(workspace_name) in [nil, ""] -> "Workspace name needs at least one letter or digit."
        true -> nil
      end

    copy_err =
      if copied,
        do: nil,
        else: "Copy the API key first. You will not be able to see it again."

    # Priority: username → workspace → copy. Show at most one.
    first_error = username_err || workspace_err || copy_err

    cond do
      first_error != nil ->
        {:noreply,
         assign(socket,
           username: username,
           workspace_name: workspace_name,
           error: first_error
         )}

      true ->
        case Accounts.signup(%{
               "username" => username,
               "workspace_name" => workspace_name,
               "plaintext_token" => socket.assigns.preview_token
             }) do
          {:ok, %{user: user, workspace: ws, token: plaintext}} ->
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
      username == "" ->
        {username, nil}

      String.length(username) < 2 ->
        {username, "Username too short (min 2)."}

      String.length(username) > 60 ->
        {username, "Username too long (max 60)."}

      not Regex.match?(~r/^[a-z0-9][a-z0-9-]*$/, username) ->
        {username, "Lowercase letters, digits, and hyphens only."}

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
  def render(%{state: :form} = assigns) do
    trimmed_username = String.trim(assigns.username || "")

    assigns =
      assign(assigns,
        can_submit: trimmed_username != "" and String.trim(assigns.workspace_name) != ""
      )

    ~H"""
    <div class="auth-shell">
      <AvelineWeb.AuthBg.split />
      <div class="auth-card auth-card-spare">
        <div class="auth-brand auth-brand-hero">
          <span class="nav-brand-mark" style="width:36px;height:36px">A</span>
          <span class="auth-brand-name" style="font-size:26px">aveline</span>
        </div>

        <form
          phx-change="validate"
          phx-submit="submit"
          class="auth-form"
          id="signup-form"
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

          <label class="auth-label" for="ws-name" style="margin-top:16px">Workspace name</label>
          <input
            type="text"
            name="workspace_name"
            id="ws-name"
            value={@workspace_name}
            autocomplete="off"
            placeholder="Aveline AI"
            class="auth-input auth-input-hero"
            phx-debounce="250"
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
            Sign up
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
        setup_prompt: setup_prompt(ws, plaintext)
      )

    ~H"""
    <div class="auth-shell">
      <AvelineWeb.AuthBg.split />
      <div class="auth-card auth-card-wide">
        <div class="auth-brand auth-brand-hero">
          <span class="nav-brand-mark" style="width:36px;height:36px">A</span>
          <span class="auth-brand-name" style="font-size:26px">aveline</span>
        </div>

        <h1 class="auth-title">You're in, {@user.username}</h1>
        <p class="auth-subtitle">
          One step: hand this to your Claude.
        </p>

        <div class="onboarding-step">
          <div class="onboarding-step-body">
            <p class="onboarding-step-desc">
              Paste this prompt into Claude Code — it installs the
              <code>aveline</code> CLI, signs in, and teaches your project to
              use Aveline for knowledge management.
            </p>
            <div class="snippet">
              <pre><code id="claude-snippet">{@setup_prompt}</code></pre>
              <button
                type="button"
                id="claude-snippet-copy"
                class="snippet-copy"
                phx-hook="CopyToken"
                data-target="#claude-snippet"
                title="Copy"
              >
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">
                  <rect x="9" y="9" width="12" height="12" rx="2" />
                  <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
                </svg>
                <span class="token-field-copy-label">Copy</span>
              </button>
            </div>
          </div>
        </div>

        <form action={~p"/login"} method="post" id="continue-form" class="auth-form" style="margin-top:8px">
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <input type="hidden" name="token" value={@plaintext} />
          <button id="continue-btn" type="submit" class="auth-submit">
            Continue to {@workspace.name}
          </button>
        </form>
      </div>
    </div>
    """
  end

  # The one-step onboarding prompt: the user hands this to their Claude,
  # which installs the CLI, signs in, and adds the CLAUDE.md note. The
  # API key rides in the prompt (a one-time paste into the user's own
  # session) — the prompt itself tells Claude to keep it out of files.
  defp setup_prompt(ws, plaintext) do
    """
    Set up Aveline, the wiki our team uses for shared knowledge (built for AI agents like you):

    1. Install the `aveline` CLI from https://github.com/aveline-ai/cli/releases/latest (pick the binary for this machine and put it on PATH).
    2. Run `aveline login --token #{plaintext}` and then `aveline use-workspace #{ws.slug}`. Never write this token into any file.
    3. Verify with `aveline whoami`, then read `aveline get-orientation --follow` to learn how this workspace organizes its knowledge.
    4. Add a short note to this project's CLAUDE.md: we keep shared knowledge in Aveline; interact via the `aveline` CLI (`aveline --help` shows every operation); start sessions with `aveline get-orientation --follow`.
    """
  end
end
