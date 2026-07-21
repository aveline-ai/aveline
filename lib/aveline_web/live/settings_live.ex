defmodule AvelineWeb.SettingsLive do
  @moduledoc """
  User settings, scoped to a workspace URL so the sidebar follows you in
  from wherever you were. The settings themselves are global (per-user);
  the workspace in the URL is only used to keep the sidebar context.
  """
  use AvelineWeb, :live_view

  alias Aveline.Accounts.User
  alias Aveline.Docs
  alias Aveline.Repo
  alias Aveline.Tokens
  alias Aveline.Workspaces
  alias AvelineWeb.LiveSession

  @impl true
  def mount(%{"slug" => slug}, session, socket) do
    user = LiveSession.current_user(session)

    case LiveSession.fetch_workspace_for_user(slug, user) do
      {:ok, ws} ->
        items = Docs.list_current(ws.id, viewer: user.id)

        {:ok,
         assign(socket,
           page_title: "Aveline · Settings",
           current_user: user,
           workspace: ws,
           sidebar_workspaces: Workspaces.list_for_user(user.id),
           sidebar_views: Aveline.Views.sidebar_sections(ws.id, user.id),
           total_count: length(items),
           topbar_title: "Settings",
           nav_active: :settings,
           display_name: user.display_name || "",
           saved: false,
           error: nil,
           tokens: Tokens.list_active_for_user(user.id),
           new_key: nil,
           key_error: nil
         )}

      :not_found ->
        {:ok, socket |> put_flash(:error, "Workspace not found.") |> push_navigate(to: ~p"/")}

      :forbidden ->
        {:ok, socket |> put_flash(:error, "Forbidden.") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("update", %{"display_name" => raw}, socket) do
    {:noreply, assign(socket, display_name: raw, saved: false, error: nil)}
  end

  def handle_event("save", %{"display_name" => raw}, socket) do
    user = socket.assigns.current_user
    new_name = raw |> to_string() |> String.trim()
    next_name = if new_name == "", do: nil, else: new_name

    changeset = User.changeset(user, %{"display_name" => next_name})

    case Repo.update(changeset) do
      {:ok, updated} ->
        {:noreply,
         assign(socket,
           current_user: updated,
           display_name: next_name || "",
           saved: true,
           error: nil
         )}

      {:error, cs} ->
        {:noreply, assign(socket, error: format_error(cs))}
    end
  end

  def handle_event("create_key", %{"key_name" => raw}, socket) do
    user = socket.assigns.current_user
    name = raw |> to_string() |> String.trim()

    cond do
      name == "" ->
        {:noreply, assign(socket, key_error: "Give the key a name, like \"laptop\" or \"work\".")}

      true ->
        case Tokens.mint(user.id, name) do
          {:ok, token, plaintext} ->
            {:noreply,
             assign(socket,
               tokens: Tokens.list_active_for_user(user.id),
               new_key: %{token: token, plaintext: plaintext},
               key_error: nil
             )}

          {:error, _} ->
            {:noreply, assign(socket, key_error: "Could not create the key. Try again.")}
        end
    end
  end

  def handle_event("revoke_key", %{"token-id" => token_id}, socket) do
    user = socket.assigns.current_user

    case Tokens.revoke_guarded(user.id, token_id) do
      {:ok, _} ->
        # Also clear the one-time reveal if it was for the revoked key.
        new_key =
          case socket.assigns.new_key do
            %{token: %{id: ^token_id}} -> nil
            other -> other
          end

        {:noreply,
         assign(socket,
           tokens: Tokens.list_active_for_user(user.id),
           new_key: new_key,
           key_error: nil
         )}

      {:error, :last_key} ->
        {:noreply, assign(socket, key_error: "That's your only key. Create a new one first, then revoke this one.")}

      {:error, _} ->
        {:noreply, assign(socket, key_error: "Could not revoke that key.")}
    end
  end

  defp format_error(%Ecto.Changeset{errors: errors}) do
    Enum.map_join(errors, "; ", fn {field, {msg, _}} -> "#{field}: #{msg}" end)
  end

  defp key_confirm(token, count) do
    base = "Revoke \"#{token.name}\" (#{Tokens.masked(token)})? Anything still using it stops working immediately."

    if count > 1 do
      base <> " If this browser signed in with it, your session cookie keeps working."
    else
      base
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="content">
      <h1 class="page-title">Settings</h1>
      <p class="page-subtitle">
        Signed in as <span class="mono">{@current_user.username}</span>.
      </p>

      <div class="section-label">Profile</div>

      <form phx-change="update" phx-submit="save" class="auth-form" style="max-width:480px">
        <label class="auth-label" for="display-name">Display name</label>
        <input
          type="text"
          name="display_name"
          id="display-name"
          value={@display_name}
          autocomplete="off"
          placeholder="e.g. Alice from accounting"
          class={"auth-input " <> if @error, do: "auth-input-error", else: ""}
          phx-debounce="250"
        />
        <div class="auth-hint">
          Shown next to your username on items and threads. Leave blank to use just the username.
        </div>
        <%= if @error do %>
          <div class="auth-error">{@error}</div>
        <% end %>
        <%= if @saved do %>
          <div class="auth-hint" style="color:#4ADE80;margin-top:8px">Saved.</div>
        <% end %>

        <button type="submit" class="auth-submit" style="max-width:140px">Save</button>
      </form>

      <div class="section-label" style="margin-top:32px">
        API keys <span class="count">{length(@tokens)}</span>
      </div>

      <%= if @new_key do %>
        <div class="invite-block" style="margin-bottom:14px">
          <p class="auth-hint" style="margin-bottom:10px">
            Your new key <strong>{@new_key.token.name}</strong>. Copy it now: this is the only
            time it's shown. Only a hash is stored.
          </p>
          <div class="invite-url-row">
            <code id="new-key-value" class="invite-url">{@new_key.plaintext}</code>
            <button
              type="button"
              id="copy-new-key-btn"
              class="auth-secondary"
              phx-hook="CopyToken"
              data-target="#new-key-value"
              style="height:36px;padding:0 14px"
            >
              Copy
            </button>
          </div>
        </div>
      <% end %>

      <ul class="card-list">
        <li :for={t <- @tokens} class="card team-row">
          <div class="team-row-left">
            <div>
              <div class="team-row-name">
                {t.name}
                <span class="mono" style="margin-left:8px;font-size:12px;color:var(--text-muted)">{Tokens.masked(t)}</span>
              </div>
              <div class="team-row-sub">
                created <span title={absolute_time(t.inserted_at)}>{relative_time(t.inserted_at)}</span>
                · last used <span :if={t.last_used_at} title={absolute_time(t.last_used_at)}>{relative_time(t.last_used_at)}</span>
                <span :if={is_nil(t.last_used_at)}>never</span>
              </div>
            </div>
          </div>
          <div class="team-row-right">
            <div class="team-row-actions">
              <button
                :if={length(@tokens) > 1}
                phx-click="revoke_key"
                phx-value-token-id={t.id}
                data-confirm={key_confirm(t, length(@tokens))}
                class="thread-action-btn"
              >
                revoke
              </button>
              <span
                :if={length(@tokens) == 1}
                class="auth-hint"
                style="font-size:11px"
                title="Your only key. Create a new one first, then revoke this one."
              >
                only key
              </span>
            </div>
          </div>
        </li>
      </ul>

      <form phx-submit="create_key" style="display:flex;gap:8px;margin-top:12px;max-width:480px">
        <input
          type="text"
          name="key_name"
          autocomplete="off"
          placeholder='Name the new key, e.g. "laptop"'
          class="auth-input"
          style="flex:1"
        />
        <button type="submit" class="auth-secondary" style="height:44px;padding:0 16px;white-space:nowrap">
          New key
        </button>
      </form>
      <%= if @key_error do %>
        <div class="auth-error" style="margin-top:8px">{@key_error}</div>
      <% end %>
      <div class="auth-hint" style="margin-top:8px">
        Keys are shown once at creation and stored hashed. Sign in on another browser
        with <span class="mono">/login/&lt;key&gt;</span>, or point the CLI at one via
        <span class="mono">aveline login</span>.
      </div>
    </div>
    """
  end
end
