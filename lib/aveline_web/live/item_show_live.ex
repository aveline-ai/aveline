defmodule AvelineWeb.ItemShowLive do
  @moduledoc false
  use AvelineWeb, :live_view

  alias Aveline.Items
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
            body_html = render_markdown(item.body || "")
            related = Items.related_items(item, 5)

            {:ok,
             assign(socket,
               page_title: "Aveline · #{item.title}",
               current_user: user,
               workspace: ws,
               crumbs: [{:text, item.title}],
               item: item,
               body_html: body_html,
               related: related
             )}
        end

      :not_found ->
        {:ok, socket |> put_flash(:error, "Workspace not found.") |> push_navigate(to: ~p"/")}

      :forbidden ->
        {:ok, socket |> put_flash(:error, "Forbidden.") |> push_navigate(to: ~p"/")}
    end
  end

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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container-narrow">
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
    """
  end
end
