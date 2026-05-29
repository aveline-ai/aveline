defmodule AvelineWeb.Api.WorkspaceController do
  use AvelineWeb, :controller

  alias Aveline.Workspaces

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, _params) do
    workspaces = Workspaces.list_for_user(conn.assigns.current_user.id)

    conn
    |> put_view(json: AvelineWeb.Api.WorkspaceJSON)
    |> render(:index, %{workspaces: workspaces})
  end

  def show(conn, %{"slug" => slug}) do
    user = conn.assigns.current_user

    with %_{} = ws <- Workspaces.get_active_by_slug(slug) || {:error, :workspace_not_found},
         true <- Workspaces.member?(ws.id, user.id) || {:error, :forbidden} do
      conn
      |> put_view(json: AvelineWeb.Api.WorkspaceJSON)
      |> render(:show, %{workspace: ws})
    end
  end
end
