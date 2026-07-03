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
     ),
     layout: false}
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
      username == "" -> {username, nil}
      String.length(username) < 2 -> {username, "Username too short (min 2)."}
      String.length(username) > 60 -> {username, "Username too long (max 60)."}
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
    assigns = assign(assigns, user: user, workspace: ws, plaintext: plaintext)

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
          Two quick things to get the most out of Aveline.
        </p>

        <div class="onboarding-step">
          <div class="onboarding-step-num">1</div>
          <div class="onboarding-step-body">
            <div class="onboarding-step-title">Install the CLI</div>
            <p class="onboarding-step-desc">
              Download the latest binary for your OS, then run <code>aveline login</code>
              with the API key you just saved.
            </p>
            <a
              href="https://github.com/aveline-ai/cli/releases/latest"
              target="_blank"
              rel="noopener"
              class="auth-secondary"
              style="display:inline-flex;align-items:center;gap:6px;padding:0 14px;height:34px;text-decoration:none"
            >
              <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M8 0C3.58 0 0 3.58 0 8a8 8 0 0 0 5.47 7.59c.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8z"/></svg>
              Open releases
            </a>
          </div>
        </div>

        <div class="onboarding-step">
          <div class="onboarding-step-num">2</div>
          <div class="onboarding-step-body">
            <div class="onboarding-step-title">Tell Claude about Aveline</div>
            <p class="onboarding-step-desc">
              Paste this into your project's <code>CLAUDE.md</code> (or
              <code>~/.claude/CLAUDE.md</code> for a global rule). Claude will
              know to read + write from the wiki via the CLI.
            </p>
            <div class="snippet">
              <pre><code id="claude-snippet">Our team uses Aveline as a shared wiki for team knowledge, a Notion replacement designed to be read and written by AI agents. Use the `aveline` CLI to interact with it (`aveline --help` for the full verb set; common verbs: `list-docs`, `get-doc`, `create-doc`, `create-comment`, `apply-ops`).</code></pre>
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
            Continue into {@workspace.name}
          </button>
        </form>
      </div>
    </div>
    """
  end
end
