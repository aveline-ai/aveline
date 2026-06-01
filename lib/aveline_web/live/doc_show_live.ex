defmodule AvelineWeb.DocShowLive do
  @moduledoc false
  use AvelineWeb, :live_view

  alias Aveline.Broadcasts
  alias Aveline.Docs
  alias Aveline.Comments
  alias Aveline.Views
  alias AvelineWeb.LiveSession

  @impl true
  def mount(%{"slug" => slug, "doc_slug" => doc_slug}, session, socket) do
    user = LiveSession.current_user(session)

    case LiveSession.fetch_workspace_for_user(slug, user) do
      {:ok, ws} ->
        case Docs.get_current_by_slug(ws.id, doc_slug) do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, "Item not found.")
             |> push_navigate(to: ~p"/w/#{ws.slug}")}

          item ->
            if connected?(socket) do
              Broadcasts.subscribe(Broadcasts.doc_comments_topic(item.base_doc_id))
              Broadcasts.subscribe(Broadcasts.doc_topic(item.base_doc_id))
            end

            related = Docs.related_docs(item, 5)
            all_items = Docs.list_current(ws.id)
            messages = Comments.list_for_base_doc(item.base_doc_id)
            versions = Docs.list_versions(item.base_doc_id)

            {:ok,
             assign(socket,
               page_title: "Aveline · #{item.title}",
               current_user: user,
               workspace: ws,
               personal_views: Views.list_personal_views(ws.id, user.id),
               team_views: Views.list_team_views(ws.id),
               total_count: length(all_items),
               pinned_count: Enum.count(all_items, & &1.pinned),
               topbar_title: item.title,
               item: item,
               related: related,
               messages: messages,
               versions: versions,
               show_history: false
             )}
        end

      :not_found ->
        {:ok, socket |> put_flash(:error, "Workspace not found.") |> push_navigate(to: ~p"/")}

      :forbidden ->
        {:ok, socket |> put_flash(:error, "Forbidden.") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("post_reply", %{"body" => raw_body}, socket) do
    %{current_user: user, item: item} = socket.assigns
    body = String.trim(raw_body || "")

    cond do
      user == nil ->
        {:noreply, put_flash(socket, :error, "Sign in to post.")}

      body == "" ->
        {:noreply, socket}

      true ->
        case Comments.create_comment(%{
               "doc_id" => item.id,
               "body" => body,
               "actor_user_id" => user.id,
               "actor_type" => "human"
             }) do
          {:ok, _msg} ->
            {:noreply, push_event(socket, "reset-form", %{id: "reply-form"})}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not post reply.")}
        end
    end
  end

  def handle_event("delete_message", %{"id" => id}, socket) do
    %{current_user: user} = socket.assigns

    with %_{} = msg <- Comments.get_comment(id),
         {:ok, _} <- Comments.soft_delete_comment(msg, user && user.id) do
      {:noreply, socket}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not delete.")}
    end
  end

  def handle_event("toggle_history", _, socket) do
    {:noreply, assign(socket, :show_history, not socket.assigns.show_history)}
  end

  @impl true
  def handle_info({event, msg}, socket)
      when event in [:comment_created, :comment_updated, :comment_deleted] do
    msgs =
      case event do
        :comment_created -> socket.assigns.messages ++ [msg]
        :comment_updated -> Enum.map(socket.assigns.messages, fn m -> if m.id == msg.id, do: msg, else: m end)
        :comment_deleted -> Enum.reject(socket.assigns.messages, fn m -> m.id == msg.id end)
      end

    {:noreply, assign(socket, :messages, msgs)}
  end

  def handle_info({:doc_updated, item}, socket) do
    if item.base_doc_id == socket.assigns.item.base_doc_id do
      versions = Docs.list_versions(item.base_doc_id)
      {:noreply, assign(socket, item: item, topbar_title: item.title, versions: versions)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  defp actor_icon("human"), do: "👤"
  defp actor_icon("agent"), do: "🤖"
  defp actor_icon(_), do: ""

  defp message_actor(%{actor_user: %Ecto.Association.NotLoaded{}}), do: nil
  defp message_actor(%{actor_user: a}), do: a
  defp message_actor(_), do: nil

  defp owner(%{owner: %Ecto.Association.NotLoaded{}}), do: nil
  defp owner(%{owner: o}), do: o
  defp owner(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <div class="item-layout">
      <div class="item-article">
        <%= if @item.deleted_at do %>
          <div class="banner banner-warning">
            This doc is deleted. URL preserved for archive.
          </div>
        <% end %>

        <header class="article-header">
          <h1 class="article-title">
            <%= if @item.pinned do %>
              <span class="pin" title="Pinned" style="margin-right:10px;display:inline-flex;vertical-align:middle">
                <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M12 2l2.39 7.36H22l-6.18 4.49L18.21 22 12 17.27 5.79 22l2.39-8.15L2 9.36h7.61z" />
                </svg>
              </span>
            <% end %>
            {@item.title}
          </h1>

          <%= if @item.summary && @item.summary != "" do %>
            <p class="article-summary">{@item.summary}</p>
          <% end %>

          <div class="article-meta">
            <%= if owner(@item) do %>
              <span class="article-meta-item">
                <span
                  class="avatar-sm"
                  style={"background:hsl(#{avatar_hue(owner(@item).username)},65%,18%);color:hsl(#{avatar_hue(owner(@item).username)},75%,75%)"}
                >
                  {initial(owner(@item).username)}
                </span>
                <span class="article-meta-val">{owner(@item).username}</span>
              </span>
              <span class="card-meta-dot">·</span>
            <% end %>
            <span class="article-meta-item" title={absolute_time(@item.updated_at)}>
              <span class="article-meta-val">v{@item.version_number} · {relative_time(@item.updated_at)}</span>
            </span>
            <%= if length(@versions) > 1 do %>
              <span class="card-meta-dot">·</span>
              <button class="clear" phx-click="toggle_history" style="background:none;border:none;padding:0;cursor:pointer">
                {if @show_history, do: "hide history", else: "history (#{length(@versions)})"}
              </button>
            <% end %>
            <%= if @item.tags != [] do %>
              <span class="card-meta-dot">·</span>
              <span class="chip-row" style="gap:6px">
                <.link
                  :for={tag <- @item.tags}
                  navigate={~p"/w/#{@workspace.slug}?tag=#{tag}"}
                  class="chip chip-accent"
                >
                  {tag}
                </.link>
              </span>
            <% end %>
          </div>
        </header>

        <%= if @show_history do %>
          <div class="version-history">
            <div class="section-label">Version history</div>
            <ol class="version-list">
              <li :for={v <- @versions} class={"version-item " <> if v.id == @item.id, do: "version-current", else: ""}>
                <div class="version-meta">
                  <span class="version-num">v{v.version_number}</span>
                  <%= if v.actor_user do %>
                    <span class="version-actor">
                      {actor_icon(v.actor_type)} {v.actor_user.username}
                    </span>
                  <% end %>
                  <span title={absolute_time(v.inserted_at)}>{relative_time(v.inserted_at)}</span>
                </div>
                <%= if v.intent && v.intent != "" do %>
                  <div class="version-intent">{v.intent}</div>
                <% end %>
                <%= if v.operations && v.operations != [] do %>
                  <div class="version-ops">
                    <span :for={op <- v.operations} class="version-op">
                      {op["op"]}
                    </span>
                  </div>
                <% end %>
              </li>
            </ol>
          </div>
        <% end %>

        <article class="prose">
          <AvelineWeb.BlockRenderer.render blocks={@item.blocks || []} />
        </article>

        <%= if @related != [] do %>
          <div class="section-label" style="margin-top:48px">
            Related <span class="count">{length(@related)}</span>
          </div>
          <ul class="card-list">
            <li :for={r <- @related}>
              <.link navigate={~p"/w/#{@workspace.slug}/d/#{r.slug}"} class="card">
                <div class="card-title">
                  <%= if r.pinned do %>
                    <span class="pin">
                      <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor">
                        <path d="M12 2l2.39 7.36H22l-6.18 4.49L18.21 22 12 17.27 5.79 22l2.39-8.15L2 9.36h7.61z" />
                      </svg>
                    </span>
                  <% end %>
                  {r.title}
                </div>
                <%= if r.summary do %>
                  <div class="card-summary">{r.summary}</div>
                <% end %>
                <div class="card-meta">
                  <span title={absolute_time(r.updated_at)}>{relative_time(r.updated_at)}</span>
                  <%= if r.tags != [] do %>
                    <span class="card-meta-dot">·</span>
                    <span style="display:flex;gap:4px;flex-wrap:wrap">
                      <span :for={t <- r.tags} class="chip">{t}</span>
                    </span>
                  <% end %>
                </div>
              </.link>
            </li>
          </ul>
        <% end %>
      </div>

      <aside class="thread-panel" id="thread">
        <div class="thread-panel-header">
          <span>Thread</span>
          <span class="count">{length(@messages)}</span>
          <span style="flex:1"></span>
          <span class="live-dot" title="Live updates via PubSub"></span>
        </div>

        <div class="thread-scroll" id="thread-scroll" phx-hook="ScrollOnAppend" data-count={length(@messages)}>
          <%= if @messages == [] do %>
            <div class="thread-empty">No replies yet.<br />Be the first to post.</div>
          <% else %>
            <ol class="thread-list">
              <li :for={m <- @messages} class="thread-message" id={"m-#{m.id}"}>
                <div class="thread-avatar">
                  <%= if message_actor(m) do %>
                    <span
                      class="avatar-sm"
                      style={"background:hsl(#{avatar_hue(message_actor(m).username)},65%,18%);color:hsl(#{avatar_hue(message_actor(m).username)},75%,75%)"}
                    >
                      {initial(message_actor(m).username)}
                    </span>
                  <% else %>
                    <span class="avatar-sm">?</span>
                  <% end %>
                </div>
                <div class="thread-body">
                  <div class="thread-meta">
                    <span class="thread-author">
                      {if message_actor(m), do: message_actor(m).username, else: "?"}
                    </span>
                    <span class="actor-badge" title={m.actor_type}>{actor_icon(m.actor_type)}</span>
                    <span class="card-meta-dot">·</span>
                    <span title={absolute_time(m.inserted_at)}>{relative_time(m.inserted_at)}</span>
                    <%= if m.edited_at do %>
                      <span class="card-meta-dot">·</span>
                      <span class="thread-edited" title={absolute_time(m.edited_at)}>edited</span>
                    <% end %>
                    <%= if m.resolved_at do %>
                      <span class="card-meta-dot">·</span>
                      <span class="thread-resolved" title={absolute_time(m.resolved_at)}>resolved</span>
                    <% end %>
                    <%= if @current_user && message_actor(m) && message_actor(m).id == @current_user.id do %>
                      <span class="thread-actions">
                        <button
                          phx-click="delete_message"
                          phx-value-id={m.id}
                          data-confirm="Delete this reply?"
                          class="thread-action-btn"
                        >
                          delete
                        </button>
                      </span>
                    <% end %>
                  </div>
                  <div class={"thread-content " <> if m.resolved_at, do: "thread-content-resolved", else: ""}>
                    {plain_text_to_html(m.body)}
                  </div>
                </div>
              </li>
            </ol>
          <% end %>
        </div>

        <%= if @current_user do %>
          <div class="thread-composer-wrap">
            <form
              phx-submit="post_reply"
              id="reply-form"
              phx-hook="ResetOnEvent"
              data-reset-event="reset-form"
              class="reply-composer"
            >
              <textarea
                name="body"
                class="reply-input"
                placeholder="Reply to this doc…"
                rows="2"
              ></textarea>
              <div class="reply-footer">
                <span class="reply-hint">Cmd+Enter to post</span>
                <button type="submit" class="reply-submit">Post</button>
              </div>
            </form>
          </div>
        <% end %>
      </aside>
    </div>
    """
  end

  # Plain-text thread bodies (no markdown): escape HTML, newlines → <br>.
  defp plain_text_to_html(nil), do: ""

  defp plain_text_to_html(body) when is_binary(body) do
    body
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> String.replace("\n", "<br />")
    |> Phoenix.HTML.raw()
  end
end
