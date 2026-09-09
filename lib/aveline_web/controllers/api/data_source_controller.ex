defmodule AvelineWeb.Api.DataSourceController do
  @moduledoc """
  Workspace data sources — external databases chart blocks query.

  The connection template (with a literal `<password>` placeholder) is
  public within the workspace and echoed on reads; the password arrives
  separately, is encrypted at rest, and has NO read path. Template
  changes require the password alongside (see `Aveline.DataSources`);
  password-only rotation and renames are fine alone.

  All decisions live in src/aveline/handlers/data_sources.gleam; this
  module only coerces params and renders the typed results. The password
  crosses Gleam as an opaque `Secret` — only the cap closures ever look
  inside.
  """
  use AvelineWeb, :controller

  alias Aveline.Gleam.CtxBuilder
  alias AvelineWeb.Api.Envelope
  alias AvelineWeb.Api.GleamAdapter

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, _params) do
    sources = :aveline@handlers@data_sources.index(CtxBuilder.build(), CtxBuilder.scope(conn))
    Envelope.ok(conn, %{data_sources: Enum.map(sources, &ds_map/1)})
  end

  def create(conn, params) do
    request =
      {:create_request, to_string(params["name"]), opt_binary(params["url"]),
       opt_binary(params["password"])}

    case :aveline@handlers@data_sources.create(
           CtxBuilder.build(),
           CtxBuilder.scope(conn),
           request
         ) do
      {:ok, ds} -> Envelope.ok(conn, %{data_source: ds_map(ds)})
      {:error, err} -> GleamAdapter.error(err)
    end
  end

  @doc """
  Versioned edit. Body: any of `new_name`, `url` (template — requires
  `password` with it), `password`.
  """
  def update(conn, %{"name" => name} = params) do
    request =
      {:update_request, opt_binary(params["new_name"]), opt_binary(params["url"]),
       opt_binary(params["password"])}

    case :aveline@handlers@data_sources.update(
           CtxBuilder.build(),
           CtxBuilder.scope(conn),
           name,
           request
         ) do
      {:ok, ds} -> Envelope.ok(conn, %{data_source: ds_map(ds)})
      {:error, err} -> GleamAdapter.error(err)
    end
  end

  @doc """
  Ad-hoc read-only query — the chart-authoring REPL. Same runner and
  safety posture as chart blocks (read-only session, single statement,
  5s timeout, 1000-row cap) but no cache: an agent iterating on SQL
  wants fresh results. Nothing is stored anywhere.
  """
  def query(conn, %{"name" => name} = params) do
    case :aveline@handlers@data_sources.query(
           CtxBuilder.build(),
           CtxBuilder.scope(conn),
           name,
           opt_binary(params["query"])
         ) do
      # The result is the runner's free-form columns/rows map, echoed
      # verbatim (it crosses Gleam opaquely).
      {:ok, result} -> Envelope.ok(conn, result)
      {:error, err} -> GleamAdapter.error(err)
    end
  end

  @doc """
  One-shot bootstrap for the SPA Data sources page — everything
  DataSourcesLive computes at mount, precomputed server-side because it
  needs server code (doc blocks for chart usage, the analytics engine
  for derived-query lineage): all current sources incl. soft-deleted,
  the query catalog with per-query chart usage and upstream refs, and
  active milestones for the timeline strip.
  """
  def overview(conn, _params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    sources = Aveline.DataSources.list_all_for_workspace(ws.id)

    queries =
      ws.id
      |> Aveline.DataSources.Queries.list_for_workspace()
      |> Aveline.Repo.preload(:created_by)
      |> Enum.sort_by(& &1.name)

    {chart_counts, charted_in} = chart_index(ws.id, user.id)
    built_on = built_on_index(queries)

    Envelope.ok(conn, %{
      sources: Enum.map(sources, &overview_source/1),
      queries: Enum.map(queries, &overview_query(&1, chart_counts, charted_in, built_on)),
      milestones: ws.id |> Aveline.Milestones.list_active() |> Enum.map(&overview_milestone/1)
    })
  end

  defp overview_source(ds) do
    %{
      "base_id" => ds.base_data_source_id,
      "name" => ds.name,
      "adapter" => ds.adapter,
      "url" => ds.url_template,
      "deleted" => not is_nil(ds.deleted_at),
      "created_by" => username_of(ds.created_by),
      "created_at" => DateTime.to_iso8601(ds.inserted_at)
    }
  end

  defp overview_query(q, chart_counts, charted_in, built_on) do
    %{
      "name" => q.name,
      "description" => q.description,
      "kind" => q.kind,
      "data_source_id" => q.data_source_id,
      "sql" => q.sql,
      "version_number" => q.version_number,
      "created_by" => username_of(q.created_by),
      "created_at" => DateTime.to_iso8601(q.inserted_at),
      "chart_count" => Map.get(chart_counts, q.name, 0),
      "charted_in" =>
        charted_in
        |> Map.get(q.name, [])
        |> Enum.map(&%{"slug" => &1.slug, "title" => &1.title}),
      "built_on" => Map.get(built_on, q.name, [])
    }
  end

  defp overview_milestone(m) do
    %{
      "id" => m.id,
      "name" => m.name,
      "date" => Date.to_iso8601(m.date),
      "description" => m.description
    }
  end

  defp username_of(%{username: username}), do: username
  defp username_of(_), do: nil

  # {query name => chart count, query name => [%{slug, title}]} across
  # live docs the viewer can read. Same derivation as DataSourcesLive.
  defp chart_index(workspace_id, viewer_id) do
    docs = Aveline.Docs.list_current(workspace_id, viewer: viewer_id)

    refs_per_doc =
      Enum.flat_map(docs, fn doc ->
        for %{"type" => "chart", "query_ref" => ref} <- List.wrap(doc.blocks),
            is_binary(ref),
            do: {ref, doc}
      end)

    counts = refs_per_doc |> Enum.map(&elem(&1, 0)) |> Enum.frequencies()

    charted_in =
      Enum.reduce(refs_per_doc, %{}, fn {ref, doc}, acc ->
        entry = %{slug: doc.slug, title: doc.title}

        Map.update(acc, ref, [entry], fn list ->
          if Enum.any?(list, &(&1.slug == doc.slug)), do: list, else: [entry | list]
        end)
      end)

    {counts, charted_in}
  end

  # query name => sorted upstream catalog refs (derived queries only).
  defp built_on_index(queries) do
    Enum.reduce(queries, %{}, fn q, acc ->
      case q.kind == "derived" && Aveline.DataSources.Engine.parse(q.sql) do
        {:ok, refs} -> Map.put(acc, q.name, Enum.sort(refs))
        _ -> acc
      end
    end)
  end

  @doc """
  Soft-deletes the row for audit; hard-deletes the password in the
  same update. Irreversible by design — connect a new source instead.
  """
  def delete(conn, %{"name" => name}) do
    case :aveline@handlers@data_sources.delete(
           CtxBuilder.build(),
           CtxBuilder.scope(conn),
           name
         ) do
      {:ok, nil} -> Envelope.ok(conn, %{})
      {:error, err} -> GleamAdapter.error(err)
    end
  end

  defp opt_binary(v) when is_binary(v), do: {:some, v}
  defp opt_binary(_), do: :none

  # Mirrors Aveline.DataSources.safe_map/1: the built-in source carries
  # `built_in`; the `<password>` placeholder in `url` is its own mask.
  defp ds_map(
         {:data_source_info, _id, name, adapter, url, version_number, credential, deleted,
          created_at}
       ) do
    base = %{
      "name" => name,
      "adapter" => adapter,
      "url" => url,
      "version_number" => version_number,
      "credential" => credential_label(credential),
      "deleted" => deleted,
      "created_at" => created_at
    }

    if adapter == "workspace", do: Map.put(base, "built_in", true), else: base
  end

  defp credential_label(:live), do: "live"
  defp credential_label(:redacted), do: "redacted"
  defp credential_label(:no_credential), do: "none"
end
