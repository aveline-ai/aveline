defmodule AvelineWeb.WelcomeLive do
  @moduledoc """
  The vestibule as a place, not a state: /w/:slug/welcome. The two
  joining flows land here once (signup auto-login, invite accept) and
  the sidebar's Connect-your-agent CTA is the way back. Leaving is
  just clicking anything in the sidebar; already-connected members are
  bounced home.
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
        if Aveline.Onboarding.agent_connected?(ws.id, user.id) do
          {:ok, push_navigate(socket, to: ~p"/w/#{ws.slug}")}
        else
          if connected?(socket), do: Process.send_after(self(), :check_setup, 2_000)

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
             agent_connected?: false,
             nav_active: :connect,
             topbar_title: "Welcome",
             setup_done: false,
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
        end

      :not_found ->
        {:ok, socket |> put_flash(:error, "Workspace not found.") |> push_navigate(to: ~p"/")}

      :forbidden ->
        {:ok, socket |> put_flash(:error, "Forbidden.") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("enter_home", _, socket) do
    {:noreply, push_navigate(socket, to: ~p"/w/#{socket.assigns.workspace.slug}")}
  end

  @impl true
  def handle_info(:check_setup, socket) do
    %{workspace: ws, current_user: user} = socket.assigns

    if Aveline.Onboarding.agent_connected?(ws.id, user.id) do
      {:noreply, assign(socket, setup_done: true)}
    else
      Process.send_after(self(), :check_setup, 2_000)
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AvelineWeb.Setup.welcome
      id="welcome"
      workspace={@workspace}
      prompt={@setup_prompt}
      setup_done={@setup_done}
      doc_count={@welcome_doc_count}
      view_count={@welcome_view_count}
      member_names={@welcome_member_names}
      orientation={@orientation}
      backdrop_docs={@welcome_backdrop_docs}
    />
    """
  end
end
