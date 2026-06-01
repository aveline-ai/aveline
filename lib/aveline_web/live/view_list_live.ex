defmodule AvelineWeb.ViewListLive do
  @moduledoc false
  use AvelineWeb, :live_view

  alias Aveline.Docs
  alias Aveline.Views
  alias AvelineWeb.LiveSession

  @impl true
  def mount(%{"slug" => slug}, session, socket) do
    user = LiveSession.current_user(session)

    case LiveSession.fetch_workspace_for_user(slug, user) do
      {:ok, ws} ->
        visible = Views.list_visible_views(ws.id, user.id)
        items = Docs.list_current(ws.id)

        match_counts =
          Map.new(visible, fn v ->
            {v.id, Enum.count(items, &tags_match?(&1.tags, v.tag_filter))}
          end)

        {:ok,
         assign(socket,
           page_title: "Aveline · Views · #{ws.name}",
           current_user: user,
           workspace: ws,
           personal_views: Views.list_personal_views(ws.id, user.id),
           team_views: Views.list_team_views(ws.id),
           total_count: length(items),
           pinned_count: Enum.count(items, & &1.pinned),
           topbar_title: "Views",
           views: visible,
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
    <div class="content">
      <%= if @views == [] do %>
        <div class="empty">
          No saved views yet. Create one with
          <code>aveline view create &lt;slug&gt; --tag &lt;tag&gt;</code>.
        </div>
      <% else %>
        <ul class="card-list">
          <li :for={v <- @views}>
            <.link navigate={~p"/w/#{@workspace.slug}/v/#{v.slug}"} class="card">
              <div class="card-title">
                {v.name}
                <span
                  class={"chip " <> if v.scope == "team", do: "chip-accent", else: ""}
                  style="font-size:10px;height:18px;padding:0 6px;margin-left:4px"
                >
                  {v.scope}
                </span>
              </div>
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
                  <span>all docs</span>
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
