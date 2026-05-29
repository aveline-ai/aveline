defmodule AvelineWeb.ItemShowLive do
  @moduledoc false
  use AvelineWeb, :live_view

  alias Aveline.Items
  alias AvelineWeb.LiveSession

  @impl true
  def mount(%{"slug" => slug, "item_slug" => item_slug}, _session, socket) do
    user = LiveSession.current_user()

    case LiveSession.fetch_workspace_for_user(slug, user) do
      {:ok, ws} ->
        case Items.get_by_slug(ws.id, item_slug) do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, "Item not found.")
             |> push_navigate(to: ~p"/app/w/#{ws.slug}")}

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
        {:ok, socket |> put_flash(:error, "Workspace not found.") |> push_navigate(to: ~p"/app")}

      :forbidden ->
        {:ok, socket |> put_flash(:error, "Forbidden.") |> push_navigate(to: ~p"/app")}
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
    <div style="max-width:760px;margin:0 auto;padding:2rem 1rem">
      <.link
        navigate={~p"/app/w/#{@workspace.slug}"}
        style="color:rgba(232,232,232,0.55);font-size:0.85rem;text-decoration:none"
      >
        ← {@workspace.name}
      </.link>

      <%= if @item.deleted_at do %>
        <div style="margin:1rem 0;padding:0.75rem 1rem;border:1px solid rgba(255,130,130,0.3);background:rgba(255,130,130,0.06);border-radius:6px;font-size:0.85rem;color:rgba(255,180,180,0.95)">
          This item is deleted. URL preserved for archive purposes.
        </div>
      <% end %>

      <h1 style="font-size:2rem;font-weight:600;margin:0.5rem 0 0.25rem">
        {@item.title}
      </h1>

      <div style="display:flex;gap:1rem;flex-wrap:wrap;color:rgba(232,232,232,0.55);font-size:0.85rem;margin-bottom:1rem">
        <span :if={@item.pinned}>📌 pinned</span>
        <span :if={loaded_owner(@item)}>owner: {loaded_owner(@item).username}</span>
        <span>via: {@item.created_via}</span>
      </div>

      <div :if={@item.tags != []} style="display:flex;flex-wrap:wrap;gap:0.4rem;margin-bottom:1.5rem">
        <span
          :for={tag <- @item.tags}
          style="padding:0.15rem 0.55rem;border-radius:999px;border:1px solid rgba(232,232,232,0.15);font-size:0.75rem"
        >
          {tag}
        </span>
      </div>

      <div :if={@item.summary && @item.summary != ""} style="font-style:italic;color:rgba(232,232,232,0.75);margin-bottom:1.5rem">
        {@item.summary}
      </div>

      <div style="line-height:1.6">
        {Phoenix.HTML.raw(@body_html)}
      </div>

      <p style="margin-top:2.5rem;padding:0.85rem 1rem;border:1px dashed rgba(232,232,232,0.15);border-radius:6px;font-size:0.85rem;color:rgba(232,232,232,0.55)">
        To edit this item, use the <code>aveline</code> CLI:
        <code>aveline edit {@item.slug}</code>.
      </p>
    </div>
    """
  end

  defp loaded_owner(%{owner: %Ecto.Association.NotLoaded{}}), do: nil
  defp loaded_owner(%{owner: owner}), do: owner
  defp loaded_owner(_), do: nil
end
