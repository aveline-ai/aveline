defmodule AvelineWeb.Api.WorkspaceController do
  @moduledoc """
  Workspace-level reads. Workspace *creation* lives in `/api/workspaces`
  POST (handled here too) so the CLI can do "create my first
  workspace" end-to-end without going through the web onboarding.

  All decisions live in src/aveline/handlers/workspaces.gleam; this
  module only coerces params and renders the typed results.
  """
  use AvelineWeb, :controller

  alias Aveline.Gleam.CtxBuilder
  alias AvelineWeb.Api.Envelope
  alias AvelineWeb.Api.GleamAdapter

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, _params) do
    workspaces = :aveline@handlers@workspaces.index(CtxBuilder.build(), actor(conn))
    Envelope.ok(conn, %{workspaces: Enum.map(workspaces, &workspace_map/1)})
  end

  def show(conn, %{"slug" => slug}) do
    case :aveline@handlers@workspaces.show(CtxBuilder.build(), actor(conn), slug) do
      {:ok, ws} -> Envelope.ok(conn, %{workspace: workspace_map(ws)})
      {:error, err} -> GleamAdapter.error(err)
    end
  end

  def create(conn, params) do
    request = {:create_request, opt_binary(params["name"]), slug_param(params["slug"])}

    case :aveline@handlers@workspaces.create(CtxBuilder.build(), actor(conn), request) do
      {:ok, ws} -> Envelope.ok(conn, %{workspace: workspace_map(ws)})
      {:error, err} -> GleamAdapter.error(err)
    end
  end

  # These endpoints are not workspace-scoped; the handler takes the bare Actor.
  defp actor(conn) do
    user = conn.assigns.current_user
    {:actor, user.id, user.username}
  end

  defp opt_binary(v) when is_binary(v), do: {:some, v}
  defp opt_binary(_), do: :none

  # An omitted slug derives from the name (Gleam-side); a given one is
  # coerced to a string as before the port.
  defp slug_param(nil), do: :none
  defp slug_param(false), do: :none
  defp slug_param(v), do: {:some, to_string(v)}

  defp workspace_map({:workspace_info, id, slug, name, created_at}) do
    %{id: id, slug: slug, name: name, created_at: created_at}
  end
end
