defmodule AvelineWeb.DocShowLive do
  @moduledoc false
  use AvelineWeb, :live_view

  alias Aveline.Broadcasts
  alias Aveline.Docs
  alias Aveline.DocViews
  alias Aveline.Comments
  alias Aveline.Kudos
  alias Aveline.Workspaces
  alias AvelineWeb.LiveSession

  @impl true
  def mount(%{"slug" => slug, "doc_slug" => doc_slug} = params, session, socket) do
    user = LiveSession.current_user(session)

    case LiveSession.fetch_workspace_for_user(slug, user) do
      {:ok, ws} ->
        case Docs.get_current_by_slug(ws.id, doc_slug) do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, "Item not found.")
             |> push_navigate(to: ~p"/w/#{ws.slug}")}

          current_doc ->
            if connected?(socket) do
              Broadcasts.subscribe(Broadcasts.doc_comments_topic(current_doc.base_doc_id))
              Broadcasts.subscribe(Broadcasts.doc_topic(current_doc.base_doc_id))
              # Record a "read" event when the LV connects (not on the dead
              # render) so reloads dedupe naturally with the connect flow.
              if user, do: DocViews.record(ws.id, current_doc.base_doc_id, user.id, "human")
            end

            all_items = Docs.list_current(ws.id)
            messages = Comments.list_for_base_doc(current_doc.base_doc_id)
            versions = Docs.list_versions(current_doc.base_doc_id)

            # Optional time-travel — `:version` param means we're showing a
            # specific historical version's blocks. Comments and sidebar
            # always use the logical (current) item; only the rendered body
            # changes.
            {showing, is_historical} =
              case resolve_version(params["version"], versions, current_doc) do
                {:ok, %{version_number: n}} when n == current_doc.version_number ->
                  {current_doc, false}

                {:ok, older} ->
                  {older, true}

                :error ->
                  {current_doc, false}
              end

            {:ok,
             assign(socket,
               page_title: "Aveline · #{current_doc.title}",
               current_user: user,
               workspace: ws,
               sidebar_workspaces: Workspaces.list_for_user(user.id),
               total_count: length(all_items),
               pinned_count: Enum.count(all_items, & &1.pinned),
               topbar_title: current_doc.title,
               # `current_doc` is always the latest (for nav, switcher,
               # comments). `item` is what we actually render — either
               # current or a historical version.
               current_doc: current_doc,
               item: showing,
               historical?: is_historical,
               messages: messages,
               versions: versions,
               commenting_on_block_id: nil,
               kudos_count: Kudos.count_for_base(current_doc.base_doc_id),
               kudos_given?: user && Kudos.given_by?(current_doc.base_doc_id, user.id),
               view_count: DocViews.count_for_base(current_doc.base_doc_id)
             )}
        end

      :not_found ->
        {:ok, socket |> put_flash(:error, "Workspace not found.") |> push_navigate(to: ~p"/")}

      :forbidden ->
        {:ok, socket |> put_flash(:error, "Forbidden.") |> push_navigate(to: ~p"/")}
    end
  end

  defp resolve_version(nil, _versions, current), do: {:ok, current}
  defp resolve_version("", _versions, current), do: {:ok, current}

  defp resolve_version(raw, versions, _current) when is_binary(raw) do
    case Integer.parse(raw) do
      {n, ""} ->
        case Enum.find(versions, &(&1.version_number == n)) do
          nil -> :error
          version -> {:ok, version}
        end

      _ ->
        :error
    end
  end

  defp resolve_version(_, _, _), do: :error

  @impl true
  def handle_event("post_comment", params, socket) do
    %{current_user: user, item: item} = socket.assigns
    body = String.trim(params["body"] || "")
    parent_id = nil_if_blank(params["parent_comment_id"])
    block_id = nil_if_blank(params["block_id"])
    and_resolve? = params["and_resolve"] == "true"
    form_id = params["form_id"] || "reply-form"

    cond do
      user == nil ->
        {:noreply, put_flash(socket, :error, "Sign in to post.")}

      body == "" ->
        {:noreply, socket}

      true ->
        with {:ok, _msg} <-
               Comments.create_comment(%{
                 "doc_id" => item.id,
                 "parent_comment_id" => parent_id,
                 "block_id" => block_id,
                 "body" => body,
                 "actor_user_id" => user.id,
                 "actor_type" => "human"
               }),
             :ok <- maybe_resolve_parent(parent_id, and_resolve?, user.id) do
          {:noreply,
           socket
           |> assign(:commenting_on_block_id, nil)
           |> push_event("reset-form", %{id: form_id})}
        else
          _ -> {:noreply, put_flash(socket, :error, "Could not post.")}
        end
    end
  end

  def handle_event("start_block_comment", %{"block-id" => block_id}, socket) do
    {:noreply, assign(socket, :commenting_on_block_id, block_id)}
  end

  def handle_event("cancel_block_comment", _, socket) do
    {:noreply, assign(socket, :commenting_on_block_id, nil)}
  end

  def handle_event("resolve_comment", %{"id" => id}, socket) do
    %{current_user: user} = socket.assigns

    with %_{} = msg <- Comments.get_comment(id),
         {:ok, _} <- Comments.resolve_comment(msg, user && user.id) do
      {:noreply, socket}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not resolve.")}
    end
  end

  def handle_event("unresolve_comment", %{"id" => id}, socket) do
    with %_{} = msg <- Comments.get_comment(id),
         {:ok, _} <- Comments.unresolve_comment(msg) do
      {:noreply, socket}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not unresolve.")}
    end
  end

  def handle_event("toggle_kudos", _, socket) do
    %{current_user: user, workspace: ws, current_doc: current_doc} = socket.assigns

    cond do
      user == nil ->
        {:noreply, put_flash(socket, :error, "Sign in to give kudos.")}

      user.id == current_doc.owner_id ->
        {:noreply, put_flash(socket, :error, "You can't give kudos to your own doc.")}

      true ->
        {:ok, _} = Kudos.toggle(ws.id, current_doc.base_doc_id, user.id)

        {:noreply,
         assign(socket,
           kudos_given?: Kudos.given_by?(current_doc.base_doc_id, user.id),
           kudos_count: Kudos.count_for_base(current_doc.base_doc_id)
         )}
    end
  end

  def handle_event("toggle_pin", _, socket) do
    %{current_user: user, current_doc: current_doc} = socket.assigns

    if user do
      case Docs.set_pinned(current_doc, not current_doc.pinned, user.id) do
        {:ok, _} -> {:noreply, socket}
        {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update pin.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Sign in to pin.")}
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

  defp nil_if_blank(nil), do: nil
  defp nil_if_blank(""), do: nil
  defp nil_if_blank(s) when is_binary(s), do: s

  defp maybe_resolve_parent(parent_id, true, user_id) when is_binary(parent_id) do
    with %_{} = c <- Comments.get_comment(parent_id),
         {:ok, _} <- Comments.resolve_comment(c, user_id) do
      :ok
    else
      _ -> {:error, :resolve_failed}
    end
  end

  defp maybe_resolve_parent(_, _, _), do: :ok

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

  def handle_info({:doc_updated, new_current}, socket) do
    if new_current.base_doc_id == socket.assigns.current_doc.base_doc_id do
      versions = Docs.list_versions(new_current.base_doc_id)
      # If we're viewing a specific historical version, don't replace the
      # rendered `item` — just refresh the live state + history list.
      item = if socket.assigns.historical?, do: socket.assigns.item, else: new_current

      {:noreply,
       assign(socket,
         current_doc: new_current,
         item: item,
         topbar_title: new_current.title,
         versions: versions
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  defp message_actor(%{actor_user: %Ecto.Association.NotLoaded{}}), do: nil
  defp message_actor(%{actor_user: a}), do: a
  defp message_actor(_), do: nil


  @impl true
  def render(assigns) do
    block_ids = collect_block_ids(assigns.item.blocks || [])
    {by_block, doc_level, orphans} = group_threads(assigns.messages, block_ids)

    assigns =
      assign(assigns,
        threads_by_block: by_block,
        doc_level_threads: doc_level,
        orphan_threads: orphans
      )

    ~H"""
    <div class="doc-layout">
      <div class="doc-article">
        <.doc_state_banner
          item={@item}
          current_doc={@current_doc}
          workspace={@workspace}
          historical?={@historical?}
        />

        <header class="article-header">
          <div class="article-title-row">
            <h1 class="article-title">{@item.title}</h1>
            <% own_doc? = @current_user && @current_user.id == @current_doc.owner_id %>
            <%= if @current_user && not own_doc? do %>
              <button
                type="button"
                phx-click="toggle_kudos"
                class={"article-kudos-btn " <> if @kudos_given?, do: "is-given", else: ""}
                title={if @kudos_given?, do: "You gave kudos — click to take it back", else: "Give kudos"}
                aria-pressed={if @kudos_given?, do: "true", else: "false"}
                aria-label={if @kudos_given?, do: "Remove kudos", else: "Give kudos"}
              >
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M6 9H4.5a2.5 2.5 0 0 1 0-5H6"/>
                  <path d="M18 9h1.5a2.5 2.5 0 0 0 0-5H18"/>
                  <path d="M4 22h16"/>
                  <path d="M10 14.66V17c0 .55-.47.98-.97 1.21C7.85 18.75 7 20.24 7 22"/>
                  <path d="M14 14.66V17c0 .55.47.98.97 1.21C16.15 18.75 17 20.24 17 22"/>
                  <path d="M18 2H6v7a6 6 0 0 0 12 0V2z"/>
                </svg>
                <span class="article-kudos-count">{@kudos_count}</span>
              </button>
            <% else %>
              <span :if={@kudos_count > 0} class="article-kudos-btn is-static" title={"#{@kudos_count} kudos"}>
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M6 9H4.5a2.5 2.5 0 0 1 0-5H6"/>
                  <path d="M18 9h1.5a2.5 2.5 0 0 0 0-5H18"/>
                  <path d="M4 22h16"/>
                  <path d="M10 14.66V17c0 .55-.47.98-.97 1.21C7.85 18.75 7 20.24 7 22"/>
                  <path d="M14 14.66V17c0 .55.47.98.97 1.21C16.15 18.75 17 20.24 17 22"/>
                  <path d="M18 2H6v7a6 6 0 0 0 12 0V2z"/>
                </svg>
                <span class="article-kudos-count">{@kudos_count}</span>
              </span>
            <% end %>
            <%= if @current_user do %>
              <button
                type="button"
                phx-click="toggle_pin"
                class={"article-pin-btn " <> if @current_doc.pinned, do: "is-pinned", else: ""}
                title={if @current_doc.pinned, do: "Pinned — click to unpin", else: "Pin this doc"}
                aria-pressed={if @current_doc.pinned, do: "true", else: "false"}
                aria-label={if @current_doc.pinned, do: "Unpin", else: "Pin"}
              >
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M12 17v5"/>
                  <path d="M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z"/>
                </svg>
              </button>
            <% else %>
              <span :if={@current_doc.pinned} class="article-pin-btn is-pinned is-static" title="Pinned" aria-label="Pinned">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M12 17v5"/>
                  <path d="M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z"/>
                </svg>
              </span>
            <% end %>
          </div>

          <%= if @item.summary && @item.summary != "" do %>
            <p class="article-summary">{@item.summary}</p>
          <% end %>

          <div class="article-meta">
            <span class="article-meta-item">
              <.author text={if @item.actor_user, do: @item.actor_user.username, else: "?"}>
                <:icon><AvelineWeb.Icons.actor type={@item.actor_type} class="actor-icon" title={@item.actor_type} /></:icon>
              </.author>
            </span>
            <span class="card-meta-dot">·</span>
            <%= if length(@versions) > 1 do %>
              <details class="version-switcher">
                <summary class="version-switcher-trigger" title={absolute_time(@item.updated_at)}>
                  <span class="article-meta-val">v{@item.version_number} · {relative_time(@item.updated_at)}</span>
                  <svg class="version-switcher-chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"/></svg>
                </summary>
                <div class="version-switcher-menu">
                  <div class="switcher-label">History · {length(@versions)} versions</div>
                  <.link
                    :for={v <- @versions}
                    navigate={
                      if v.version_number == @current_doc.version_number,
                        do: ~p"/w/#{@workspace.slug}/d/#{@current_doc.slug}",
                        else: ~p"/w/#{@workspace.slug}/d/#{@current_doc.slug}/v/#{v.version_number}"
                    }
                    class={"version-switcher-item " <> if v.version_number == @item.version_number, do: "current", else: ""}
                  >
                    <span class="version-switcher-num">v{v.version_number}</span>
                    <%= if v.actor_user do %>
                      <span class="version-switcher-actor">
                        <AvelineWeb.Icons.actor type={v.actor_type} class="actor-icon" />
                        {v.actor_user.username}
                      </span>
                    <% end %>
                    <span class="version-switcher-time" title={absolute_time(v.inserted_at)}>
                      {relative_time(v.inserted_at)}
                    </span>
                    <%= if v.version_number == @item.version_number do %>
                      <span class="check">✓</span>
                    <% end %>
                    <%= if v.intent && v.intent != "" do %>
                      <span class="version-switcher-intent">{v.intent}</span>
                    <% end %>
                    <%= if summary = disposition_summary(v.comment_dispositions) do %>
                      <span class="version-switcher-dispo">{summary}</span>
                    <% end %>
                  </.link>
                </div>
              </details>
            <% else %>
              <span class="article-meta-item" title={absolute_time(@item.updated_at)}>
                <span class="article-meta-val">v{@item.version_number} · {relative_time(@item.updated_at)}</span>
              </span>
            <% end %>
            <%= if @item.tags != [] do %>
              <span class="card-meta-dot">·</span>
              <span class="chip-row" style="gap:6px">
                <.link
                  :for={tag <- @item.tags}
                  navigate={~p"/w/#{@workspace.slug}?tag=#{tag}"}
                  class="chip chip-tag"
                >
                  {tag}
                </.link>
              </span>
            <% end %>
          </div>
        </header>

        <section
          :if={@doc_level_threads != [] or @orphan_threads != [] or @current_user}
          class="doc-discussion doc-discussion-top"
          id="discussion"
        >
          <ol :if={@doc_level_threads != []} class="comment-card-list">
            <li
              :for={thread <- @doc_level_threads}
              id={"thread-#{thread.parent.id}"}
              class={"comment-card-wrap " <> if thread.parent.resolved_at, do: "comment-card-wrap-resolved", else: ""}
            >
              <.comment_card
                thread={thread}
                current_user={@current_user}
                workspace={@workspace}
                current_doc={@current_doc}
              />
            </li>
          </ol>

          <%= if @orphan_threads != [] do %>
            <div class="doc-discussion-subheader">
              <span>Orphaned</span>
              <span class="count">{length(@orphan_threads)}</span>
              <span class="doc-discussion-subnote">
                Block these were on no longer exists in this version.
              </span>
            </div>
            <ol class="comment-card-list">
              <li
                :for={thread <- @orphan_threads}
                id={"thread-#{thread.parent.id}"}
                class={"comment-card-wrap comment-card-wrap-orphan " <> if thread.parent.resolved_at, do: "comment-card-wrap-resolved", else: ""}
              >
                <div :if={caption = orphan_caption(thread.parent)} class="orphan-snippet">
                  <span class="orphan-snippet-label">originally on</span>
                  <span class="orphan-snippet-text">"{caption}"</span>
                </div>
                <.comment_card
                  thread={thread}
                  current_user={@current_user}
                  workspace={@workspace}
                  current_doc={@current_doc}
                />
              </li>
            </ol>
          <% end %>

          <%= if @current_user do %>
            <form
              phx-submit="post_comment"
              id="doc-comment-form"
              phx-hook="ResetOnEvent"
              data-reset-event="reset-form"
              class="comment-composer"
            >
              <input type="hidden" name="form_id" value="doc-comment-form" />
              <textarea
                name="body"
                class="comment-composer-input"
                placeholder="Add a comment…"
                rows="2"
              ></textarea>
              <div class="comment-composer-footer">
                <span class="comment-composer-hint">Cmd+Enter to post</span>
                <button type="submit" class="comment-composer-submit">Post</button>
              </div>
            </form>
          <% end %>
        </section>

        <article class="prose">
          <div class="blocks">
            <%= for b <- @item.blocks || [] do %>
              <AvelineWeb.BlockRenderer.block block={b} />
              <.block_comment_zone
                block_id={b["id"]}
                threads={Map.get(@threads_by_block, b["id"], [])}
                composer_open?={@commenting_on_block_id == b["id"]}
                current_user={@current_user}
                workspace={@workspace}
                current_doc={@current_doc}
              />
            <% end %>
          </div>
        </article>
      </div>
    </div>
    """
  end

  # Top-of-doc state banner. At most one variant ever renders; priority is
  # historical > deleted. Nothing renders when the doc is current + live.
  attr :item, :map, required: true
  attr :current_doc, :map, required: true
  attr :workspace, :map, required: true
  attr :historical?, :boolean, required: true

  defp doc_state_banner(%{historical?: true} = assigns) do
    ~H"""
    <div class="doc-banner doc-banner-historical" role="status">
      <div class="doc-banner-row">
        <span class="doc-banner-tag">Viewing v{@item.version_number}</span>
        <span :if={@item.actor_user} class="doc-banner-actor">
          <AvelineWeb.Icons.actor type={@item.actor_type} class="actor-icon" />
          {@item.actor_user.username}
        </span>
        <span class="card-meta-dot">·</span>
        <span title={absolute_time(@item.inserted_at)}>{relative_time(@item.inserted_at)}</span>
        <span class="doc-banner-spacer"></span>
        <.link
          navigate={~p"/w/#{@workspace.slug}/d/#{@current_doc.slug}"}
          class="doc-banner-action"
        >
          Back to v{@current_doc.version_number} (latest) →
        </.link>
      </div>
      <div :if={@item.intent && @item.intent != ""} class="doc-banner-detail">
        {@item.intent}
      </div>
    </div>
    """
  end

  defp doc_state_banner(%{item: %{deleted_at: %_{}}} = assigns) do
    ~H"""
    <div class="doc-banner doc-banner-deleted" role="status">
      <div class="doc-banner-row">
        <span class="doc-banner-tag">Deleted</span>
        <span>URL preserved for archive.</span>
      </div>
    </div>
    """
  end

  defp doc_state_banner(assigns), do: ~H""

  # Builds {threads_by_block_id, doc_level_threads, orphan_threads}.
  #
  #   * threads_by_block_id — only contains anchored threads whose block_id
  #     is still in the current view's blocks. Renders inline under each block.
  #   * doc_level_threads — comments posted with no block_id.
  #   * orphan_threads — comments whose block_id no longer exists in this
  #     version (block was deleted in a later edit). Surfaced separately
  #     so the conversation isn't lost.
  #
  # A "thread" is %{parent: comment, replies: [comment, ...]}.
  defp group_threads(messages, current_block_ids) do
    block_set = MapSet.new(current_block_ids)

    top_levels = for m <- messages, is_nil(m.parent_comment_id), do: m

    replies =
      messages
      |> Enum.filter(& &1.parent_comment_id)
      |> Enum.group_by(& &1.parent_comment_id)

    threads =
      Enum.map(top_levels, fn parent ->
        %{parent: parent, replies: Map.get(replies, parent.id, [])}
      end)

    Enum.reduce(threads, {%{}, [], []}, fn t, {by_block, doc_level, orphans} ->
      case t.parent.block_id do
        nil ->
          {by_block, [t | doc_level], orphans}

        "" ->
          {by_block, [t | doc_level], orphans}

        bid ->
          if MapSet.member?(block_set, bid) do
            {Map.update(by_block, bid, [t], &[t | &1]), doc_level, orphans}
          else
            {by_block, doc_level, [t | orphans]}
          end
      end
    end)
    |> reverse_buckets()
  end

  defp reverse_buckets({by_block, doc_level, orphans}) do
    by_block = Map.new(by_block, fn {k, v} -> {k, Enum.reverse(v)} end)
    {by_block, Enum.reverse(doc_level), Enum.reverse(orphans)}
  end

  defp collect_block_ids(blocks) do
    Enum.flat_map(blocks, fn b -> if id = b["id"], do: [id], else: [] end)
  end

  # First line / first few words of the original block the orphan pointed
  # at, used as caption on the orphan card. We have the original version
  # preloaded via :doc, so we can introspect its blocks for the snippet.
  defp orphan_caption(%{block_id: bid, doc: %{blocks: blocks}}) when is_binary(bid) and is_list(blocks) do
    case Enum.find(blocks, fn b -> b["id"] == bid end) do
      nil -> nil
      block -> block_snippet(block)
    end
  end

  defp orphan_caption(_), do: nil

  defp block_snippet(%{"type" => "heading", "text" => text}), do: String.slice(text || "", 0, 80)
  defp block_snippet(%{"type" => "code", "content" => content}), do: String.slice(content || "", 0, 80)

  defp block_snippet(%{"type" => "paragraph", "content" => content}) when is_list(content) do
    content
    |> Enum.map_join("", fn s -> s["text"] || "" end)
    |> String.slice(0, 120)
  end

  defp block_snippet(%{"type" => "list", "items" => [first | _]}) when is_map(first) do
    case first["content"] do
      [_ | _] = c -> c |> Enum.map_join("", fn s -> s["text"] || "" end) |> String.slice(0, 120)
      _ -> nil
    end
  end

  defp block_snippet(_), do: nil

  # The inline zone rendered under each block: existing threads + an
  # optional composer if the user clicked the block's "comment" button.
  attr :block_id, :string, required: true
  attr :threads, :list, required: true
  attr :composer_open?, :boolean, required: true
  attr :current_user, :map, required: true
  attr :workspace, :map, required: true
  attr :current_doc, :map, required: true

  defp block_comment_zone(assigns) do
    ~H"""
    <div :if={@threads != [] or @composer_open?} class="block-comments">
      <ol :if={@threads != []} class="comment-card-list">
        <li
          :for={thread <- @threads}
          id={"thread-#{thread.parent.id}"}
          class={"comment-card-wrap " <> if thread.parent.resolved_at, do: "comment-card-wrap-resolved", else: ""}
        >
          <.comment_card
            thread={thread}
            current_user={@current_user}
            workspace={@workspace}
            current_doc={@current_doc}
          />
        </li>
      </ol>

      <%= if @current_user && @composer_open? do %>
        <form
          phx-submit="post_comment"
          id={"block-comment-form-" <> @block_id}
          phx-hook="ResetOnEvent"
          data-reset-event="reset-form"
          class="comment-composer comment-composer-inline"
        >
          <input type="hidden" name="block_id" value={@block_id} />
          <input type="hidden" name="form_id" value={"block-comment-form-" <> @block_id} />
          <textarea
            name="body"
            class="comment-composer-input"
            placeholder="Ask a question about this block…"
            rows="2"
            autofocus
          ></textarea>
          <div class="comment-composer-footer">
            <span class="comment-composer-hint">Cmd+Enter to post</span>
            <button type="button" phx-click="cancel_block_comment" class="comment-composer-cancel">Cancel</button>
            <button type="submit" class="comment-composer-submit">Comment</button>
          </div>
        </form>
      <% end %>
    </div>
    """
  end

  # One self-contained comment thread: parent + nested replies + actions +
  # inline reply composer. Each card is independent — it shows everything
  # needed to read, reply, resolve, or jump back to its block.
  attr :thread, :map, required: true
  attr :current_user, :map, required: true
  attr :workspace, :map, required: true
  attr :current_doc, :map, required: true

  defp comment_card(assigns) do
    ~H"""
    <article class="comment-card">
      <.comment_row
        message={@thread.parent}
        is_reply={false}
        workspace={@workspace}
        current_doc={@current_doc}
        current_user={@current_user}
      />

      <ol :if={@thread.replies != []} class="comment-card-replies">
        <li :for={r <- @thread.replies} id={"m-#{r.id}"}>
          <.comment_row
            message={r}
            is_reply={true}
            workspace={@workspace}
            current_doc={@current_doc}
            current_user={@current_user}
          />
        </li>
      </ol>

      <%= if @current_user && is_nil(@thread.parent.resolved_at) do %>
        <form
          phx-submit="post_comment"
          id={"reply-form-" <> @thread.parent.id}
          phx-hook="ResetOnEvent"
          data-reset-event="reset-form"
          class="comment-composer comment-composer-reply"
        >
          <input type="hidden" name="parent_comment_id" value={@thread.parent.id} />
          <input type="hidden" name="form_id" value={"reply-form-" <> @thread.parent.id} />
          <textarea
            name="body"
            class="comment-composer-input"
            placeholder={"Reply to #{if message_actor(@thread.parent), do: message_actor(@thread.parent).username, else: "this thread"}…"}
            rows="2"
          ></textarea>
          <div class="comment-composer-footer">
            <span class="comment-composer-hint">Cmd+Enter to reply</span>
            <button
              type="submit"
              name="and_resolve"
              value="true"
              class="comment-composer-submit comment-composer-submit-resolve"
              title="Post reply and mark this thread resolved"
            >
              Reply &amp; resolve
            </button>
            <button
              type="submit"
              name="and_resolve"
              value="false"
              class="comment-composer-submit"
            >
              Reply
            </button>
          </div>
        </form>
      <% end %>
    </article>
    """
  end

  # Renders one comment row (top-level or reply). Per-thread reply composer,
  # resolve toggle, and version badge are handled here.
  attr :message, :map, required: true
  attr :current_user, :map, required: true
  attr :workspace, :map, required: true
  attr :current_doc, :map, required: true
  attr :is_reply, :boolean, default: false

  defp comment_row(assigns) do
    ~H"""
    <div class="thread-body">
      <div class="thread-meta">
        <AvelineWeb.Icons.actor type={@message.actor_type} class="actor-icon" title={@message.actor_type} />
        <span class="thread-author">
          {if message_actor(@message), do: message_actor(@message).username, else: "?"}
        </span>
        <span class="card-meta-dot">·</span>
        <span title={absolute_time(@message.inserted_at)}>{relative_time(@message.inserted_at)}</span>
        <%= if @message.edited_at do %>
          <span class="card-meta-dot">·</span>
          <span class="thread-edited" title={absolute_time(@message.edited_at)}>edited</span>
        <% end %>
        <%= if version_badge_visible?(@message, @current_doc) do %>
          <span class="card-meta-dot">·</span>
          <.link
            navigate={
              if @message.doc.version_number == @current_doc.version_number,
                do: ~p"/w/#{@workspace.slug}/d/#{@current_doc.slug}",
                else: ~p"/w/#{@workspace.slug}/d/#{@current_doc.slug}/v/#{@message.doc.version_number}"
            }
            class="thread-version-badge"
            title={"Posted on v#{@message.doc.version_number}"}
          >
            on v{@message.doc.version_number}
          </.link>
        <% end %>
        <%= if not @is_reply && @message.resolved_at do %>
          <span class="card-meta-dot">·</span>
          <span class="thread-resolved" title={absolute_time(@message.resolved_at)}>
            resolved<%= cond do
              resolved_doc = resolver_doc(@message) ->
                " in v#{resolved_doc.version_number}"
              @message.resolved_by ->
                " by #{@message.resolved_by.username}"
              true ->
                ""
            end %>
          </span>
          <.link
            :if={resolver_doc(@message)}
            navigate={resolver_doc_path(@message, @workspace, @current_doc)}
            class="thread-version-badge"
            title="Open the version that resolved this"
          >
            see v{resolver_doc(@message).version_number}
          </.link>
        <% end %>
        <span class="thread-actions">
          <%= if @current_user && not @is_reply do %>
            <%= if @message.resolved_at do %>
              <button phx-click="unresolve_comment" phx-value-id={@message.id} class="thread-action-btn">
                unresolve
              </button>
            <% else %>
              <button phx-click="resolve_comment" phx-value-id={@message.id} class="thread-action-btn">
                resolve
              </button>
            <% end %>
          <% end %>
          <%= if @current_user && message_actor(@message) && message_actor(@message).id == @current_user.id do %>
            <button
              phx-click="delete_message"
              phx-value-id={@message.id}
              data-confirm="Delete this?"
              class="thread-action-btn"
            >
              delete
            </button>
          <% end %>
        </span>
      </div>
      <div class={"thread-content " <> if @message.resolved_at, do: "thread-content-resolved", else: ""}>
        {plain_text_to_html(@message.body)}
      </div>
    </div>
    """
  end

  defp resolver_doc(%{resolved_by_doc: %Aveline.Docs.Doc{} = d}), do: d
  defp resolver_doc(_), do: nil

  # Compact summary line for a version's dispositions: "Resolved 2 · Re-anchored 1".
  # Returns nil when there are no dispositions (so nothing renders).
  defp disposition_summary(nil), do: nil
  defp disposition_summary([]), do: nil

  defp disposition_summary(list) when is_list(list) do
    counts = Enum.frequencies_by(list, & &1["action"])

    [
      counts["resolve"] && "Resolved #{counts["resolve"]}",
      counts["reanchor"] && "Re-anchored #{counts["reanchor"]}",
      counts["leave"] && "Left open #{counts["leave"]}"
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " · ")
    end
  end

  defp resolver_doc_path(%{resolved_by_doc: %Aveline.Docs.Doc{} = d}, workspace, current_doc) do
    if d.version_number == current_doc.version_number,
      do: ~p"/w/#{workspace.slug}/d/#{current_doc.slug}",
      else: ~p"/w/#{workspace.slug}/d/#{current_doc.slug}/v/#{d.version_number}"
  end

  defp version_badge_visible?(%{doc: %{version_number: n}}, %{version_number: m})
       when is_integer(n) and is_integer(m),
       do: true

  defp version_badge_visible?(_, _), do: false

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
