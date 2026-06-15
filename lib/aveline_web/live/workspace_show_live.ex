defmodule AvelineWeb.WorkspaceShowLive do
  @moduledoc false
  use AvelineWeb, :live_view

  alias Aveline.Docs
  alias Aveline.DocViews
  alias Aveline.Kudos
  alias Aveline.Workspaces
  alias AvelineWeb.LiveSession

  @impl true
  def mount(%{"slug" => slug}, session, socket) do
    user = LiveSession.current_user(session)

    case LiveSession.fetch_workspace_for_user(slug, user) do
      {:ok, ws} ->
        {:ok,
         assign(socket,
           page_title: "Aveline · #{ws.name}",
           current_user: user,
           workspace: ws,
           sidebar_workspaces: Workspaces.list_for_user(user.id),
           workspace_tags: Docs.list_workspace_tags(ws.id),
           # Every workspace member appears as a chip — non-owners just
           # render disabled (count 0). Mirrors tag chip behaviour.
           workspace_authors:
             Workspaces.list_members(ws.id)
             |> Enum.map(& &1.user)
             |> Enum.sort_by(& &1.username),
           chip_counts: %{},
           author_counts: %{},
           selected_tags: [],
           selected_authors: [],
           pin_mode: :pinned_first,
           sort: :recent,
           search: "",
           items: [],
           view_counts: %{},
           kudos_counts: %{},
           total_count: 0,
           pinned_count: 0,
           page_size: Aveline.Pagination.default_page_size(),
           has_more?: false
         )}

      :not_found ->
        {:ok,
         socket
         |> put_flash(:error, "Workspace not found.")
         |> push_navigate(to: ~p"/")}

      :forbidden ->
        {:ok,
         socket
         |> put_flash(:error, "You are not a member of this workspace.")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    selected_tags = parse_tags(params["tag"])
    selected_authors =
      parse_authors(params["author"], socket.assigns.workspace_authors)
    pin_mode = parse_pin_mode(params["pin"])
    sort = parse_sort(params["sort"])
    search = params["q"] || ""

    ws = socket.assigns.workspace
    page_size = socket.assigns.page_size
    owner_ids = author_ids(selected_authors, socket.assigns.workspace_authors)

    # Fetch one extra row so we can tell whether more pages exist without
    # a separate COUNT(*).
    raw =
      Docs.list_current(ws.id,
        pin_mode: pin_mode,
        sort: sort,
        tags: selected_tags,
        owner_ids: owner_ids,
        search: search,
        limit: page_size + 1
      )

    {items, has_more?} =
      case raw do
        list when length(list) > page_size -> {Enum.take(list, page_size), true}
        list -> {list, false}
      end

    base_ids = Enum.map(items, & &1.base_doc_id)
    # Facet-style chip counts. For each tag/author, how many docs in the
    # CURRENT filter set also carry it. Selected entries trivially match
    # every doc; unselected ones with count 0 mean "no overlap — adding
    # this would empty the page," and we render those disabled.
    chip_counts = items |> Enum.flat_map(& &1.tags) |> Enum.frequencies()
    author_counts =
      items
      |> Enum.flat_map(fn i -> if i.owner, do: [i.owner.username], else: [] end)
      |> Enum.frequencies()

    {:noreply,
     assign(socket,
       selected_tags: selected_tags,
       selected_authors: selected_authors,
       pin_mode: pin_mode,
       sort: sort,
       search: search,
       items: items,
       chip_counts: chip_counts,
       author_counts: author_counts,
       view_counts: DocViews.counts_by_base(base_ids),
       kudos_counts: Kudos.counts_by_base(base_ids),
       total_count: length(items),
       pinned_count: Enum.count(items, & &1.pinned),
       has_more?: has_more?,
       # Docs is THE docs tab — stay highlighted regardless of filter state
       # so it's clear what page you're on. Clicking the sidebar link
       # navigates to /w/:slug with no query string, which resets filters
       # naturally via handle_params.
       nav_active: :all,
       topbar_title:
         case selected_tags do
           [] -> "Docs"
           [one] -> "##{one}"
           many -> Enum.map_join(many, " · ", &"##{&1}")
         end
     )}
  end

  defp parse_tags(nil), do: []
  defp parse_tags(""), do: []
  defp parse_tags(s) when is_binary(s), do: [s]
  defp parse_tags(list) when is_list(list), do: list |> Enum.filter(&(is_binary(&1) and &1 != "")) |> Enum.uniq()

  defp parse_authors(nil, _users), do: []
  defp parse_authors("", _users), do: []
  defp parse_authors(s, users) when is_binary(s), do: parse_authors([s], users)
  defp parse_authors(list, users) when is_list(list) do
    known = MapSet.new(users, & &1.username)
    list |> Enum.filter(&(is_binary(&1) and &1 != "" and MapSet.member?(known, &1))) |> Enum.uniq()
  end

  defp author_ids([], _users), do: []
  defp author_ids(usernames, users) do
    lookup = Map.new(users, &{&1.username, &1.id})
    Enum.flat_map(usernames, fn u -> if id = lookup[u], do: [id], else: [] end)
  end

  defp parse_pin_mode("interleave"), do: :interleave
  defp parse_pin_mode(_),             do: :pinned_first

  defp parse_sort("kudos"), do: :kudos
  defp parse_sort("views"), do: :views
  defp parse_sort(_),       do: :recent

  @impl true
  def handle_event("toggle_tag", %{"tag" => tag}, socket) do
    new_tags =
      if tag in socket.assigns.selected_tags do
        List.delete(socket.assigns.selected_tags, tag)
      else
        socket.assigns.selected_tags ++ [tag]
      end

    {:noreply, push_patch(socket, to: build_path(socket, %{tag: new_tags}))}
  end

  def handle_event("toggle_author", %{"author" => username}, socket) do
    new_authors =
      if username in socket.assigns.selected_authors do
        List.delete(socket.assigns.selected_authors, username)
      else
        socket.assigns.selected_authors ++ [username]
      end

    {:noreply, push_patch(socket, to: build_path(socket, %{author: new_authors}))}
  end

  def handle_event("search", %{"value" => v}, socket) do
    {:noreply, push_patch(socket, to: build_path(socket, %{q: v}))}
  end

  def handle_event("set_pin_mode", %{"mode" => mode}, socket) do
    {:noreply, push_patch(socket, to: build_path(socket, %{pin: mode_to_param(mode)}))}
  end

  def handle_event("set_sort", %{"sort" => sort}, socket) do
    {:noreply, push_patch(socket, to: build_path(socket, %{sort: sort_to_param(sort)}))}
  end

  def handle_event("load_more", _, socket) do
    %{
      workspace: ws,
      selected_tags: tags,
      selected_authors: authors,
      workspace_authors: ws_authors,
      pin_mode: pin_mode,
      sort: sort,
      items: existing,
      page_size: page_size
    } = socket.assigns

    raw =
      Docs.list_current(ws.id,
        pin_mode: pin_mode,
        sort: sort,
        tags: tags,
        owner_ids: author_ids(authors, ws_authors),
        search: socket.assigns.search,
        limit: page_size + 1,
        offset: length(existing)
      )

    {next, has_more?} =
      case raw do
        list when length(list) > page_size -> {Enum.take(list, page_size), true}
        list -> {list, false}
      end

    items = existing ++ next
    base_ids = Enum.map(items, & &1.base_doc_id)

    {:noreply,
     assign(socket,
       items: items,
       view_counts: DocViews.counts_by_base(base_ids),
       kudos_counts: Kudos.counts_by_base(base_ids),
       chip_counts: items |> Enum.flat_map(& &1.tags) |> Enum.frequencies(),
       author_counts:
         items
         |> Enum.flat_map(fn i -> if i.owner, do: [i.owner.username], else: [] end)
         |> Enum.frequencies(),
       has_more?: has_more?
     )}
  end

  defp mode_to_param("pinned_first"), do: nil
  defp mode_to_param("interleave"),   do: "interleave"
  defp sort_to_param("recent"), do: nil
  defp sort_to_param(other), do: other

  defp build_path(socket, overrides) when is_map(overrides) do
    base = %{
      tag: socket.assigns.selected_tags,
      author: socket.assigns.selected_authors,
      pin: pin_param(socket.assigns.pin_mode),
      sort: sort_param(socket.assigns.sort),
      q: nz(socket.assigns.search)
    }

    merged = Map.merge(base, overrides)

    # Phoenix uses Plug.Conn.Query (last-wins on repeated keys). To get
    # real lists back we serialize as `key[]=a&key[]=b` — pass the value
    # as a list and Plug handles the [] syntax for us.
    tags = Map.get(merged, :tag, [])
    authors = Map.get(merged, :author, [])

    scalars =
      merged
      |> Map.drop([:tag, :author])
      |> Enum.reject(fn {_k, v} -> v in [nil, "", false] end)
      |> Enum.map(fn {k, v} -> {Atom.to_string(k), v} end)

    query =
      scalars
      |> maybe_append_list("tag", tags)
      |> maybe_append_list("author", authors)

    if query == [] do
      ~p"/w/#{socket.assigns.workspace.slug}"
    else
      ~p"/w/#{socket.assigns.workspace.slug}?#{query}"
    end
  end

  defp maybe_append_list(query, _key, []), do: query
  defp maybe_append_list(query, key, list), do: query ++ [{key, list}]

  defp nz(""), do: nil
  defp nz(s), do: s

  defp pin_param(:interleave), do: "interleave"
  defp pin_param(_), do: nil

  defp sort_param(:kudos), do: "kudos"
  defp sort_param(:views), do: "views"
  defp sort_param(_), do: nil

  @impl true
  def render(assigns) do
    # All filtering — tags, authors, search (Postgres FTS), pin — happens
    # in SQL via Docs.list_current/2. The render just paints @items.
    assigns = assign(assigns, shown_items: assigns.items)

    ~H"""
    <div class="content">
      <h1 class="page-title">Docs</h1>
      <p class="page-subtitle">
        Everything written in <span class="mono">{@workspace.slug}</span> — filter by tag or author, search title and content.
      </p>

      <div class="filter-bar">
        <div class="filter-row">
          <span class="filter-row-icon" title="Search">
            <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
              <circle cx="7" cy="7" r="4.5" />
              <path d="M10.5 10.5L14 14" />
            </svg>
          </span>
          <form phx-submit="search" class="filter-row-form">
            <input
              type="text"
              name="value"
              value={@search}
              placeholder="Search docs by title & content"
              class="search-input"
              autocomplete="off"
            />
          </form>
        </div>
        <%= if @workspace_tags != [] do %>
          <div class="filter-row">
            <span class="filter-row-icon" title="Filter by tag">
              <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5">
                <path d="M2 7l5-5h6v6l-5 5z" stroke-linejoin="round" />
                <circle cx="9.5" cy="6.5" r="0.9" fill="currentColor" />
              </svg>
            </span>
            <div class="chip-row">
              <%= for tag <- @workspace_tags do %>
                <% selected = tag in @selected_tags %>
                <% count = Map.get(@chip_counts, tag, 0) %>
                <% disabled = not selected and count == 0 %>
                <button
                  phx-click={unless disabled, do: "toggle_tag"}
                  phx-value-tag={tag}
                  disabled={disabled}
                  class={"chip chip-tag " <> cond do
                    selected -> "chip-active"
                    disabled -> "chip-disabled"
                    true -> ""
                  end}
                  title={if disabled, do: "No overlap with current filter", else: nil}
                >
                  <span class="chip-text">{tag}</span>
                  <span class="chip-meta">{if selected, do: "•", else: count}</span>
                </button>
              <% end %>
            </div>
          </div>
        <% end %>

        <%= if @workspace_authors != [] do %>
          <div class="filter-row">
            <span class="filter-row-icon" title="Filter by author">
              <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5">
                <circle cx="8" cy="6" r="2.6" />
                <path d="M3 13.5c0-2.2 2.2-3.5 5-3.5s5 1.3 5 3.5" stroke-linecap="round" />
              </svg>
            </span>
            <div class="chip-row">
              <%= for u <- @workspace_authors do %>
                <% selected = u.username in @selected_authors %>
                <% count = Map.get(@author_counts, u.username, 0) %>
                <% disabled = not selected and count == 0 %>
                <button
                  phx-click={unless disabled, do: "toggle_author"}
                  phx-value-author={u.username}
                  disabled={disabled}
                  class={"chip chip-author " <> cond do
                    selected -> "chip-active"
                    disabled -> "chip-disabled"
                    true -> ""
                  end}
                  title={if disabled, do: "No overlap with current filter", else: nil}
                >
                  <span class="chip-text">{u.username}</span>
                  <span class="chip-meta">{if selected, do: "•", else: count}</span>
                </button>
              <% end %>
            </div>
          </div>
        <% end %>

        <div class="filter-row">
          <span class="filter-row-icon" title="Sort and pin behavior">
            <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
              <path d="M4 3v10" />
              <path d="M2 11l2 2 2-2" />
              <path d="M12 13V3" />
              <path d="M10 5l2-2 2 2" />
            </svg>
          </span>
          <div class="seg-row">
            <div class="seg" role="group" aria-label="Pin behaviour">
              <button
                :for={{label, mode} <- [{"Pinned first", :pinned_first}, {"Interleave", :interleave}]}
                phx-click="set_pin_mode"
                phx-value-mode={Atom.to_string(mode)}
                class={"seg-btn " <> if @pin_mode == mode, do: "seg-btn-active", else: ""}
              >
                {label}
              </button>
            </div>
            <div class="seg" role="group" aria-label="Sort">
              <button
                :for={{label, s} <- [{"Recent", :recent}, {"Kudos", :kudos}, {"Views", :views}]}
                phx-click="set_sort"
                phx-value-sort={Atom.to_string(s)}
                class={"seg-btn " <> if @sort == s, do: "seg-btn-active", else: ""}
              >
                {label}
              </button>
            </div>
          </div>
        </div>
      </div>

      <%= if @shown_items == [] do %>
        <div class="empty">No docs match the current filter.</div>
      <% else %>
        <ul class="card-list">
          <li :for={i <- @shown_items}>
            <.link navigate={~p"/w/#{@workspace.slug}/d/#{i.slug}"} class="card">
              <div class="card-title">
                <%= if i.pinned do %>
                  <span class="card-pin" title="Pinned" aria-label="Pinned">
                    <svg viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">
                      <path d="M12 17v5"/>
                      <path d="M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z"/>
                    </svg>
                  </span>
                <% end %>
                {i.title}
              </div>
              <%= if i.summary do %>
                <div class="card-summary">{i.summary}</div>
              <% end %>
              <div class="card-meta">
                <%= if i.actor_user do %>
                  <.author text={i.actor_user.username} />
                  <span class="card-meta-dot">·</span>
                <% end %>
                <span title={absolute_time(i.updated_at)}>{relative_time(i.updated_at)}</span>
                <span class="card-meta-dot">·</span>
                <span class="card-stat" title={"#{Map.get(@view_counts, i.base_doc_id, 0)} views"}>
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/>
                    <circle cx="12" cy="12" r="3"/>
                  </svg>
                  <span>{Map.get(@view_counts, i.base_doc_id, 0)}</span>
                </span>
                <span class="card-stat" title={"#{Map.get(@kudos_counts, i.base_doc_id, 0)} kudos"}>
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M6 9H4.5a2.5 2.5 0 0 1 0-5H6"/>
                    <path d="M18 9h1.5a2.5 2.5 0 0 0 0-5H18"/>
                    <path d="M4 22h16"/>
                    <path d="M10 14.66V17c0 .55-.47.98-.97 1.21C7.85 18.75 7 20.24 7 22"/>
                    <path d="M14 14.66V17c0 .55.47.98.97 1.21C16.15 18.75 17 20.24 17 22"/>
                    <path d="M18 2H6v7a6 6 0 0 0 12 0V2z"/>
                  </svg>
                  <span>{Map.get(@kudos_counts, i.base_doc_id, 0)}</span>
                </span>
                <%= if i.tags != [] do %>
                  <span class="card-meta-dot">·</span>
                  <span style="display:flex;gap:4px;flex-wrap:wrap">
                    <.tag :for={t <- i.tags} text={t} />
                  </span>
                <% end %>
              </div>
            </.link>
          </li>
        </ul>
        <%= if @has_more? do %>
          <div class="load-more-wrap">
            <button type="button" phx-click="load_more" class="load-more-btn">
              Load more
            </button>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end
end
