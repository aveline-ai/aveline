defmodule AvelineWeb.Api.QueryController do
  @moduledoc """
  The workspace query catalog — named, versioned queries built on data
  sources. Raw queries name an external `source` and run in its dialect;
  derived queries omit `source` and compose other catalog queries in the
  analytics dialect. Charts and ad-hoc runs consume them through the
  built-in `derived` data source.

  Thin adapter over `Aveline.DataSources.Queries`, like every other
  controller — the context owns validation (name rules, reference and
  cycle checks).
  """
  use AvelineWeb, :controller

  alias Aveline.DataSources
  alias Aveline.DataSources.Queries
  alias AvelineWeb.Api.Envelope

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, params) do
    ws = conn.assigns.current_workspace

    queries =
      case params["source"] do
        nil ->
          Queries.list_for_workspace(ws.id)

        source_name ->
          case DataSources.get_current_by_name(ws.id, source_name) do
            nil -> []
            source -> Queries.list_for_source(ws.id, source.base_data_source_id)
          end
      end

    Envelope.ok(conn, %{queries: Enum.map(queries, &Queries.safe_map/1)})
  end

  def show(conn, %{"name" => name}) do
    ws = conn.assigns.current_workspace

    case Queries.get_current_by_name(ws.id, name) do
      nil -> {:error, :not_found}
      query -> Envelope.ok(conn, %{query: Queries.safe_map(query)})
    end
  end

  @doc """
  Create. Body: `name`, `sql`, optional `source` (a data source name;
  its presence makes the query raw, its absence derived).
  """
  def create(conn, params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    attrs =
      %{name: params["name"], sql: params["sql"]}
      |> then(fn a -> if params["source"], do: Map.put(a, :source, params["source"]), else: a end)

    with {:ok, query} <- Queries.create(ws.id, attrs, user.id) do
      Envelope.ok(conn, %{query: Queries.safe_map(query)})
    end
  end

  @doc "Versioned edit. Body: any of `new_name`, `sql`."
  def update(conn, %{"name" => name} = params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    changes =
      %{}
      |> then(fn c -> if params["new_name"], do: Map.put(c, :name, params["new_name"]), else: c end)
      |> then(fn c -> if params["sql"], do: Map.put(c, :sql, params["sql"]), else: c end)

    with %{} = query <- Queries.get_current_by_name(ws.id, name) || {:error, :not_found},
         {:ok, updated} <- Queries.edit(query, changes, user.id) do
      Envelope.ok(conn, %{query: Queries.safe_map(updated)})
    end
  end

  def delete(conn, %{"name" => name}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with %{} = query <- Queries.get_current_by_name(ws.id, name) || {:error, :not_found},
         {:ok, _} <- Queries.delete(query, user.id) do
      Envelope.ok(conn, %{})
    end
  end

  def restore(conn, %{"name" => name}) do
    ws = conn.assigns.current_workspace

    with %{} = query <- Queries.get_latest_deleted_by_name(ws.id, name) || {:error, :not_found},
         {:ok, restored} <- Queries.restore(query) do
      Envelope.ok(conn, %{query: Queries.safe_map(restored)})
    end
  end
end
