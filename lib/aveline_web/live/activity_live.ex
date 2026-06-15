defmodule AvelineWeb.ActivityLive do
  @moduledoc """
  Workspace audit timeline. Renders the unified `events` feed with one
  compact row per action: who, what, when, link to the target if any.

  Everything significant flows through `Aveline.Events`, so this LV is
  intentionally dumb — it just paginates and presents.
  """
  use AvelineWeb, :live_view

  alias Aveline.Events
  alias Aveline.Workspaces
  alias AvelineWeb.LiveSession

  @page_size Aveline.Pagination.default_page_size()

  @impl true
  def mount(%{"slug" => slug}, session, socket) do
    user = LiveSession.current_user(session)

    case LiveSession.fetch_workspace_for_user(slug, user) do
      {:ok, ws} ->
        {events, has_more?} = load_page(ws.id, nil)

        {:ok,
         assign(socket,
           page_title: "Aveline · Activity · #{ws.name}",
           current_user: user,
           workspace: ws,
           sidebar_workspaces: Workspaces.list_for_user(user.id),
           topbar_title: "Activity",
           nav_active: :activity,
           events: events,
           has_more?: has_more?
         )}

      :not_found ->
        {:ok, socket |> put_flash(:error, "Workspace not found.") |> push_navigate(to: ~p"/")}

      :forbidden ->
        {:ok, socket |> put_flash(:error, "Forbidden.") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true

  def handle_event("load_more", _, socket) do
    %{workspace: ws, events: existing} = socket.assigns
    cursor = List.last(existing) && List.last(existing).inserted_at

    {next, has_more?} = load_page(ws.id, cursor)

    {:noreply, assign(socket, events: existing ++ next, has_more?: has_more?)}
  end

  # Fetch one extra row so we can flag whether more pages exist without a
  # separate COUNT(*).
  defp load_page(workspace_id, cursor) do
    raw = Events.list_for_workspace(workspace_id, limit: @page_size + 1, before: cursor)

    if length(raw) > @page_size do
      {Enum.take(raw, @page_size), true}
    else
      {raw, false}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="content">
      <h1 class="page-title">Activity</h1>
      <p class="page-subtitle">
        Everything that's happened in <span class="mono">{@workspace.slug}</span> — most recent first.
      </p>

      <%= if @events == [] do %>
        <div class="empty">Nothing yet. Actions show up here as people (and agents) work.</div>
      <% else %>
        <ol class="event-list">
          <li :for={e <- @events} class="event-row">
            <span class="event-actor">
              <AvelineWeb.Icons.actor type={e.actor_type} class="actor-icon" title={e.actor_type} />
              <span class="event-actor-name">{actor_name(e)}</span>
              <span :if={e.actor_type == "agent"} class="event-via">via Claude</span>
            </span>
            <span class="event-verb">{verb(e.action)}</span>
            <.target_link event={e} workspace={@workspace} />
            <span :if={detail = detail(e)} class="event-detail">— {detail}</span>
            <span class="card-meta-dot">·</span>
            <span class="event-time" title={absolute_time(e.inserted_at)}>
              {relative_time(e.inserted_at)}
            </span>
          </li>
        </ol>
        <%= if @has_more? do %>
          <div class="load-more-wrap">
            <button type="button" phx-click="load_more" class="load-more-btn">
              Load older
            </button>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  # ===== Display helpers =====

  defp actor_name(%{actor_user: %{username: name}}) when is_binary(name), do: name
  defp actor_name(_), do: "?"

  # Verb phrasing per action — kept terse since the row will always have
  # actor + target. The renderer should read like a sentence in context.
  defp verb("doc_created"), do: "created"
  defp verb("doc_edited"), do: "edited"
  defp verb("doc_deleted"), do: "deleted"
  defp verb("doc_restored"), do: "restored"
  defp verb("doc_pinned"), do: "pinned"
  defp verb("doc_unpinned"), do: "unpinned"
  defp verb("doc_viewed"), do: "read"
  defp verb("comment_created"), do: "commented on"
  defp verb("comment_resolved"), do: "resolved a comment on"
  defp verb("comment_unresolved"), do: "reopened a comment on"
  defp verb("comment_deleted"), do: "deleted a comment on"
  defp verb("kudos_given"), do: "gave kudos to"
  defp verb("kudos_revoked"), do: "took back kudos from"
  defp verb("member_joined"), do: "joined as"
  defp verb("member_removed"), do: "removed"
  defp verb("tag_renamed"), do: "renamed tag"
  defp verb("tag_merged"), do: "merged tag into"
  defp verb("tag_deleted"), do: "deleted tag"
  defp verb(other), do: String.replace(other, "_", " ")

  # Optional one-liner appended after the link, when the action has
  # useful extra context (intent text, tags, etc.).
  defp detail(%{action: "doc_created", data: %{"tags" => [_ | _] = tags}}),
    do: "tagged " <> Enum.map_join(tags, " · ", &"##{&1}")

  defp detail(%{action: action, data: %{"intent" => intent}})
       when action in ["doc_created", "doc_edited"] and intent != "",
       do: intent

  defp detail(_), do: nil

  # Link to the target when we know how. Falls back to plain text label.
  attr :event, :map, required: true
  attr :workspace, :map, required: true

  defp target_link(%{event: %{target_kind: "doc", target_slug: s}} = assigns) when is_binary(s) do
    ~H"""
    <.link navigate={~p"/w/#{@workspace.slug}/d/#{@event.target_slug}"} class="event-target">
      {@event.target_label || @event.target_slug}
    </.link>
    """
  end

  defp target_link(%{event: %{target_kind: "comment", target_slug: s}} = assigns) when is_binary(s) do
    ~H"""
    <.link navigate={~p"/w/#{@workspace.slug}/d/#{@event.target_slug}"} class="event-target">
      {@event.target_label || @event.target_slug}
    </.link>
    """
  end

  defp target_link(%{event: %{target_label: label}} = assigns) when is_binary(label) do
    ~H"""
    <span class="event-target">{@event.target_label}</span>
    """
  end

  defp target_link(assigns), do: ~H""
end
