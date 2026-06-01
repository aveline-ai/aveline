defmodule AvelineWeb.SignupLive do
  @moduledoc """
  Token-only signup. Pick a username, get an API key, save the key.

  Two states:
    * `:form` — collecting username (live validation)
    * `:show_token` — displaying the plaintext token with a copy gate

  The plaintext token lives only in socket assigns during `:show_token`.
  Refreshing the page wipes it forever. The JS hook adds a `beforeunload`
  guard that warns until the user clicks Copy.
  """
  use AvelineWeb, :live_view

  alias Aveline.Accounts

  @impl true
  def mount(_params, session, socket) do
    # If already signed in, send them home.
    if session["user_id"], do: {:ok, push_navigate(socket, to: ~p"/")}, else: do_mount(socket)
  end

  defp do_mount(socket) do
    {:ok,
     assign(socket,
       page_title: "Aveline · Sign up",
       state: :form,
       username: "",
       error: nil,
       result: nil
     )}
  end

  @impl true
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
        case Accounts.signup(%{"username" => username}) do
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
        {username, "Too short (minimum 2 characters)."}

      String.length(username) > 60 ->
        {username, "Too long (max 60 characters)."}

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
  def render(%{state: :form} = assigns) do
    trimmed = String.trim(assigns.username || "")
    slug_preview = if trimmed != "", do: String.downcase(trimmed), else: nil
    assigns = assign(assigns, slug_preview: slug_preview)

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
          <div class="auth-hint" style="min-height:18px">
            <%= if @error do %>
              <span class="auth-error" style="margin:0">{@error}</span>
            <% else %>
              aveline.ai/w/<code>{@slug_preview || ""}</code>
            <% end %>
          </div>

          <button
            type="submit"
            class="auth-submit"
            disabled={@username == "" or @error != nil}
          >
            Create account
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
        <div class="auth-brand">
          <span class="nav-brand-mark">A</span>
          <span class="auth-brand-name">aveline</span>
        </div>
        <h1 class="auth-title">Save your API key</h1>
        <p class="auth-subtitle">
          Hi <strong>{@user.username}</strong> — this is the only time you'll see this token.
          We store the hash, not the plaintext, so there's no way to recover it.
          Stash it in 1Password or your password manager now.
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

          <form action={~p"/login"} method="post" id="continue-form">
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <input type="hidden" name="token" value={@plaintext} />
            <button id="continue-btn" type="submit" class="auth-submit" disabled>
              I saved it — continue
            </button>
          </form>
        </div>

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
