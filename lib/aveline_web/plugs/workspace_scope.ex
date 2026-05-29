defmodule AvelineWeb.Plugs.WorkspaceScope do
  @moduledoc """
  Resolves `:workspace_slug` path param to a workspace and verifies that the
  current user is a member. Assigns `:current_workspace`. Returns 404 with
  `workspace_not_found` or 403 with `forbidden` on failure.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [put_view: 2, render: 3]

  alias Aveline.Workspaces
  alias AvelineWeb.Api.ErrorJSON

  def init(opts), do: opts

  def call(conn, _opts) do
    slug = conn.path_params["workspace_slug"]
    user = conn.assigns[:current_user]

    cond do
      is_nil(user) ->
        error(conn, 401, "unauthorized", "Missing or invalid bearer token.")

      is_nil(slug) ->
        error(conn, 404, "workspace_not_found", "Workspace not found.")

      true ->
        case Workspaces.get_active_by_slug(slug) do
          nil ->
            error(conn, 404, "workspace_not_found", "Workspace not found.")

          workspace ->
            if Workspaces.member?(workspace.id, user.id) do
              assign(conn, :current_workspace, workspace)
            else
              error(conn, 403, "forbidden", "You don't have access to this workspace.")
            end
        end
    end
  end

  defp error(conn, status, code, message) do
    conn
    |> put_status(status)
    |> put_view(json: ErrorJSON)
    |> render(:error, %{code: code, message: message})
    |> halt()
  end
end
