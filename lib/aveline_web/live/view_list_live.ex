defmodule AvelineWeb.ViewListLive do
  @moduledoc false
  use AvelineWeb, :live_view

  alias Aveline.Items
  alias Aveline.Views
  alias AvelineWeb.LiveSession

  @impl true
  def mount(%{"slug" => slug}, session, socket) do
    user = LiveSession.current_user(session)

    case LiveSession.fetch_workspace_for_user(slug, user) do
      {:ok, ws} ->
        views = Views.list_views(ws.id)
        items = Items.list_items(ws.id)

        match_counts =
          Map.new(views, fn v ->
            {v.id, Enum.count(items, &tags_match?(&1.tags, v.tag_filter))}
          end)

        {:ok,
         assign(socket,
           page_title: "Aveline · Views · #{ws.name}",
           current_user: user,
           workspace: ws,
           crumbs: [{:text, "Views"}],
           views: views,
           match_counts: match_counts,
           item_count: length(items)
         )}

      :not_found ->
        {:ok, socket |> put_flash(:error, "Workspace not found.") |> push_navigate(to: ~p"/")}

      :forbidden ->
        {:ok, socket |> put_flash(:error, "Forbidden.") |> push_navigate(to: ~p"/")}
    end
  end

  defp tags_match?(_item_tags, []), do: true
  defp tags_match?(item_tags, filter) when is_list(item_tags) and is_list(filter) do
    Enum.all?(filter, &(&1 in item_tags))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <h1 class="page-title">{@workspace.name}</h1>
      <p class="page-subtitle">
        <span class="mono">{@workspace.slug}</span>
        <span class="card-meta-dot">·</span>
        {@item_count} notes
      </p>

      <div class="tabs">
        <.link navigate={~p"/w/#{@workspace.slug}"} class="tab">
          All <span class="count">{@item_count}</span>
        </.link>
        <.link navigate={~p"/w/#{@workspace.slug}?pinned=true"} class="tab">
          Pinned
        </.link>
        <span class="tab tab-active">
          Views <span class="count">{length(@views)}</span>
        </span>
      </div>

      <%= if @views == [] do %>
        <div class="empty">
          No saved views yet. Create one with
          <code>aveline view create &lt;slug&gt; --tag &lt;tag&gt;</code>.
        </div>
      <% else %>
        <ul class="card-list">
          <li :for={v <- @views}>
            <.link navigate={~p"/w/#{@workspace.slug}/v/#{v.slug}"} class="card">
              <div class="card-title">{v.name}</div>
              <%= if v.description do %>
                <div class="card-summary">{v.description}</div>
              <% end %>
              <div class="card-meta">
                <span>{Map.get(@match_counts, v.id, 0)} matching</span>
                <span class="card-meta-dot">·</span>
                <%= if v.tag_filter != [] do %>
                  <span style="display:flex;gap:4px;flex-wrap:wrap">
                    <span :for={t <- v.tag_filter} class="chip chip-accent">{t}</span>
                  </span>
                <% else %>
                  <span>all notes</span>
                <% end %>
              </div>
            </.link>
          </li>
        </ul>
      <% end %>
    </div>
    """
  end
end
