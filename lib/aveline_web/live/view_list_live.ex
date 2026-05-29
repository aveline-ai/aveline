defmodule AvelineWeb.ViewListLive do
  @moduledoc false
  use AvelineWeb, :live_view

  alias Aveline.Views
  alias AvelineWeb.LiveSession

  @impl true
  def mount(%{"slug" => slug}, session, socket) do
    user = LiveSession.current_user(session)

    case LiveSession.fetch_workspace_for_user(slug, user) do
      {:ok, ws} ->
        {:ok,
         assign(socket,
           page_title: "Aveline · Views · #{ws.name}",
           current_user: user,
           workspace: ws,
           views: Views.list_views(ws.id)
         )}

      :not_found ->
        {:ok, socket |> put_flash(:error, "Workspace not found.") |> push_navigate(to: ~p"/")}

      :forbidden ->
        {:ok, socket |> put_flash(:error, "Forbidden.") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="max-width:760px;margin:0 auto;padding:2rem 1rem">
      <.link
        navigate={~p"/w/#{@workspace.slug}"}
        style="color:rgba(232,232,232,0.55);font-size:0.85rem;text-decoration:none"
      >
        ← {@workspace.name}
      </.link>
      <h1 style="font-size:1.75rem;font-weight:600;margin:0.5rem 0 1rem">Views</h1>

      <%= if @views == [] do %>
        <p style="color:rgba(232,232,232,0.55)">No saved views yet.</p>
      <% else %>
        <ul style="list-style:none;padding:0;margin:0;display:flex;flex-direction:column;gap:0.5rem">
          <li :for={v <- @views}>
            <.link
              navigate={~p"/w/#{@workspace.slug}/v/#{v.slug}"}
              style="display:block;padding:0.85rem 1rem;border:1px solid rgba(232,232,232,0.15);border-radius:8px;color:inherit;text-decoration:none"
            >
              <div style="font-weight:500">{v.name}</div>
              <div style="font-size:0.8rem;color:rgba(232,232,232,0.55);margin-top:0.2rem">
                {if v.tag_filter == [], do: "all items", else: Enum.join(v.tag_filter, " ∩ ")}
              </div>
            </.link>
          </li>
        </ul>
      <% end %>
    </div>
    """
  end
end
