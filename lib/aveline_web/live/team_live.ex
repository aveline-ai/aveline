defmodule AvelineWeb.TeamLive do
  @moduledoc false
  use AvelineWeb, :live_view

  alias Aveline.Docs
  alias Aveline.Stats
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

        items = Docs.list_current(ws.id, viewer: user.id)
        invite = Workspaces.get_active_invite_for_workspace(ws.id)

        {:ok,
         socket
         |> assign(
           page_title: "Aveline · Team · #{ws.name}",
           current_user: user,
           workspace: ws,
           sidebar_workspaces: Workspaces.list_for_user(user.id),
           sidebar_views: Aveline.Views.sidebar_sections(ws.id, user.id),
           total_count: length(items),
           topbar_title: "Team",
           nav_active: :team,
           invite: invite
         )
         |> assign_roster(ws.id)}

      :not_found ->
        {:ok, socket |> put_flash(:error, "Workspace not found.") |> push_navigate(to: ~p"/")}

      :forbidden ->
        {:ok, socket |> put_flash(:error, "Forbidden.") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("create_invite", _, socket) do
    %{workspace: ws, current_user: user} = socket.assigns

    case Workspaces.ensure_invite(ws.id, user.id) do
      {:ok, invite} -> {:noreply, assign(socket, :invite, invite)}
      _ -> {:noreply, put_flash(socket, :error, "Could not create invite link.")}
    end
  end

  def handle_event("rotate_invite", _, socket) do
    %{workspace: ws, current_user: user} = socket.assigns

    case Workspaces.rotate_invite(ws.id, user.id) do
      {:ok, invite} ->
        {:noreply,
         socket
         |> assign(:invite, invite)
         |> put_flash(:info, "Rotated. Old link no longer works.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not rotate.")}
    end
  end

  def handle_event("revoke_invite", _, socket) do
    %{invite: invite, current_user: user} = socket.assigns

    case invite && Workspaces.revoke_invite(invite, user.id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:invite, nil)
         |> put_flash(:info, "Invite link revoked.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("remove_member", %{"user-id" => uid}, socket) do
    ws = socket.assigns.workspace

    if uid == socket.assigns.current_user.id do
      {:noreply, put_flash(socket, :error, "You can't remove yourself.")}
    else
      case Workspaces.remove_member(ws.id, uid, socket.assigns.current_user.id) do
        {:ok, _} ->
          {:noreply, assign_roster(socket, ws.id)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not remove member.")}
      end
    end
  end

  @impl true
  def handle_info({event, _payload}, socket) when event in [:member_added, :member_removed] do
    {:noreply, assign_roster(socket, socket.assigns.workspace.id)}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  # Members plus their usage stats (folded in from the old Usage page) —
  # recomputed together so rows and stats never drift apart.
  defp assign_roster(socket, ws_id) do
    members = Workspaces.list_members(ws_id)
    stats_by_user = Map.new(Stats.contributors(ws_id), &{&1.user.id, &1})

    assign(socket,
      members: members,
      member_count: length(members),
      stats_by_user: stats_by_user,
      totals: Stats.workspace_totals(ws_id)
    )
  end

  defp invite_url(code) do
    base = AvelineWeb.Endpoint.url()
    base <> "/invite/" <> code
  rescue
    _ -> "/invite/" <> code
  end

  @impl true
  def render(assigns) do
    invite_full = if assigns[:invite], do: invite_url(assigns.invite.code), else: nil
    assigns = assign(assigns, invite_full: invite_full)

    ~H"""
    <div class="content">
      <h1 class="page-title">Team</h1>
      <p class="page-subtitle">
        Everyone who can read + comment in <span class="mono">{@workspace.slug}</span>.
      </p>

      <p class="team-totals">
        Together: <.stat value={@totals.active_docs} label="doc" />
        · <.stat value={@totals.reads} label="view" />
        · <.stat value={@totals.total_edits} label="edit" />
        · <.stat value={@totals.kudos} label="kudos" />
        · <.stat value={@totals.comments} label="comment" />
      </p>

      <div class="section-label">
        Members <span class="count">{@member_count}</span>
      </div>

      <ul class="card-list">
        <li :for={m <- @members} class="card team-row">
          <div class="team-row-left">
            <div
              class="team-avatar"
              style={"background: hsl(#{avatar_hue(m.user.username)}, 55%, 28%); color: hsl(#{avatar_hue(m.user.username)}, 70%, 80%)"}
            >
              {initial(m.user.username)}
            </div>
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
            <.member_stats stats={Map.get(@stats_by_user, m.user.id)} />
            <div class="team-row-actions">
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
          </div>
        </li>
      </ul>

      <div class="section-label" style="margin-top:32px">Invite link</div>

      <%= if @invite do %>
        <div class="invite-block">
          <p class="auth-hint" style="margin-bottom:10px">
            Anyone with this link can join <strong>{@workspace.name}</strong>. New users get a signup screen; existing users join with one click.
          </p>
          <div class="invite-url-row">
            <code id="invite-url-value" class="invite-url">{@invite_full}</code>
            <button
              type="button"
              id="copy-invite-btn"
              class="auth-secondary"
              phx-hook="CopyToken"
              data-target="#invite-url-value"
              style="height:36px;padding:0 14px"
            >
              Copy
            </button>
          </div>
          <div style="display:flex;gap:8px;margin-top:12px">
            <button
              phx-click="rotate_invite"
              data-confirm="Rotate the invite link? The current link will stop working."
              class="auth-secondary"
              style="height:32px;padding:0 12px;font-size:12px"
            >
              Rotate
            </button>
            <button
              phx-click="revoke_invite"
              data-confirm="Revoke the invite link entirely?"
              class="auth-secondary"
              style="height:32px;padding:0 12px;font-size:12px;color:var(--danger);border-color:rgba(229,72,77,0.3)"
            >
              Revoke
            </button>
          </div>
        </div>
      <% else %>
        <div class="banner">
          No active invite link.
          <button phx-click="create_invite" class="auth-link" style="background:none;border:none;cursor:pointer;padding:0;margin-left:6px">
            Generate one
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  attr :stats, :map, default: nil

  defp member_stats(%{stats: nil} = assigns), do: ~H""

  # Two clusters so the semantics are unmissable: what they made (docs
  # owned, versions written) vs what it earned (views + kudos received
  # by docs they own).
  defp member_stats(assigns) do
    ~H"""
    <div class="team-row-stats">
      <div class="team-stat-group">
        <div class="team-stat-group-label">Built</div>
        <div class="team-stat-group-values">
          <.stat value={@stats.docs_owned} label="doc" />
          · <.stat value={@stats.edits_made} label="edit" />
        </div>
      </div>
      <div class="team-stat-group">
        <div class="team-stat-group-label">Impact</div>
        <div class="team-stat-group-values">
          <.stat value={@stats.reads_earned} label="view" />
          · <.stat value={@stats.kudos_earned} label="kudos" />
        </div>
      </div>
    </div>
    """
  end

  attr :value, :integer, required: true
  attr :label, :string, required: true

  # "kudos" is its own plural; everything else takes a plain s.
  defp stat(assigns) do
    assigns = assign(assigns, :word, pluralize_label(assigns.label, assigns.value))

    ~H"""
    <span class="team-stat"><strong>{format_number(@value)}</strong> {@word}</span>
    """
  end

  defp pluralize_label(label, 1), do: label
  defp pluralize_label("kudos", _), do: "kudos"
  defp pluralize_label(label, _), do: label <> "s"
end
