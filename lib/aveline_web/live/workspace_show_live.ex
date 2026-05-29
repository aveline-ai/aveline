defmodule AvelineWeb.WorkspaceShowLive do
  @moduledoc false
  use AvelineWeb, :live_view

  alias Aveline.Items
  alias AvelineWeb.LiveSession

  @impl true
  def mount(%{"slug" => slug}, session, socket) do
    user = LiveSession.current_user(session)

    case LiveSession.fetch_workspace_for_user(slug, user) do
      {:ok, ws} ->
        items = Items.list_items(ws.id)
        pinned = Enum.filter(items, & &1.pinned)

        tag_counts =
          items
          |> Enum.flat_map(& &1.tags)
          |> Enum.frequencies()
          |> Enum.sort_by(fn {_t, c} -> -c end)

        {:ok,
         assign(socket,
           page_title: "Aveline · #{ws.name}",
           current_user: user,
           workspace: ws,
           items: items,
           pinned: pinned,
           tag_counts: tag_counts,
           selected_tag: nil,
           search: ""
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
  def handle_event("set_tag", %{"tag" => tag}, socket) do
    new_tag = if socket.assigns.selected_tag == tag, do: nil, else: tag
    {:noreply, assign(socket, :selected_tag, new_tag)}
  end

  def handle_event("search", %{"value" => v}, socket) do
    {:noreply, assign(socket, :search, v)}
  end

  defp filtered(items, tag, search) do
    items
    |> Enum.filter(fn i -> is_nil(tag) or tag in i.tags end)
    |> Enum.filter(fn i ->
      case String.trim(search || "") do
        "" -> true
        s -> String.contains?(String.downcase(i.title), String.downcase(s))
      end
    end)
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns, :filtered_items, filtered(assigns.items, assigns.selected_tag, assigns.search))

    ~H"""
    <div style="max-width:760px;margin:0 auto;padding:2rem 1rem">
      <.link
        navigate={~p"/"}
        style="color:rgba(232,232,232,0.55);font-size:0.85rem;text-decoration:none"
      >
        ← All workspaces
      </.link>
      <h1 style="font-size:1.75rem;font-weight:600;margin:0.5rem 0 0.25rem">{@workspace.name}</h1>
      <div style="display:flex;gap:1rem;color:rgba(232,232,232,0.55);font-size:0.85rem;margin-bottom:1.5rem">
        <span>{@workspace.slug}</span>
        <.link navigate={~p"/w/#{@workspace.slug}/views"} style="color:inherit">
          views
        </.link>
      </div>

      <%= if @pinned != [] do %>
        <h2 style="font-size:0.75rem;font-weight:600;text-transform:uppercase;letter-spacing:0.08em;color:rgba(232,232,232,0.55);margin:0 0 0.5rem">
          Pinned
        </h2>
        <ul style="list-style:none;padding:0;margin:0 0 1.5rem;display:flex;flex-direction:column;gap:0.4rem">
          <li :for={i <- @pinned}>
            <.link
              navigate={~p"/w/#{@workspace.slug}/i/#{i.slug}"}
              style="display:block;padding:0.6rem 0.85rem;border:1px solid rgba(232,232,232,0.15);border-radius:6px;color:inherit;text-decoration:none"
            >
              {i.title}
            </.link>
          </li>
        </ul>
      <% end %>

      <form phx-change="search" style="margin-bottom:1rem">
        <input
          type="text"
          name="value"
          value={@search}
          placeholder="search titles…"
          style="width:100%;padding:0.55rem 0.75rem;border-radius:6px;border:1px solid rgba(232,232,232,0.15);background:rgba(232,232,232,0.04);color:#f5f5f5;font-family:inherit"
        />
      </form>

      <%= if @tag_counts != [] do %>
        <div style="display:flex;flex-wrap:wrap;gap:0.4rem;margin-bottom:1rem">
          <button
            :for={{tag, count} <- @tag_counts}
            phx-click="set_tag"
            phx-value-tag={tag}
            style={"padding:0.25rem 0.6rem;border-radius:999px;border:1px solid rgba(232,232,232,0.15);background:#{if @selected_tag == tag, do: "rgba(245,245,245,0.15)", else: "transparent"};color:inherit;font-family:inherit;font-size:0.8rem;cursor:pointer"}
          >
            {tag} <span style="opacity:0.55">({count})</span>
          </button>
        </div>
      <% end %>

      <ul style="list-style:none;padding:0;margin:0;display:flex;flex-direction:column;gap:0.4rem">
        <li :for={i <- @filtered_items}>
          <.link
            navigate={~p"/w/#{@workspace.slug}/i/#{i.slug}"}
            style="display:block;padding:0.6rem 0.85rem;border:1px solid rgba(232,232,232,0.1);border-radius:6px;color:inherit;text-decoration:none"
          >
            <div style="font-weight:500">{i.title}</div>
            <div :if={i.tags != []} style="font-size:0.75rem;color:rgba(232,232,232,0.55);margin-top:0.15rem">
              {Enum.join(i.tags, " · ")}
            </div>
          </.link>
        </li>
      </ul>
      <p :if={@filtered_items == []} style="color:rgba(232,232,232,0.55);margin-top:1rem">
        No items match.
      </p>
    </div>
    """
  end
end
