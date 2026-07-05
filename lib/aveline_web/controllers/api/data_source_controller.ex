defmodule AvelineWeb.Api.DataSourceController do
  @moduledoc """
  Workspace data sources — external databases chart blocks query.

  The connection URL is write-only: it arrives on create, is encrypted
  at rest, and every response echoes only name/adapter/host/database.
  The adapter is derived from the URL scheme (postgres:// or mysql://).
  """
  use AvelineWeb, :controller

  alias Aveline.DataSources
  alias AvelineWeb.Api.Envelope

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, _params) do
    ws = conn.assigns.current_workspace

    Envelope.ok(conn, %{
      data_sources: ws.id |> DataSources.list_for_workspace() |> Enum.map(&DataSources.safe_map/1)
    })
  end

  def create(conn, params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user
    name = params["name"] |> to_string() |> String.trim() |> String.downcase()

    with {:ok, ds} <- DataSources.create(ws.id, name, params["url"], user.id) do
      Envelope.ok(conn, %{data_source: DataSources.safe_map(ds)})
    end
  end

  @doc """
  Soft-deletes the row for audit; hard-deletes the credential in the
  same update. Irreversible by design — connect a new source instead.
  """
  def delete(conn, %{"name" => name}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with %{} = ds <- DataSources.get_current_by_name(ws.id, name) || {:error, :not_found},
         {:ok, _} <- DataSources.delete(ds, user.id) do
      Envelope.ok(conn, %{})
    end
  end
end
