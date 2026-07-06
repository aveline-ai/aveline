defmodule AvelineWeb.WorkspaceShowLive do
  @moduledoc false
  use AvelineWeb, :live_view

  alias Aveline.Docs
  alias Aveline.DocViews
  alias Aveline.Tags
  alias Phoenix.LiveView.JS
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
           sidebar_views: Aveline.Views.list_pinned(ws.id),
           workspace_tags: Docs.list_workspace_tags(ws.id),
           tag_colors: tag_colors(ws.id),
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
           group_by: nil,
           views: Aveline.Views.list_for_workspace(ws.id),
           current_view: nil,
           modified?: false,
           sort: :recent,
           search: "",
           items: [],
           view_counts: %{},
           kudos_counts: %{},
           total_count: 0,
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
    ws = socket.assigns.workspace

    current_view =
      case params["view_name"] do
        nil -> nil
        name -> Aveline.Views.get_current_by_name(ws.id, name)
      end

    if params["view_name"] && is_nil(current_view) do
      {:noreply,
       socket
       |> put_flash(:error, "View not found.")
       |> push_navigate(to: ~p"/w/#{ws.slug}/docs")}
    else
      config = (current_view && current_view.config) || %{}

      # Pristine view URL (no knob params): seed the knobs from the
      # saved config. Any knob param present = session state, taken
      # entirely from the URL. The saved view is never mutated from
      # here — screens deviate, agents save.
      pristine? =
        not Enum.any?(~w(tag author group sort q), &Map.has_key?(params, &1))

      {selected_tags, group_by, sort, selected_authors, search} =
        if pristine? do
          {Map.get(config, "tags", []), Map.get(config, "group_by"),
           parse_sort(Map.get(config, "sort")), [], ""}
        else
          {parse_tags(params["tag"]),
           parse_group(params["group"], ws.id),
           parse_sort(params["sort"]),
           parse_authors(params["author"], socket.assigns.workspace_authors),
           params["q"] || ""}
        end

      modified? =
        current_view != nil and
          (Enum.sort(selected_tags) != Enum.sort(Map.get(config, "tags", [])) or
             group_by != Map.get(config, "group_by") or
             sort != parse_sort(Map.get(config, "sort")) or
             selected_authors != [] or search != "")

      handle_docs_params(socket, current_view, selected_tags, group_by, sort, selected_authors, search, modified?)
    end
  end

  defp handle_docs_params(socket, current_view, selected_tags, group_by, sort, selected_authors, search, modified?) do
    ws = socket.assigns.workspace
    page_size = socket.assigns.page_size
    owner_ids = author_ids(selected_authors, socket.assigns.workspace_authors)

    # Fetch one extra row so we can tell whether more pages exist without
    # a separate COUNT(*).
    raw =
      Docs.list_current(ws.id,
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
       group_by: group_by,
       current_view: current_view,
       modified?: modified?,
       kanban: group_by && kanban_columns(ws.id, group_by, items),
       sort: sort,
       search: search,
       items: items,
       chip_counts: chip_counts,
       author_counts: author_counts,
       view_counts: DocViews.counts_by_base(base_ids),
       kudos_counts: Kudos.counts_by_base(base_ids),
       total_count: length(items),
       has_more?: has_more?,
       # On a view, the sidebar highlights that view's item; otherwise
       # Docs stays highlighted regardless of filter state.
       nav_active: if(current_view, do: {:view, current_view.name}, else: :all),
       topbar_title:
         cond do
           current_view -> current_view.name
           selected_tags == [] -> "Docs"
           true -> Enum.map_join(selected_tags, " · ", &"##{&1}")
         end
     )}
  end

  # Columns for the grouped (kanban) rendering: the scope's members in
  # tag order, each with its docs; docs carrying no tag from the scope
  # land in an unassigned column. Colors come from @tag_colors.
  defp kanban_columns(workspace_id, scope, items) do
    members = Tags.list_scope_members(workspace_id, scope)

    grouped =
      Enum.group_by(items, fn i -> Enum.find(members, &(&1 in i.tags)) end)

    %{
      scope: scope,
      columns: Enum.map(members, fn m -> {m, Map.get(grouped, m, [])} end),
      unassigned: Map.get(grouped, nil, [])
    }
  end

  # slug => custom color for every live tag that has one.
  defp tag_colors(workspace_id) do
    workspace_id
    |> Tags.list_for_workspace()
    |> Enum.reject(&is_nil(&1.color))
    |> Map.new(&{&1.slug, &1.color})
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

  # A group value is a tag scope with members in this workspace;
  # anything else means ungrouped.
  defp parse_group(nil, _ws), do: nil
  defp parse_group("", _ws), do: nil

  defp parse_group(s, ws_id) when is_binary(s) do
    if Tags.list_scope_members(ws_id, s) != [], do: s, else: nil
  end

  defp parse_group(_, _), do: nil

  defp parse_sort("kudos"), do: :kudos
  defp parse_sort("views"), do: :views
  defp parse_sort(_), do: :recent

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

  def handle_event("set_group", %{"group" => group}, socket) do
    group = if group in [nil, "", "none"], do: nil, else: group
    {:noreply, push_patch(socket, to: build_path(socket, %{group: group}))}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     push_patch(socket,
       to: build_path(socket, %{tag: [], author: [], group: nil, q: nil})
     )}
  end

  # Back to the saved view: the bare view URL re-seeds from config.
  def handle_event("reset_view", _params, socket) do
    view = socket.assigns.current_view
    {:noreply, push_patch(socket, to: ~p"/w/#{socket.assigns.workspace.slug}/v/#{view.name}")}
  end

  def handle_event("search", %{"value" => v}, socket) do
    {:noreply, push_patch(socket, to: build_path(socket, %{q: v}))}
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
      sort: sort,
      items: existing,
      page_size: page_size
    } = socket.assigns

    raw =
      Docs.list_current(ws.id,
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
       kanban: socket.assigns.group_by && kanban_columns(ws.id, socket.assigns.group_by, items),
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

  defp sort_to_param("recent"), do: nil
  defp sort_to_param(other), do: other

  defp build_path(socket, overrides) when is_map(overrides) do
    base = %{
      tag: socket.assigns.selected_tags,
      author: socket.assigns.selected_authors,
      group: socket.assigns.group_by,
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

    # Session state stays on the view URL when a view is open, so the
    # modified indicator and reset have something to deviate from.
    base_path =
      case socket.assigns.current_view do
        nil -> ~p"/w/#{socket.assigns.workspace.slug}/docs"
        view -> ~p"/w/#{socket.assigns.workspace.slug}/v/#{view.name}"
      end

    if query == [] do
      base_path
    else
      base_path <> "?" <> Plug.Conn.Query.encode(Map.new(query))
    end
  end

  defp maybe_append_list(query, _key, []), do: query
  defp maybe_append_list(query, key, list), do: query ++ [{key, list}]

  defp nz(""), do: nil
  defp nz(s), do: s

  defp sort_param(:kudos), do: "kudos"
  defp sort_param(:views), do: "views"
  defp sort_param(_), do: nil

  # ===== Filter dropdown machinery =====
  # LiveView-native dropdowns: JS.toggle shows the menu, phx-click-away
  # hides it, Escape hides it. LiveView tracks JS-command changes across
  # patches, so multi-select menus stay open while the list re-renders.

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :count, :integer, default: 0
  slot :inner_block, required: true

  defp fdd(assigns) do
    ~H"""
    <div
      class="fdd"
      id={@id}
      phx-click-away={JS.hide(to: "##{@id}-menu")}
      phx-window-keydown={JS.hide(to: "##{@id}-menu")}
      phx-key="escape"
    >
      <button
        type="button"
        class={"fdd-btn " <> if @count > 0, do: "fdd-btn-active", else: ""}
        phx-click={JS.toggle(to: "##{@id}-menu")}
      >
        {@label}
        <span :if={@count > 0} class="fdd-badge">{@count}</span>
        <svg class="fdd-chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <polyline points="6 9 12 15 18 9" />
        </svg>
      </button>
      <div class="fdd-menu" id={@id <> "-menu"} hidden>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # Plain tags first, then one section per scope (status, priority, …).
  defp grouped_tags(tags) do
    {plain, scoped} = Enum.split_with(tags, &is_nil(Tags.scope_of(&1)))

    grouped =
      scoped
      |> Enum.group_by(&Tags.scope_of/1)
      |> Enum.sort_by(&elem(&1, 0))

    {plain, grouped}
  end

  defp sort_label(:recent), do: "Recent"
  defp sort_label(:kudos), do: "Kudos"
  defp sort_label(:views), do: "Views"

  @impl true
  def render(assigns) do
    # All filtering — tags, authors, search (Postgres FTS) — happens
    # in SQL via Docs.list_current/2. The render just paints @items.
    assigns = assign(assigns, shown_items: assigns.items)

    ~H"""
    <div class="content">
      <div class="docs-head">
        <%= if @views == [] do %>
          <h1 class="page-title">Docs</h1>
        <% else %>
          <div
            class="title-fdd"
            id="fdd-view"
            phx-click-away={JS.hide(to: "#fdd-view-menu")}
            phx-window-keydown={JS.hide(to: "#fdd-view-menu")}
            phx-key="escape"
          >
            <h1 class="page-title">
              <button type="button" class="title-fdd-btn" phx-click={JS.toggle(to: "#fdd-view-menu")}>
                {if @current_view, do: @current_view.name, else: "Docs"}
                <svg class="title-chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
                  <polyline points="6 9 12 15 18 9" />
                </svg>
              </button>
            </h1>
            <div class="fdd-menu title-fdd-menu" id="fdd-view-menu" hidden>
              <.link patch={~p"/w/#{@workspace.slug}/docs"} class="vmenu-item">
                <span class={"fdd-check fdd-radio " <> if is_nil(@current_view), do: "on", else: ""}></span>
                <span class="vmenu-body">
                  <span class="vmenu-name">All docs</span>
                  <span class="vmenu-desc">Everything written in this workspace.</span>
                </span>
              </.link>
              <.link :for={v <- @views} patch={~p"/w/#{@workspace.slug}/v/#{v.name}"} class="vmenu-item">
                <span class={"fdd-check fdd-radio " <> if @current_view && @current_view.name == v.name, do: "on", else: ""}></span>
                <span class="vmenu-body">
                  <span class="vmenu-name">{v.name}</span>
                  <span class="vmenu-desc">{v.description}</span>
                </span>
              </.link>
            </div>
          </div>
        <% end %>
        <span :if={@modified?} class="view-modified">
          modified
          <button type="button" class="view-reset" phx-click="reset_view">reset</button>
        </span>
      </div>
      <p class="page-subtitle docs-subtitle">
        <%= if @current_view do %>
          {@current_view.description}
        <% else %>
          Everything written in <span class="mono">{@workspace.slug}</span>. Filter, search, sort, group.
        <% end %>
      </p>

      <div class="docs-controls">
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
      </div>

      <div class="fbar">
        <.fdd :if={@workspace_tags != []} id="fdd-tag" label="Tag" count={length(@selected_tags)}>
          <% {plain, scoped} = grouped_tags(@workspace_tags) %>
          <button
            :for={tag <- plain}
            type="button"
            class="fdd-item"
            phx-click="toggle_tag"
            phx-value-tag={tag}
          >
            <span class={"fdd-check " <> if tag in @selected_tags, do: "on", else: ""}></span>
            <span class="fdd-item-label">{tag}</span>
            <span class="fdd-item-count">{Map.get(@chip_counts, tag, 0)}</span>
          </button>
          <%= for {scope, values} <- scoped do %>
            <div class="fdd-section">{scope}</div>
            <button
              :for={tag <- values}
              type="button"
              class="fdd-item"
              phx-click="toggle_tag"
              phx-value-tag={tag}
            >
              <span class={"fdd-check " <> if tag in @selected_tags, do: "on", else: ""}></span>
              <span class="fdd-item-label">{Tags.value_of(tag)}</span>
              <span class="fdd-item-count">{Map.get(@chip_counts, tag, 0)}</span>
            </button>
          <% end %>
        </.fdd>

        <.fdd :if={@workspace_authors != []} id="fdd-author" label="Author" count={length(@selected_authors)}>
          <button
            :for={u <- @workspace_authors}
            type="button"
            class="fdd-item"
            phx-click="toggle_author"
            phx-value-author={u.username}
          >
            <span class={"fdd-check " <> if u.username in @selected_authors, do: "on", else: ""}></span>
            <span class="fdd-item-label">{u.username}</span>
            <span class="fdd-item-count">{Map.get(@author_counts, u.username, 0)}</span>
          </button>
        </.fdd>

        <.fdd
          id="fdd-group"
          label={if @group_by, do: "Group · " <> @group_by, else: "Group"}
          count={0}
        >
          <button
            type="button"
            class="fdd-item"
            phx-click={JS.hide(to: "#fdd-group-menu") |> JS.push("set_group", value: %{group: "none"})}
          >
            <span class={"fdd-check fdd-radio " <> if is_nil(@group_by), do: "on", else: ""}></span>
            <span class="fdd-item-label">None</span>
          </button>
          <button
            :for={scope <- workspace_scopes(@workspace_tags)}
            type="button"
            class="fdd-item"
            phx-click={JS.hide(to: "#fdd-group-menu") |> JS.push("set_group", value: %{group: scope})}
          >
            <span class={"fdd-check fdd-radio " <> if @group_by == scope, do: "on", else: ""}></span>
            <span class="fdd-item-label">{scope}</span>
          </button>
        </.fdd>

        <.fdd id="fdd-sort" label={"Sort · " <> sort_label(@sort)} count={0}>
          <button
            :for={{label, s} <- [{"Recent", :recent}, {"Kudos", :kudos}, {"Views", :views}]}
            type="button"
            class="fdd-item"
            phx-click={JS.hide(to: "#fdd-sort-menu") |> JS.push("set_sort", value: %{sort: Atom.to_string(s)})}
          >
            <span class={"fdd-check fdd-radio " <> if @sort == s, do: "on", else: ""}></span>
            <span class="fdd-item-label">{label}</span>
          </button>
        </.fdd>

        <button
          :if={is_nil(@current_view) and (@selected_tags != [] or @selected_authors != [] or @group_by != nil or @search != "")}
          type="button"
          class="fbar-clear"
          phx-click="clear_filters"
        >
          Clear all
        </button>
      </div>

      <div
        :if={@selected_tags != [] or @selected_authors != []}
        class="fpills"
      >
        <button
          :for={tag <- @selected_tags}
          type="button"
          class="fpill"
          phx-click="toggle_tag"
          phx-value-tag={tag}
          title="Remove filter"
        >
          {tag} <span class="fpill-x">×</span>
        </button>
        <button
          :for={a <- @selected_authors}
          type="button"
          class="fpill"
          phx-click="toggle_author"
          phx-value-author={a}
          title="Remove filter"
        >
          @{a} <span class="fpill-x">×</span>
        </button>
      </div>
      </div>

      <%= if @shown_items == [] do %>
        <div class="empty">No docs match the current filter.</div>
      <% else %>
        <%= if @group_by && @kanban do %>
          <div class="board docs-board">
            <div :for={{col, docs} <- @kanban.columns} class="board-col">
              <div class="board-col-head">
                <span
                  class="board-col-dot"
                  style={
                    if c = Map.get(@tag_colors, col) do
                      "background: " <> c
                    end
                  }
                >
                </span>
                <span class="board-col-name">{Tags.value_of(col)}</span>
                <span class="board-col-count">{length(docs)}</span>
              </div>
              <div class="board-col-cards">
                <.link :for={d <- docs} navigate={~p"/w/#{@workspace.slug}/d/#{d.slug}"} class="board-card">
                  <span class="board-card-title">{d.title}</span>
                  <span :if={d.owner} class="board-card-owner">{d.owner.username}</span>
                </.link>
              </div>
            </div>
            <div :if={@kanban.unassigned != []} class="board-col board-col-unassigned">
              <div class="board-col-head">
                <span class="board-col-dot"></span>
                <span class="board-col-name">no {@group_by}</span>
                <span class="board-col-count">{length(@kanban.unassigned)}</span>
              </div>
              <div class="board-col-cards">
                <.link
                  :for={d <- @kanban.unassigned}
                  navigate={~p"/w/#{@workspace.slug}/d/#{d.slug}"}
                  class="board-card"
                >
                  <span class="board-card-title">{d.title}</span>
                  <span :if={d.owner} class="board-card-owner">{d.owner.username}</span>
                </.link>
              </div>
            </div>
          </div>
          <%= if @has_more? do %>
            <div class="load-more-wrap">
              <button type="button" phx-click="load_more" class="load-more-btn">Load more</button>
            </div>
          <% end %>
        <% else %>
        <ul class="card-list">
          <li :for={i <- @shown_items}>
            <.link navigate={~p"/w/#{@workspace.slug}/d/#{i.slug}"} class="card">
              <div class="card-title">
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
                    <.tag :for={t <- i.tags} text={t} color={Map.get(@tag_colors, t)} />
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
      <% end %>
    </div>
    """
  end

  # Scopes (with members) present in this workspace's tags, in order.
  defp workspace_scopes(tags) do
    tags
    |> Enum.map(&Tags.scope_of/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end
end
