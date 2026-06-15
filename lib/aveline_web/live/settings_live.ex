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
  alias Aveline.Workspaces
  alias AvelineWeb.LiveSession

  @impl true
  def mount(%{"slug" => slug}, session, socket) do
    user = LiveSession.current_user(session)

    case LiveSession.fetch_workspace_for_user(slug, user) do
      {:ok, ws} ->
        items = Docs.list_current(ws.id)

        {:ok,
         assign(socket,
           page_title: "Aveline · Settings",
           current_user: user,
           workspace: ws,
           sidebar_workspaces: Workspaces.list_for_user(user.id),
           total_count: length(items),
           pinned_count: Enum.count(items, & &1.pinned),
           topbar_title: "Settings",
           nav_active: :settings,
           display_name: user.display_name || "",
           saved: false,
           error: nil
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

  defp format_error(%Ecto.Changeset{errors: errors}) do
    Enum.map_join(errors, "; ", fn {field, {msg, _}} -> "#{field}: #{msg}" end)
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

      <div class="section-label" style="margin-top:32px">Account</div>
      <div class="banner">
        Your username (<span class="mono">{@current_user.username}</span>) and personal
        workspace slug are fixed for now. We'll add account rename + token rotation
        in v0.1.
      </div>
    </div>
    """
  end
end
