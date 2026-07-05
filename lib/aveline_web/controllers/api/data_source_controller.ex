defmodule AvelineWeb.Api.DataSourceController do
  @moduledoc """
  Workspace data sources — external databases chart blocks query.

  The connection template (with a literal `<password>` placeholder) is
  public within the workspace and echoed on reads; the password arrives
  separately, is encrypted at rest, and has NO read path. Template
  changes require the password alongside (see `Aveline.DataSources`);
  password-only rotation and renames are fine alone.
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

    with {:ok, ds} <-
           DataSources.create(ws.id, name, params["url"], params["password"], user.id) do
      Envelope.ok(conn, %{data_source: DataSources.safe_map(ds)})
    end
  end

  @doc """
  Versioned edit. Body: any of `new_name`, `url` (template — requires
  `password` with it), `password`.
  """
  def update(conn, %{"name" => name} = params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    changes =
      %{}
      |> then(fn c -> if params["new_name"], do: Map.put(c, :name, params["new_name"]), else: c end)
      |> then(fn c -> if params["url"], do: Map.put(c, :url, params["url"]), else: c end)
      |> then(fn c ->
        if is_binary(params["password"]), do: Map.put(c, :password, params["password"]), else: c
      end)

    with %{} = ds <- DataSources.get_current_by_name(ws.id, name) || {:error, :not_found},
         {:ok, ds} <- DataSources.edit(ds, changes, user.id) do
      Envelope.ok(conn, %{data_source: DataSources.safe_map(ds)})
    end
  end

  @doc """
  Ad-hoc read-only query — the chart-authoring REPL. Same runner and
  safety posture as chart blocks (read-only session, single statement,
  5s timeout, 1000-row cap) but no cache: an agent iterating on SQL
  wants fresh results. Nothing is stored anywhere.
  """
  def query(conn, %{"name" => name} = params) do
    ws = conn.assigns.current_workspace
    query = params["query"]

    cond do
      not is_binary(query) or String.trim(query) == "" ->
        {:error, "query is required"}

      true ->
        with %{} = ds <- DataSources.get_current_by_name(ws.id, name) || {:error, :not_found} do
          case Aveline.DataSources.Runner.run(ds, query) do
            {:ok, result} -> Envelope.ok(conn, result)
            {:error, msg} -> {:error, :query_failed, msg}
          end
        end
    end
  end

  @doc """
  Soft-deletes the row for audit; hard-deletes the password in the
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
