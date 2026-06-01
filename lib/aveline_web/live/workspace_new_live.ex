defmodule AvelineWeb.WorkspaceNewLive do
  @moduledoc """
  Create-a-workspace form. Pick a name; slug is derived. Creator is
  added as the first member. Redirects to the new workspace on success.
  """
  use AvelineWeb, :live_view

  alias Aveline.Slug
  alias Aveline.Workspaces
  alias AvelineWeb.LiveSession

  @impl true
  def mount(_params, session, socket) do
    case LiveSession.current_user(session) do
      nil ->
        {:ok, socket |> put_flash(:error, "Sign in first.") |> push_navigate(to: ~p"/login")}

      user ->
        {:ok,
         assign(socket,
           page_title: "Aveline · New workspace",
           current_user: user,
           name: "",
           error: nil
         )}
    end
  end

  @impl true
  def handle_event("validate", %{"name" => raw}, socket) do
    {:noreply, assign(socket, name: raw, error: nil)}
  end

  def handle_event("submit", %{"name" => raw}, socket) do
    name = String.trim(raw || "")
    user = socket.assigns.current_user

    cond do
      name == "" ->
        {:noreply, assign(socket, error: "Pick a name.")}

      String.length(name) > 80 ->
        {:noreply, assign(socket, error: "Too long (max 80 characters).")}

      true ->
        case Slug.derive(name) do
          nil ->
            {:noreply, assign(socket, error: "Name needs at least one letter or digit.")}

          slug ->
            case Workspaces.create_workspace(%{
                   "name" => name,
                   "slug" => slug,
                   "created_by_id" => user.id
                 }) do
              {:ok, ws} ->
                {:ok, _} = Workspaces.ensure_member(ws.id, user.id)

                {:noreply,
                 socket
                 |> put_flash(:info, "Workspace created.")
                 |> push_navigate(to: ~p"/w/#{ws.slug}")}

              {:error, %Ecto.Changeset{errors: errors}} ->
                msg =
                  case errors[:slug] do
                    {"has already been taken", _} ->
                      "That name is already in use. Pick a different one."

                    _ ->
                      "Couldn't create — check the name."
                  end

                {:noreply, assign(socket, error: msg)}

              {:error, _} ->
                {:noreply, assign(socket, error: "Couldn't create the workspace.")}
            end
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="auth-shell">
      <div class="auth-card">
        <div class="auth-brand">
          <span class="nav-brand-mark">A</span>
          <span class="auth-brand-name">aveline</span>
        </div>
        <h1 class="auth-title">New workspace</h1>
        <p class="auth-subtitle">
          Pick a name for your team. We'll generate a slug from it.
        </p>

        <form phx-change="validate" phx-submit="submit" class="auth-form">
          <label class="auth-label" for="ws-name">Workspace name</label>
          <input
            type="text"
            name="name"
            id="ws-name"
            value={@name}
            autocomplete="off"
            placeholder="e.g. Stable Engineering"
            class={"auth-input " <> if @error, do: "auth-input-error", else: ""}
            phx-debounce="250"
            autofocus
          />
          <div class="auth-hint">
            <%= if String.trim(@name) != "" do %>
              Slug: <code>{Slug.derive(@name) || "—"}</code>
            <% else %>
              Used in the URL (<code>/w/&lt;slug&gt;</code>).
            <% end %>
          </div>
          <%= if @error do %>
            <div class="auth-error">{@error}</div>
          <% end %>

          <button type="submit" class="auth-submit" disabled={String.trim(@name) == ""}>
            Create workspace
          </button>
        </form>
      </div>
    </div>
    """
  end
end
