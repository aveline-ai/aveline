defmodule AvelineWeb.SettingsLive do
  @moduledoc """
  User settings. v0 only allows editing the display name — username is
  used in personal-workspace slugs so we leave it alone until we have a
  rename-with-slug-redirect story.
  """
  use AvelineWeb, :live_view

  alias Aveline.Accounts.User
  alias Aveline.Items
  alias Aveline.Repo
  alias Aveline.Views
  alias Aveline.Workspaces
  alias AvelineWeb.LiveSession

  @impl true
  def mount(_params, session, socket) do
    case LiveSession.current_user(session) do
      nil ->
        {:ok, socket |> put_flash(:error, "Sign in first.") |> push_navigate(to: ~p"/login")}

      user ->
        # Reuse the sidebar by picking the user's first workspace as context.
        # Settings itself is global — `nav_active: :settings` highlights it.
        workspaces = Workspaces.list_for_user(user.id)
        primary = List.first(workspaces)

        layout_assigns =
          case primary do
            nil ->
              %{}

            ws ->
              items = Items.list_current(ws.id)

              %{
                workspace: ws,
                personal_views: Views.list_personal_views(ws.id, user.id),
                team_views: Views.list_team_views(ws.id),
                total_count: length(items),
                pinned_count: Enum.count(items, & &1.pinned),
                topbar_title: "Settings",
                nav_active: :settings
              }
          end

        {:ok,
         assign(socket,
           Map.merge(
             %{
               page_title: "Aveline · Settings",
               current_user: user,
               display_name: user.display_name || "",
               saved: false,
               error: nil
             },
             layout_assigns
           ))}
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

    changeset =
      User.changeset(user, %{"display_name" => next_name})

    case Repo.update(changeset) do
      {:ok, updated} ->
        {:noreply,
         assign(socket, current_user: updated, display_name: next_name || "", saved: true, error: nil)}

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
    <div class="container-narrow">
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
