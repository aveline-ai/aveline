defmodule AvelineWeb.WorkspaceListLive do
  @moduledoc false
  use AvelineWeb, :live_view

  alias Aveline.Workspaces
  alias AvelineWeb.LiveSession

  @impl true
  def mount(_params, session, socket) do
    user = LiveSession.current_user(session)

    workspaces =
      case user do
        nil -> []
        u -> Workspaces.list_for_user(u.id)
      end

    {:ok,
     assign(socket,
       page_title: "Aveline · Workspaces",
       current_user: user,
       workspaces: workspaces
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="max-width:700px;margin:0 auto;padding:2rem 1rem">
      <h1 style="font-size:1.75rem;font-weight:600;margin-bottom:0.25rem">Workspaces</h1>
      <p style="color:rgba(232,232,232,0.55);margin-bottom:1.5rem">
        <%= if @current_user do %>
          Signed in as {@current_user.username} · <.link href={~p"/logout"} style="color:inherit;text-decoration:underline">log out</.link>
        <% else %>
          Not signed in.
        <% end %>
      </p>

      <%= if is_nil(@current_user) do %>
        <div style="padding:1rem;border:1px solid rgba(232,232,232,0.15);border-radius:8px;background:rgba(232,232,232,0.04)">
          Visit <code>/login/&lt;your-token&gt;</code> to sign in. Local tokens
          are printed by <code>mix ecto.setup</code>.
        </div>
      <% else %>
        <%= if @workspaces == [] do %>
          <p style="color:rgba(232,232,232,0.55)">No workspaces yet.</p>
        <% else %>
          <ul style="list-style:none;padding:0;margin:0;display:flex;flex-direction:column;gap:0.5rem">
            <li :for={w <- @workspaces}>
              <.link
                navigate={~p"/w/#{w.slug}"}
                style="display:block;padding:0.85rem 1rem;border:1px solid rgba(232,232,232,0.15);border-radius:8px;color:inherit;text-decoration:none"
              >
                <div style="font-weight:500">{w.name}</div>
                <div style="font-size:0.8rem;color:rgba(232,232,232,0.55)">{w.slug}</div>
              </.link>
            </li>
          </ul>
        <% end %>
      <% end %>
    </div>
    """
  end
end
