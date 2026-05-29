defmodule AvelineWeb.ViewShowLive do
  @moduledoc false
  use AvelineWeb, :live_view

  alias Aveline.Views
  alias AvelineWeb.LiveSession

  @impl true
  def mount(%{"slug" => slug, "view_slug" => view_slug}, _session, socket) do
    user = LiveSession.current_user()

    case LiveSession.fetch_workspace_for_user(slug, user) do
      {:ok, ws} ->
        case Views.get_by_slug(ws.id, view_slug) do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, "View not found.")
             |> push_navigate(to: ~p"/app/w/#{ws.slug}/views")}

          view ->
            items = Views.matching_items(view)

            {:ok,
             assign(socket,
               page_title: "Aveline · View · #{view.name}",
               current_user: user,
               workspace: ws,
               view: view,
               items: items,
               pinned_only: false
             )}
        end

      :not_found ->
        {:ok, socket |> put_flash(:error, "Workspace not found.") |> push_navigate(to: ~p"/app")}

      :forbidden ->
        {:ok, socket |> put_flash(:error, "Forbidden.") |> push_navigate(to: ~p"/app")}
    end
  end

  @impl true
  def handle_event("toggle_pinned", _params, socket) do
    {:noreply, update(socket, :pinned_only, &(!&1))}
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :shown_items,
        if(assigns.pinned_only, do: Enum.filter(assigns.items, & &1.pinned), else: assigns.items)
      )

    ~H"""
    <div style="max-width:760px;margin:0 auto;padding:2rem 1rem">
      <.link
        navigate={~p"/app/w/#{@workspace.slug}/views"}
        style="color:rgba(232,232,232,0.55);font-size:0.85rem;text-decoration:none"
      >
        ← Views
      </.link>
      <h1 style="font-size:1.75rem;font-weight:600;margin:0.5rem 0 0.25rem">{@view.name}</h1>
      <p
        :if={@view.description && @view.description != ""}
        style="color:rgba(232,232,232,0.65);margin-bottom:0.75rem"
      >
        {@view.description}
      </p>
      <div style="display:flex;flex-wrap:wrap;gap:0.4rem;margin-bottom:1rem">
        <span :if={@view.tag_filter == []} style="font-size:0.85rem;color:rgba(232,232,232,0.55)">
          no filter (all items)
        </span>
        <span
          :for={tag <- @view.tag_filter}
          style="padding:0.15rem 0.55rem;border-radius:999px;border:1px solid rgba(232,232,232,0.15);font-size:0.75rem"
        >
          {tag}
        </span>
      </div>

      <label style="display:inline-flex;align-items:center;gap:0.4rem;margin-bottom:1rem;font-size:0.85rem;cursor:pointer">
        <input type="checkbox" checked={@pinned_only} phx-click="toggle_pinned" /> pinned only
      </label>

      <ul style="list-style:none;padding:0;margin:0;display:flex;flex-direction:column;gap:0.4rem">
        <li :for={i <- @shown_items}>
          <.link
            navigate={~p"/app/w/#{@workspace.slug}/i/#{i.slug}"}
            style="display:block;padding:0.6rem 0.85rem;border:1px solid rgba(232,232,232,0.1);border-radius:6px;color:inherit;text-decoration:none"
          >
            <div style="font-weight:500">
              <span :if={i.pinned}>📌</span> {i.title}
            </div>
            <div :if={i.tags != []} style="font-size:0.75rem;color:rgba(232,232,232,0.55);margin-top:0.15rem">
              {Enum.join(i.tags, " · ")}
            </div>
          </.link>
        </li>
      </ul>
      <p :if={@shown_items == []} style="color:rgba(232,232,232,0.55);margin-top:1rem">
        No matching items.
      </p>
    </div>
    """
  end
end
