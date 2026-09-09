defmodule AvelineWeb.Api.MeController do
  @moduledoc """
  GET /api/me — who am I + workspaces I belong to. Logic lives in
  src/aveline/handlers/me.gleam.
  """
  use AvelineWeb, :controller

  import Aveline.Gleam.Interop, only: [unopt: 1]

  alias Aveline.Gleam.CtxBuilder
  alias AvelineWeb.Api.Envelope

  action_fallback AvelineWeb.Api.FallbackController

  def show(conn, _params) do
    user = conn.assigns.current_user

    {:me_response, me, workspaces} =
      :aveline@handlers@me.show(CtxBuilder.build(), {:actor, user.id, user.username})

    Envelope.ok(conn, %{
      user: user_map(me),
      workspaces: Enum.map(workspaces, &workspace_map/1)
    })
  end

  defp user_map({:user_info, id, username, display_name, email}) do
    %{id: id, username: username, display_name: unopt(display_name), email: unopt(email)}
  end

  defp workspace_map({:workspace_info, id, slug, name, created_at}) do
    %{id: id, slug: slug, name: name, created_at: created_at}
  end
end
