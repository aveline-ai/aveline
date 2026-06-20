defmodule AvelineWeb.Api.WorkspaceController do
  @moduledoc """
  Workspace-level reads. Workspace *creation* lives in `/api/workspaces`
  POST (handled here too) so the CLI can do "create my first
  workspace" end-to-end without going through the web onboarding.
  """
  use AvelineWeb, :controller

  alias Aveline.Workspaces
  alias AvelineWeb.Api.Envelope
  alias AvelineWeb.Api.Views

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, _params) do
    workspaces = Workspaces.list_for_user(conn.assigns.current_user.id)
    Envelope.ok(conn, %{workspaces: Enum.map(workspaces, &Views.workspace/1)})
  end

  def show(conn, %{"slug" => slug}) do
    user = conn.assigns.current_user

    with %_{} = ws <- Workspaces.get_active_by_slug(slug) || {:error, :workspace_not_found},
         true <- Workspaces.member?(ws.id, user.id) || {:error, :forbidden} do
      Envelope.ok(conn, %{workspace: Views.workspace(ws)})
    end
  end

  def create(conn, params) do
    user = conn.assigns.current_user

    attrs = %{
      "name" => params["name"],
      "slug" => params["slug"],
      "created_by_id" => user.id
    }

    with {:ok, ws} <- Workspaces.create_workspace(attrs),
         {:ok, _} <- Workspaces.ensure_member(ws.id, user.id) do
      Envelope.ok(conn, %{workspace: Views.workspace(ws)})
    end
  end
end
