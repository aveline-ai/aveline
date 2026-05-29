defmodule AvelineWeb.WorkspaceListLive do
  @moduledoc false
  use AvelineWeb, :live_view

  alias Aveline.Workspaces
  alias AvelineWeb.LiveSession

  @impl true
  def mount(_params, _session, socket) do
    user = LiveSession.current_user()

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
          Signed in as {@current_user.username}
        <% else %>
          No session.
        <% end %>
      </p>

      <%= if is_nil(@current_user) do %>
        <div style="padding:1rem;border:1px solid rgba(232,232,232,0.15);border-radius:8px;background:rgba(232,232,232,0.04)">
          No session user. In dev, set <code>SEED_USER_EMAIL</code> in the environment
          and run <code>mix aveline.seed</code> to bootstrap a user.
        </div>
      <% else %>
        <%= if @workspaces == [] do %>
          <p style="color:rgba(232,232,232,0.55)">No workspaces yet.</p>
        <% else %>
          <ul style="list-style:none;padding:0;margin:0;display:flex;flex-direction:column;gap:0.5rem">
            <li :for={w <- @workspaces}>
              <.link
                navigate={~p"/app/w/#{w.slug}"}
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
