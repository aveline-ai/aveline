defmodule AvelineWeb.WelcomeLive do
  @moduledoc """
  The welcome page: /w/:slug/welcome. Joining flows land here (signup
  auto-login, invite accept) and the sidebar's Connect agent item is
  always the way back. A plain destination, no connected-state
  machinery: leaving is just clicking anything in the sidebar.
  """
  use AvelineWeb, :live_view

  alias Aveline.Docs
  alias Aveline.Workspaces
  alias AvelineWeb.LiveSession

  @impl true
  def mount(%{"slug" => slug}, session, socket) do
    user = LiveSession.current_user(session)

    case LiveSession.fetch_workspace_for_user(slug, user) do
      {:ok, ws} ->
        docs = Docs.list_current(ws.id, viewer: user.id, sort: :recent)
        # Template docs are scaffolding, not life: never backdrop material.
        backdrop = Enum.reject(docs, &("template" in (&1.tags || [])))

        {:ok,
         assign(socket,
           page_title: "Aveline · Welcome to #{ws.name}",
           current_user: user,
           workspace: ws,
           sidebar_workspaces: Workspaces.list_for_user(user.id),
           sidebar_views: Aveline.Views.sidebar_sections(ws.id, user.id),
           nav_active: :connect,
           topbar_title: "Welcome",
           setup_prompt: AvelineWeb.Setup.prompt(ws),
           orientation: Docs.get_orientation(ws.id),
           welcome_backdrop_docs: Enum.take(backdrop, 10),
           welcome_doc_count: length(docs),
           welcome_view_count:
             length(Aveline.Views.list_for_workspace(ws.id, viewer: user.id)),
           welcome_member_names:
             Workspaces.list_members(ws.id)
             |> Enum.map(& &1.user.username)
             |> Enum.reject(&(&1 == user.username))
             |> Enum.sort()
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
    <AvelineWeb.Setup.welcome
      id="welcome"
      workspace={@workspace}
      prompt={@setup_prompt}
      doc_count={@welcome_doc_count}
      view_count={@welcome_view_count}
      member_names={@welcome_member_names}
      orientation={@orientation}
      backdrop_docs={@welcome_backdrop_docs}
    />
    """
  end
end
