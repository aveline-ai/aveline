defmodule AvelineWeb.ItemShowLive do
  @moduledoc false
  use AvelineWeb, :live_view

  alias Aveline.Broadcasts
  alias Aveline.Items
  alias Aveline.Messages
  alias Aveline.Views
  alias AvelineWeb.LiveSession

  @impl true
  def mount(%{"slug" => slug, "item_slug" => item_slug}, session, socket) do
    user = LiveSession.current_user(session)

    case LiveSession.fetch_workspace_for_user(slug, user) do
      {:ok, ws} ->
        case Items.get_by_slug(ws.id, item_slug) do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, "Item not found.")
             |> push_navigate(to: ~p"/w/#{ws.slug}")}

          item ->
            if connected?(socket) do
              Broadcasts.subscribe(Broadcasts.item_messages_topic(item.id))
              Broadcasts.subscribe(Broadcasts.item_topic(item.id))
            end

            body_html = render_markdown(item.body || "")
            related = Items.related_items(item, 5)
            all_items = Items.list_items(ws.id)
            messages = Messages.list_for_item(item.id)

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
               body_html: body_html,
               related: related,
               messages: messages
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
        case Messages.create_message(%{
               "item_id" => item.id,
               "author_id" => user.id,
               "body" => body,
               "created_via" => "web"
             }) do
          {:ok, _msg} ->
            {:noreply, push_event(socket, "reset-form", %{id: "reply-form"})}

          {:error, %Ecto.Changeset{} = cs} ->
            errs =
              cs
              |> Ecto.Changeset.traverse_errors(fn {msg, _} -> msg end)
              |> inspect()

            {:noreply, put_flash(socket, :error, "Could not post reply: " <> errs)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not post reply.")}
        end
    end
  end

  def handle_event("delete_message", %{"id" => id}, socket) do
    %{current_user: user} = socket.assigns

    with %_{} = msg <- Messages.get_message(id),
         {:ok, _} <- Messages.soft_delete_message(msg, user && user.id) do
      {:noreply, socket}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not delete.")}
    end
  end

  @impl true
  def handle_info({event, msg}, socket)
      when event in [:message_created, :message_updated, :message_deleted] do
    msgs =
      case event do
        :message_created ->
          socket.assigns.messages ++ [msg]

        :message_updated ->
          Enum.map(socket.assigns.messages, fn m -> if m.id == msg.id, do: msg, else: m end)

        :message_deleted ->
          Enum.reject(socket.assigns.messages, fn m -> m.id == msg.id end)
      end

    {:noreply, assign(socket, :messages, msgs)}
  end

  def handle_info({:item_updated, item}, socket) do
    if item.id == socket.assigns.item.id do
      {:noreply,
       assign(socket,
         item: item,
         body_html: render_markdown(item.body || ""),
         topbar_title: item.title
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:item_deleted, item}, socket) do
    if item.id == socket.assigns.item.id do
      {:noreply, assign(socket, :item, item)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  defp render_markdown(""), do: ""

  defp render_markdown(body) when is_binary(body) do
    case Earmark.as_html(body, escape: true) do
      {:ok, html, _} -> html
      {:error, html, _} -> html
    end
  end

  defp owner(%{owner: %Ecto.Association.NotLoaded{}}), do: nil
  defp owner(%{owner: o}), do: o
  defp owner(_), do: nil

  defp author_of(%{author: %Ecto.Association.NotLoaded{}}), do: nil
  defp author_of(%{author: a}), do: a
  defp author_of(_), do: nil

  defp message_body_html(body) when is_binary(body) do
    case Earmark.as_html(body, escape: true) do
      {:ok, html, _} -> html
      {:error, html, _} -> html
    end
  end

  defp message_body_html(_), do: ""

  @impl true
  def render(assigns) do
    ~H"""
    <div class="item-layout">
      <div class="item-article">
        <%= if @item.deleted_at do %>
          <div class="banner banner-warning">
            This note is deleted. URL preserved for archive.
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
              <span class="article-meta-val">{relative_time(@item.updated_at)}</span>
            </span>
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

        <article class="prose">
          {Phoenix.HTML.raw(@body_html)}
        </article>

        <%= if @related != [] do %>
          <div class="section-label" style="margin-top:48px">
            Related <span class="count">{length(@related)}</span>
          </div>
          <ul class="card-list">
            <li :for={r <- @related}>
              <.link navigate={~p"/w/#{@workspace.slug}/i/#{r.slug}"} class="card">
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

        <div class="banner" style="margin-top:48px">
          Edit via the CLI: <code>aveline edit {@item.slug}</code>
        </div>
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
                  <%= if author_of(m) do %>
                    <span
                      class="avatar-sm"
                      style={"background:hsl(#{avatar_hue(author_of(m).username)},65%,18%);color:hsl(#{avatar_hue(author_of(m).username)},75%,75%)"}
                    >
                      {initial(author_of(m).username)}
                    </span>
                  <% else %>
                    <span class="avatar-sm">?</span>
                  <% end %>
                </div>
                <div class="thread-body">
                  <div class="thread-meta">
                    <span class="thread-author">
                      {if author_of(m), do: author_of(m).username, else: "?"}
                    </span>
                    <span class="card-meta-dot">·</span>
                    <span title={absolute_time(m.inserted_at)}>{relative_time(m.inserted_at)}</span>
                    <%= if m.edited_at do %>
                      <span class="card-meta-dot">·</span>
                      <span class="thread-edited" title={absolute_time(m.edited_at)}>edited</span>
                    <% end %>
                    <%= if m.created_via && m.created_via != "web" do %>
                      <span class="card-meta-dot">·</span>
                      <span class="thread-via">via {m.created_via}</span>
                    <% end %>
                    <%= if @current_user && author_of(m) && author_of(m).id == @current_user.id do %>
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
                  <div class="thread-content">{Phoenix.HTML.raw(message_body_html(m.body))}</div>
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
                placeholder="Reply to this note… (markdown ok)"
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
end
