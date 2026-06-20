defmodule AvelineWeb.Api.MeController do
  @moduledoc """
  GET /api/me — who am I + workspaces I belong to.
  """
  use AvelineWeb, :controller

  alias Aveline.Workspaces
  alias AvelineWeb.Api.Envelope
  alias AvelineWeb.Api.Views

  action_fallback AvelineWeb.Api.FallbackController

  def show(conn, _params) do
    user = conn.assigns.current_user
    workspaces = Workspaces.list_for_user(user.id)

    Envelope.ok(conn, %{
      user: Views.user(user),
      workspaces: Enum.map(workspaces, &Views.workspace/1)
    })
  end
end
