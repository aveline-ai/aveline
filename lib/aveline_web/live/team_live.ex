defmodule AvelineWeb.TeamLive do
  @moduledoc false
  use AvelineWeb, :live_view

  alias Aveline.Items
  alias Aveline.Views
  alias Aveline.Workspaces
  alias AvelineWeb.LiveSession

  @impl true
  def mount(%{"slug" => slug}, session, socket) do
    user = LiveSession.current_user(session)

    case LiveSession.fetch_workspace_for_user(slug, user) do
      {:ok, ws} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Aveline.PubSub, Workspaces.members_topic(ws.id))
        end

        members = Workspaces.list_members(ws.id)
        items = Items.list_current(ws.id)

        {:ok,
         assign(socket,
           page_title: "Aveline · Team · #{ws.name}",
           current_user: user,
           workspace: ws,
           personal_views: Views.list_personal_views(ws.id, user.id),
           team_views: Views.list_team_views(ws.id),
           total_count: length(items),
           pinned_count: Enum.count(items, & &1.pinned),
           topbar_title: "Team",
           nav_active: :team,
           members: members,
           member_count: length(members),
           invite_username: "",
           invite_error: nil,
           invite_flash: nil
         )}

      :not_found ->
        {:ok, socket |> put_flash(:error, "Workspace not found.") |> push_navigate(to: ~p"/")}

      :forbidden ->
        {:ok, socket |> put_flash(:error, "Forbidden.") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("update_invite", %{"username" => v}, socket) do
    {:noreply, assign(socket, invite_username: v, invite_error: nil)}
  end

  def handle_event("invite", %{"username" => raw}, socket) do
    username = raw |> to_string() |> String.trim() |> String.downcase()
    ws = socket.assigns.workspace

    cond do
      username == "" ->
        {:noreply, assign(socket, invite_error: "Enter a username.")}

      true ->
        case Workspaces.add_member_by_username(ws.id, username) do
          {:ok, _, user} ->
            members = Workspaces.list_members(ws.id)

            {:noreply,
             assign(socket,
               members: members,
               member_count: length(members),
               invite_username: "",
               invite_error: nil,
               invite_flash: "Added #{user.username}."
             )}

          {:error, :user_not_found} ->
            {:noreply,
             assign(socket,
               invite_error:
                 "No user with that username. They need to sign up first at /signup."
             )}

          {:error, _} ->
            {:noreply, assign(socket, invite_error: "Could not add member.")}
        end
    end
  end

  def handle_event("remove_member", %{"user-id" => uid}, socket) do
    ws = socket.assigns.workspace

    if uid == socket.assigns.current_user.id do
      {:noreply, assign(socket, invite_error: "You can't remove yourself.")}
    else
      case Workspaces.remove_member(ws.id, uid) do
        {:ok, _} ->
          members = Workspaces.list_members(ws.id)
          {:noreply, assign(socket, members: members, member_count: length(members))}

        {:error, _} ->
          {:noreply, assign(socket, invite_error: "Could not remove member.")}
      end
    end
  end

  @impl true
  def handle_info({event, _payload}, socket) when event in [:member_added, :member_removed] do
    members = Workspaces.list_members(socket.assigns.workspace.id)
    {:noreply, assign(socket, members: members, member_count: length(members))}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <h1 class="page-title">Team</h1>
      <p class="page-subtitle">
        Everyone who can read + comment in <span class="mono">{@workspace.slug}</span>.
      </p>

      <%= if @invite_flash do %>
        <div class="banner" style="border-color:rgba(74,222,128,0.30);color:#4ADE80">
          {@invite_flash}
        </div>
      <% end %>

      <div class="section-label">
        Members <span class="count">{@member_count}</span>
      </div>

      <ul class="card-list">
        <li :for={m <- @members} class="card team-row">
          <div class="team-row-left">
            <span
              class="avatar"
              style={"width:32px;height:32px;font-size:13px;background:hsl(#{avatar_hue(m.user.username)},65%,18%);color:hsl(#{avatar_hue(m.user.username)},75%,75%)"}
            >
              {initial(m.user.username)}
            </span>
            <div>
              <div class="team-row-name">
                {m.user.username}
                <%= if m.user.id == @current_user.id do %>
                  <span class="chip" style="margin-left:6px;font-size:10px;height:18px;padding:0 6px">you</span>
                <% end %>
              </div>
              <div class="team-row-sub">
                <%= if m.user.display_name && m.user.display_name != "" do %>
                  {m.user.display_name} ·
                <% end %>
                joined <span title={absolute_time(m.inserted_at)}>{relative_time(m.inserted_at)}</span>
              </div>
            </div>
          </div>
          <div class="team-row-right">
            <%= if m.user.id != @current_user.id do %>
              <button
                phx-click="remove_member"
                phx-value-user-id={m.user.id}
                data-confirm={"Remove #{m.user.username} from this workspace?"}
                class="thread-action-btn"
              >
                remove
              </button>
            <% end %>
          </div>
        </li>
      </ul>

      <div class="section-label" style="margin-top:32px">Invite</div>

      <form phx-submit="invite" phx-change="update_invite" class="auth-form" style="max-width:420px">
        <label class="auth-label" for="invite-username">Username</label>
        <input
          type="text"
          name="username"
          id="invite-username"
          value={@invite_username}
          autocomplete="off"
          autocapitalize="none"
          autocorrect="off"
          spellcheck="false"
          placeholder="e.g. trevor"
          class={"auth-input " <> if @invite_error, do: "auth-input-error", else: ""}
          phx-debounce="200"
        />
        <div class="auth-hint">
          Add an existing user by their username. They'll see this workspace immediately.
        </div>
        <%= if @invite_error do %>
          <div class="auth-error">{@invite_error}</div>
        <% end %>

        <button type="submit" class="auth-submit" style="max-width:140px" disabled={@invite_username == ""}>
          Add to workspace
        </button>
      </form>
    </div>
    """
  end
end
