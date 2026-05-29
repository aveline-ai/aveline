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

            {:ok,
             assign(socket,
               page_title: "Aveline · #{item.title}",
               current_user: user,
               workspace: ws,
               item: item,
               body_html: body_html
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
        <div class="page-eyebrow">
          {@workspace.name} ·
          <span class="mono">{@item.slug}</span>
        </div>
        <h1 class="article-title">
          <%= if @item.pinned do %>
            <span class="pin" title="Pinned" style="margin-right:8px">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
                <path d="M12 2l2.39 7.36H22l-6.18 4.49L18.21 22 12 17.27 5.79 22l2.39-8.15L2 9.36h7.61z" />
              </svg>
            </span>
          <% end %>
          {@item.title}
        </h1>

        <%= if @item.summary && @item.summary != "" do %>
          <p class="article-summary">{@item.summary}</p>
        <% end %>

        <%= if @item.tags != [] do %>
          <div class="chip-row" style="margin-bottom:12px">
            <span :for={tag <- @item.tags} class="chip chip-accent">{tag}</span>
          </div>
        <% end %>

        <div class="article-meta">
          <%= if loaded_owner(@item) do %>
            <span class="article-meta-item">
              <span class="article-meta-key">Owner</span>
              <span class="article-meta-val">{loaded_owner(@item).username}</span>
            </span>
          <% end %>
          <span class="article-meta-item">
            <span class="article-meta-key">Created via</span>
            <span class="article-meta-val mono">{@item.created_via}</span>
          </span>
          <span class="article-meta-item">
            <span class="article-meta-key">Updated</span>
            <span class="article-meta-val">{format_date(@item.updated_at)}</span>
          </span>
        </div>
      </header>

      <article class="prose">
        {Phoenix.HTML.raw(@body_html)}
      </article>

      <div class="banner" style="margin-top:48px">
        Edit via the CLI: <code>aveline edit {@item.slug}</code>
      </div>
    </div>
    """
  end

  defp loaded_owner(%{owner: %Ecto.Association.NotLoaded{}}), do: nil
  defp loaded_owner(%{owner: owner}), do: owner
  defp loaded_owner(_), do: nil

  defp format_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %-d, %Y")
  end

  defp format_date(_), do: ""
end
