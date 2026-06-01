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

  @impl true
  def mount(_params, session, socket) do
    case session["user_id"] do
      nil ->
        do_mount(socket)

      user_id ->
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
       fake_token: mint_fake_token()
     )}
  end

  # A static dotted placeholder that looks like an API key without
  # being mistaken for one. Same shape as `avl_<32 chars>`.
  defp mint_fake_token, do: "avl_" <> String.duplicate("•", 32)

  @impl true
  def handle_event("validate", params, socket) do
    {username, username_err} = check_username(params["username"] || "")
    workspace_name = (params["workspace_name"] || "") |> to_string()

    error =
      cond do
        username_err != nil -> username_err
        true -> nil
      end

    {:noreply,
     assign(socket,
       username: username,
       workspace_name: workspace_name,
       error: error
     )}
  end

  def handle_event("submit", params, socket) do
    {username, username_err} = check_username(params["username"] || "")
    workspace_name = (params["workspace_name"] || "") |> to_string() |> String.trim()

    cond do
      username_err != nil ->
        {:noreply, assign(socket, username: username, error: username_err)}

      workspace_name == "" ->
        {:noreply,
         assign(socket,
           username: username,
           workspace_name: workspace_name,
           error: "Pick a workspace name."
         )}

      Slug.derive(workspace_name) in [nil, ""] ->
        {:noreply,
         assign(socket,
           workspace_name: workspace_name,
           error: "Workspace name needs at least one letter or digit."
         )}

      true ->
        case Accounts.signup(%{
               "username" => username,
               "workspace_name" => workspace_name
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
    workspace_slug = if assigns.workspace_name != "", do: Slug.derive(assigns.workspace_name), else: nil

    assigns =
      assign(assigns,
        username_slug: if(trimmed_username != "", do: String.downcase(trimmed_username), else: nil),
        workspace_slug: workspace_slug,
        can_submit: trimmed_username != "" and String.trim(assigns.workspace_name) != "" and assigns.error == nil
      )

    ~H"""
    <div class="auth-shell">
      <div class="auth-card auth-card-spare">
        <div class="auth-brand auth-brand-hero">
          <span class="nav-brand-mark" style="width:36px;height:36px">A</span>
          <span class="auth-brand-name" style="font-size:26px">aveline</span>
        </div>

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
            placeholder="arie"
            class={"auth-input auth-input-hero " <> if @error, do: "auth-input-error", else: ""}
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
          <div class="auth-hint" style="min-height:18px">
            <%= if @error do %>
              <span class="auth-error" style="margin:0">{@error}</span>
            <% else %>
              aveline.ai/w/<code>{@workspace_slug || ""}</code>
            <% end %>
          </div>

          <label class="auth-label" style="margin-top:18px">Your API key</label>
          <div class="token-preview">{@fake_token}</div>
          <div class="auth-hint">
            Generated when you sign up — save it like a password. (CLI uses this too.)
          </div>

          <button type="submit" class="auth-submit" disabled={not @can_submit}>
            Sign up
          </button>
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
    <div class="auth-shell" id="show-token-shell" phx-hook="UnsavedTokenGuard">
      <div class="auth-card auth-card-wide">
        <div class="auth-brand auth-brand-hero">
          <span class="nav-brand-mark" style="width:36px;height:36px">A</span>
          <span class="auth-brand-name" style="font-size:26px">aveline</span>
        </div>
        <h1 class="auth-title">Save your API key</h1>
        <p class="auth-subtitle">
          Hi <strong>{@user.username}</strong> — this is the only time you'll see
          this. We store the hash, not the plaintext, so there's no recovery.
          Stash it in 1Password now.
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

        <form action={~p"/login"} method="post" id="continue-form" style="margin-top:16px">
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <input type="hidden" name="token" value={@plaintext} />
          <button id="continue-btn" type="submit" class="auth-submit" disabled>
            I saved it — continue
          </button>
        </form>

        <div class="auth-divider"></div>

        <div class="auth-cli-hint">
          <div class="auth-cli-hint-title">Use this in the CLI</div>
          <pre class="auth-cli-block">{"aveline login\n# paste the token when prompted"}</pre>
        </div>
      </div>
    </div>
    """
  end
end
