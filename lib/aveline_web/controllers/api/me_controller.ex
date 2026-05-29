defmodule AvelineWeb.Api.MeController do
  use AvelineWeb, :controller

  alias Aveline.Workspaces

  action_fallback AvelineWeb.Api.FallbackController

  def show(conn, _params) do
    user = conn.assigns.current_user
    workspaces = Workspaces.list_for_user(user.id)

    conn
    |> put_view(json: AvelineWeb.Api.MeJSON)
    |> render(:show, %{user: user, workspaces: workspaces})
  end
end
