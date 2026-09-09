defmodule AvelineWeb.Api.QueryController do
  @moduledoc """
  The workspace query catalog — named, versioned queries built on data
  sources. Raw queries name an external `source` and run in its dialect;
  derived queries omit `source` and compose other catalog queries in the
  analytics dialect. Charts and ad-hoc runs consume them through the
  built-in `derived` data source.

  Thin adapter over the Gleam handlers in
  src/aveline/handlers/queries.gleam, which own validation (name rules,
  reference and cycle checks) with IO injected via CtxBuilder.
  """
  use AvelineWeb, :controller

  alias Aveline.Gleam.CtxBuilder
  alias Aveline.Gleam.Interop
  alias AvelineWeb.Api.Envelope
  alias AvelineWeb.Api.GleamAdapter

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, params) do
    {:ok, queries} =
      :aveline@handlers@queries.index(
        CtxBuilder.build(),
        CtxBuilder.scope(conn),
        Interop.opt(params["source"], &to_string/1)
      )

    Envelope.ok(conn, %{queries: Enum.map(queries, &query_map/1)})
  end

  def show(conn, %{"name" => name}) do
    :aveline@handlers@queries.show(CtxBuilder.build(), CtxBuilder.scope(conn), name)
    |> render_query(conn)
  end

  @doc """
  Create. Body: `name`, `sql`, optional `source` (a data source name;
  its presence makes the query raw, its absence derived).
  """
  def create(conn, params) do
    request =
      {:create_request, to_string(params["name"]), to_string(params["sql"]),
       Interop.opt(params["description"], &to_string/1),
       if(params["source"], do: {:some, to_string(params["source"])}, else: :none)}

    :aveline@handlers@queries.create(CtxBuilder.build(), CtxBuilder.scope(conn), request)
    |> render_query(conn)
  end

  @doc "Versioned edit. Body: any of `new_name`, `description`, `sql`."
  def update(conn, %{"name" => name} = params) do
    request =
      {:edit_request,
       if(params["new_name"], do: {:some, to_string(params["new_name"])}, else: :none),
       if(params["sql"], do: {:some, to_string(params["sql"])}, else: :none),
       if(Map.has_key?(params, "description"),
         do: {:some, Interop.opt(params["description"], &to_string/1)},
         else: :none
       )}

    :aveline@handlers@queries.update(CtxBuilder.build(), CtxBuilder.scope(conn), name, request)
    |> render_query(conn)
  end

  def delete(conn, %{"name" => name}) do
    case :aveline@handlers@queries.delete(CtxBuilder.build(), CtxBuilder.scope(conn), name) do
      {:ok, nil} -> Envelope.ok(conn, %{})
      {:error, err} -> GleamAdapter.error(err)
    end
  end

  def restore(conn, %{"name" => name}) do
    :aveline@handlers@queries.restore(CtxBuilder.build(), CtxBuilder.scope(conn), name)
    |> render_query(conn)
  end

  defp render_query(result, conn) do
    case result do
      {:ok, query} -> Envelope.ok(conn, %{query: query_map(query)})
      {:error, err} -> GleamAdapter.error(err)
    end
  end

  # The one shape read surfaces see (mirrors the legacy safe_map/1).
  defp query_map(
         {:query, _id, _base_query_id, version_number, name, description, kind, data_source_id,
          sql, deleted, created_at}
       ) do
    %{
      "name" => name,
      "description" => Interop.unopt(description),
      "kind" => Atom.to_string(kind),
      "data_source_id" => Interop.unopt(data_source_id),
      "sql" => sql,
      "version_number" => version_number,
      "deleted" => deleted,
      "created_at" => created_at
    }
  end
end
