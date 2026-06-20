defmodule AvelineWeb.Plugs.WorkspaceScope do
  @moduledoc """
  Resolves `:workspace_slug` path param to a workspace and verifies that the
  current user is a member. Assigns `:current_workspace`. Returns the
  canonical API envelope on failure.
  """
  import Plug.Conn

  alias Aveline.Workspaces
  alias AvelineWeb.Api.Envelope

  def init(opts), do: opts

  def call(conn, _opts) do
    slug = conn.path_params["workspace_slug"]
    user = conn.assigns[:current_user]

    cond do
      is_nil(user) ->
        halt_err(conn, 401, "unauthorized", "Missing or invalid bearer token.")

      is_nil(slug) ->
        halt_err(conn, 404, "workspace_not_found", "Workspace not found.")

      true ->
        case Workspaces.get_active_by_slug(slug) do
          nil ->
            halt_err(conn, 404, "workspace_not_found", "Workspace not found.")

          workspace ->
            if Workspaces.member?(workspace.id, user.id) do
              assign(conn, :current_workspace, workspace)
            else
              halt_err(conn, 403, "forbidden", "You don't have access to this workspace.")
            end
        end
    end
  end

  defp halt_err(conn, status, code, message) do
    conn
    |> Envelope.err(status, code, message)
    |> halt()
  end
end
