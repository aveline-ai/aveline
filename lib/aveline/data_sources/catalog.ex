defmodule Aveline.DataSources.Catalog do
  @moduledoc """
  Executes SQL against the workspace source — the virtual data source
  whose tables are the query catalog. The pipeline (same for a chart
  render, run-block, and ad-hoc query-data-source):

    1. resolve — parse the SQL, look each referenced table up in the
       catalog, recurse through derived definitions (visited set; the
       write path already guarantees a DAG). Unresolvable names fail
       closed: an error, never a silent empty table.
    2. run leaves — each raw query through the existing Runner + 60s
       cache (row cap, timeout, TLS, single-flight), in parallel.
    3. compose — one sandboxed engine process materializes the leaves
       as typed temp tables, creates each derived layer bottom-up,
       executes the top-level SELECT, caps the output.
    4. stream and discard — rows go back to the caller; nothing is
       persisted anywhere at any layer.

  Results are `{:ok, result_map}` shaped like `Runner.run/2` plus
  `"truncated_inputs"` when a leaf hit the row cap (stats over silently
  truncated data are wrong — the chart says so).
  """

  alias Aveline.DataSources
  alias Aveline.DataSources.Cache
  alias Aveline.DataSources.Engine
  alias Aveline.DataSources.Queries

  # The write path caps chains at 10; the run path fails closed a bit
  # above it rather than trusting stored state forever.
  @resolve_depth_cap 12

  def run(workspace_id, sql) do
    with {:ok, refs} <- Engine.parse(sql),
         {:ok, plan} <- expand(workspace_id, refs),
         {:ok, leaf_results} <- run_leaves(plan.leaves) do
      derived = Enum.map(plan.derived, &{&1.name, &1.sql})

      case Engine.run(leaf_results, derived, sql) do
        {:ok, result} ->
          # The catalog queries this SQL directly names — for the chart
          # caption ("catalog: activity_per_day"). Sorted, deduped.
          result = Map.put(result, "catalog_refs", Enum.sort(refs))
          {:ok, flag_truncated_inputs(result, leaf_results)}

        {:error, msg} ->
          {:error, msg}
      end
    end
  end

  @doc """
  Drop the cache entries for a catalog SQL's raw leaves, so the next run
  re-dials the customer databases (the re-run button). The composed
  result was never cached; only leaves are.
  """
  def bust_leaves(workspace_id, sql) do
    with {:ok, refs} <- Engine.parse(sql),
         {:ok, plan} <- expand(workspace_id, refs) do
      Enum.each(plan.leaves, fn leaf ->
        case DataSources.get_current_by_base(leaf.data_source_id) do
          nil -> :ok
          source -> Cache.bust(source.base_data_source_id, leaf.sql)
        end
      end)
    end

    :ok
  end

  # ── resolution ─────────────────────────────────────────────────────
  # DFS from the top-level references. Output: raw leaves + derived
  # queries in bottom-up creation order (post-order).

  defp expand(workspace_id, refs) do
    case Enum.reduce_while(refs, {:ok, %{seen: %{}, order: []}}, fn ref, {:ok, acc} ->
           case visit(workspace_id, ref, acc, 0) do
             {:ok, acc} -> {:cont, {:ok, acc}}
             {:error, _} = err -> {:halt, err}
           end
         end) do
      {:ok, %{seen: seen, order: order}} ->
        # `order` holds derived names most-recently-finished first;
        # dependencies finish before dependents, so creation order
        # (dependencies first) is its reverse.
        {:ok,
         %{
           leaves: seen |> Map.values() |> Enum.filter(&(&1.kind == "raw")),
           derived: order |> Enum.reverse() |> Enum.map(&Map.fetch!(seen, &1))
         }}

      {:error, _} = err ->
        err
    end
  end

  defp visit(_ws, _name, _acc, depth) when depth > @resolve_depth_cap,
    do: {:error, "query chain deeper than #{@resolve_depth_cap} — refusing to run"}

  defp visit(workspace_id, name, acc, depth) do
    if Map.has_key?(acc.seen, name) do
      {:ok, acc}
    else
      case Queries.get_current_by_name(workspace_id, name) do
        nil ->
          {:error,
           "unknown table #{inspect(name)} — every table in workspace-source SQL must be a catalog query (aveline list-queries)"}

        %{kind: "raw"} = q ->
          {:ok, %{acc | seen: Map.put(acc.seen, name, q)}}

        %{kind: "derived"} = q ->
          with {:ok, refs} <- Engine.parse(q.sql) do
            acc = %{acc | seen: Map.put(acc.seen, name, q)}

            case Enum.reduce_while(refs, {:ok, acc}, fn ref, {:ok, acc} ->
                   case visit(workspace_id, ref, acc, depth + 1) do
                     {:ok, acc} -> {:cont, {:ok, acc}}
                     {:error, _} = err -> {:halt, err}
                   end
                 end) do
              # Post-order: dependencies precede dependents.
              {:ok, acc} -> {:ok, %{acc | order: [name | acc.order]}}
              {:error, _} = err -> err
            end
          else
            {:error, msg} -> {:error, "derived query #{inspect(name)}: #{msg}"}
          end
      end
    end
  end

  # ── leaves ─────────────────────────────────────────────────────────

  defp run_leaves(leaves) do
    leaves
    |> Task.async_stream(&run_leaf/1, max_concurrency: 4, timeout: 30_000, on_timeout: :kill_task)
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, named_result}}, {:ok, acc} -> {:cont, {:ok, [named_result | acc]}}
      {:ok, {:error, msg}}, _acc -> {:halt, {:error, msg}}
      {:exit, _reason}, _acc -> {:halt, {:error, "a leaf query crashed"}}
    end)
  end

  defp run_leaf(query) do
    case DataSources.get_current_by_base(query.data_source_id) do
      nil ->
        {:error, "query #{inspect(query.name)}: its data source was deleted — repoint it (aveline edit-query)"}

      source ->
        case Cache.run(source, query.sql) do
          {:ok, result} -> {:ok, {query.name, result}}
          {:error, msg} -> {:error, "query #{inspect(query.name)} (#{source.name}): #{msg}"}
        end
    end
  end

  defp flag_truncated_inputs(result, leaf_results) do
    case for {name, %{"truncated" => true}} <- leaf_results, do: name do
      [] -> result
      names -> Map.put(result, "truncated_inputs", Enum.sort(names))
    end
  end
end
