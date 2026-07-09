defmodule Aveline.DataSources.Queries do
  @moduledoc """
  The workspace query catalog (see `Query`). Write-path rules, all
  API-time with structured errors:

    * raw queries name a live external source; their SQL is the
      source's dialect (unparseable by us — errors surface at run time)
    * derived queries parse (Engine.parse: single SELECT, syntax) and
      every referenced table must resolve to a live catalog name
    * the dependency graph stays a DAG: writes that would close a cycle
      or exceed the depth cap are rejected. The graph is never held
      resident — each write rebuilds it from the table inside the
      transaction under a per-workspace advisory lock (no hidden state,
      no concurrent-edit race)
    * renaming or deleting a query that other DERIVED queries reference
      is rejected until the dependents are updated. Charts reference
      names inside SQL text and are looser by design: they orphan to an
      error card, and the edit surfaces a feeds-N warning (PR 3)

  Queries hold no secrets, so unlike data sources they soft-delete and
  restore like docs.
  """

  import Ecto.Query, warn: false

  alias Aveline.DataSources
  alias Aveline.DataSources.Engine
  alias Aveline.DataSources.Query
  alias Aveline.Repo

  @depth_cap 10

  defp live_query do
    from q in Query, where: not q.superseded and is_nil(q.deleted_at)
  end

  def list_for_workspace(workspace_id) do
    from(q in live_query(), where: q.workspace_id == ^workspace_id, order_by: q.name)
    |> Repo.all()
  end

  @doc "The lineage view: catalog queries built on one source (base id)."
  def list_for_source(workspace_id, source_base_id) do
    from(q in live_query(),
      where: q.workspace_id == ^workspace_id and q.data_source_id == ^source_base_id,
      order_by: q.name
    )
    |> Repo.all()
  end

  def get_current_by_name(workspace_id, name) when is_binary(name) do
    from(q in live_query(), where: q.workspace_id == ^workspace_id and q.name == ^name)
    |> Repo.one()
  end

  def get_latest_by_base(base_id) when is_binary(base_id) do
    from(q in Query, where: q.base_query_id == ^base_id and not q.superseded)
    |> Repo.one()
  end

  @doc "The current (non-superseded) soft-deleted query by name — for restore."
  def get_latest_deleted_by_name(workspace_id, name) when is_binary(name) do
    from(q in Query,
      where:
        q.workspace_id == ^workspace_id and q.name == ^name and
          not q.superseded and not is_nil(q.deleted_at)
    )
    |> Repo.one()
  end

  @doc """
  Create a catalog query. `attrs` carries `:name`, `:sql`, and — for a
  raw query — `:source` (a data source name). No `:source` means
  derived: the SQL is parsed and its references validated against the
  catalog inside the workspace's graph lock.
  """
  def create(workspace_id, attrs, user_id) do
    name = attrs |> Map.get(:name, "") |> to_string() |> String.trim() |> String.downcase()
    sql = attrs |> Map.get(:sql, "") |> to_string()

    case Map.get(attrs, :source) do
      nil ->
        insert_derived(workspace_id, name, sql, user_id)

      source_name ->
        case DataSources.get_current_by_name(workspace_id, to_string(source_name)) do
          nil ->
            {:error, :data_source_not_found, "no data source named #{inspect(source_name)}"}

          %{adapter: "workspace"} ->
            {:error, :invalid_query,
             "raw queries target external sources; a query over the workspace catalog is a derived query (omit source)"}

          source ->
            insert(workspace_id, %{
              name: name,
              kind: "raw",
              data_source_id: source.base_data_source_id,
              sql: sql,
              created_by_id: user_id
            })
        end
    end
  end

  defp insert_derived(workspace_id, name, sql, user_id) do
    with_graph_lock(workspace_id, fn ->
      with {:ok, refs} <- parse_derived(sql),
           :ok <- refs_resolve(workspace_id, refs, name),
           :ok <- graph_stays_dag(workspace_id, name, refs) do
        insert(workspace_id, %{
          name: name,
          kind: "derived",
          data_source_id: nil,
          sql: sql,
          created_by_id: user_id
        })
      end
    end)
  end

  defp insert(workspace_id, attrs) do
    %Query{}
    |> Query.insert_changeset(Map.merge(attrs, %{workspace_id: workspace_id, base_query_id: Ecto.UUID.generate()}))
    |> Repo.insert()
    |> normalize_insert()
  end

  @doc """
  Versioned edit; `changes` may carry `:name` and/or `:sql`. Renames are
  rejected while other derived queries reference the old name.
  """
  def edit(%Query{} = current, changes, user_id) when is_map(changes) do
    name =
      changes |> Map.get(:name, current.name) |> to_string() |> String.trim() |> String.downcase()

    sql = changes |> Map.get(:sql, current.sql) |> to_string()

    with_graph_lock(current.workspace_id, fn ->
      rename? = name != current.name

      with :ok <- if(rename?, do: no_derived_dependents(current, "rename"), else: :ok),
           :ok <- validate_for_kind(current, name, sql) do
        insert_next_version(current, %{name: name, sql: sql}, user_id)
      end
    end)
  end

  defp validate_for_kind(%{kind: "raw"}, _name, _sql), do: :ok

  defp validate_for_kind(%{kind: "derived", workspace_id: ws, name: own_name}, new_name, sql) do
    with {:ok, refs} <- parse_derived(sql),
         :ok <- refs_resolve(ws, refs, new_name, except: own_name) do
      graph_stays_dag(ws, new_name, refs, except: own_name)
    end
  end

  @doc "Soft delete. Rejected while other derived queries reference it."
  def delete(%Query{} = current, user_id) do
    with_graph_lock(current.workspace_id, fn ->
      with :ok <- no_derived_dependents(current, "delete") do
        current
        |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(), deleted_by_id: user_id)
        |> Repo.update()
      end
    end)
  end

  @doc "Restore a soft-deleted query. Fails if the name was re-taken."
  def restore(%Query{} = current) do
    current
    |> Ecto.Changeset.change(deleted_at: nil, deleted_by_id: nil)
    |> Ecto.Changeset.unique_constraint([:workspace_id, :name],
      name: :queries_workspace_id_name_index,
      message: "already exists"
    )
    |> Repo.update()
    |> normalize_insert()
  end

  defp insert_next_version(current, attrs, user_id) do
    result =
      Repo.transaction(fn ->
        {1, _} =
          from(q in Query, where: q.id == ^current.id)
          |> Repo.update_all(set: [superseded: true])

        insert =
          %Query{}
          |> Query.insert_changeset(%{
            workspace_id: current.workspace_id,
            base_query_id: current.base_query_id,
            version_number: current.version_number + 1,
            name: attrs.name,
            kind: current.kind,
            data_source_id: current.data_source_id,
            sql: attrs.sql,
            created_by_id: user_id
          })
          |> Repo.insert()

        case insert do
          {:ok, q} -> q
          {:error, cs} -> Repo.rollback(cs)
        end
      end)

    normalize_insert(result)
  end

  # ── graph validation ─────────────────────────────────────────────
  # Rebuilt from the table on every write, held for the transaction,
  # thrown away: no resident state, no cross-node divergence. The
  # advisory lock serializes writers per workspace so two concurrent
  # edits can't each pass acyclicity against their own snapshot.

  defp with_graph_lock(workspace_id, fun) do
    case Repo.transaction(
           fn ->
             Repo.query!("SELECT pg_advisory_xact_lock(hashtext('aveline_queries:' || $1))", [
               workspace_id
             ])

             case fun.() do
               {:ok, value} -> value
               {:error, _} = err -> Repo.rollback(err)
               {:error, _, _} = err -> Repo.rollback(err)
             end
           end,
           timeout: 30_000
         ) do
      {:ok, value} -> {:ok, value}
      {:error, {:error, _} = err} -> err
      {:error, {:error, _, _} = err} -> err
      {:error, other} -> {:error, other}
    end
  end

  defp no_derived_dependents(%Query{} = current, action) do
    dependents =
      current.workspace_id
      |> derived_edges(current.name)
      |> Enum.filter(fn {_name, refs} -> current.name in refs end)
      |> Enum.map(fn {name, _} -> name end)
      |> Enum.sort()

    case dependents do
      [] ->
        :ok

      names ->
        {:error, :query_has_dependents,
         "cannot #{action} #{inspect(current.name)}: derived quer#{if length(names) == 1, do: "y", else: "ies"} #{Enum.join(names, ", ")} reference#{if length(names) == 1, do: "s", else: ""} it — update #{if length(names) == 1, do: "it", else: "them"} first"}
    end
  end

  defp parse_derived(sql) do
    case Engine.parse(sql) do
      {:ok, refs} -> {:ok, refs}
      {:error, msg} -> {:error, :invalid_query, msg}
    end
  end

  defp refs_resolve(workspace_id, refs, own_name, opts \\ []) do
    except = Keyword.get(opts, :except)

    known =
      list_for_workspace(workspace_id)
      |> Enum.map(& &1.name)
      |> MapSet.new()
      |> then(fn set -> if except, do: MapSet.delete(set, except), else: set end)
      |> MapSet.put(own_name)

    case Enum.reject(refs, &MapSet.member?(known, &1)) do
      [] ->
        :ok

      unknown ->
        {:error, :invalid_query,
         "unknown catalog quer#{if length(unknown) == 1, do: "y", else: "ies"}: #{Enum.join(unknown, ", ")} — every referenced table must be a catalog query in this workspace (aveline list-queries)"}
    end
  end

  # DFS over the whole live edge set with the candidate edges swapped
  # in: rejects cycles (visiting-set) and chains past the depth cap.
  defp graph_stays_dag(workspace_id, name, refs, opts \\ []) do
    except = Keyword.get(opts, :except)

    edges =
      workspace_id
      |> derived_edges(except)
      |> Map.put(name, refs)

    Enum.reduce_while(Map.keys(edges), :ok, fn start, :ok ->
      case depth(start, edges, MapSet.new(), %{}) do
        {:cycle, involved} ->
          {:halt,
           {:error, :invalid_query,
            "circular reference involving: #{involved |> Enum.uniq() |> Enum.join(", ")} — the catalog must stay a DAG"}}

        {:depth, d, _memo} when d > @depth_cap ->
          {:halt, {:error, :invalid_query, "query chains deeper than #{@depth_cap} are not allowed (got #{d})"}}

        {:depth, _d, _memo} ->
          {:cont, :ok}
      end
    end)
  end

  # Every live derived query's references, parsed fresh. Catalogs are
  # small (dozens); recomputing beats storing derived state.
  defp derived_edges(workspace_id, except) do
    from(q in live_query(),
      where: q.workspace_id == ^workspace_id and q.kind == "derived"
    )
    |> Repo.all()
    |> Enum.reject(&(&1.name == except))
    |> Map.new(fn q ->
      case Engine.parse(q.sql) do
        {:ok, refs} -> {q.name, refs}
        # A stored query that no longer parses can't add edges; its own
        # runs will surface the error.
        {:error, _} -> {q.name, []}
      end
    end)
  end

  defp depth(node, edges, visiting, memo) do
    cond do
      MapSet.member?(visiting, node) ->
        {:cycle, [node | visiting |> MapSet.to_list() |> Enum.sort()]}

      Map.has_key?(memo, node) ->
        {:depth, memo[node], memo}

      true ->
        case Map.get(edges, node) do
          # A leaf (raw query, or a name that isn't a derived query).
          nil ->
            {:depth, 1, Map.put(memo, node, 1)}

          refs ->
            visiting = MapSet.put(visiting, node)

            Enum.reduce_while(refs, {:depth, 1, memo}, fn ref, {:depth, best, memo} ->
              case depth(ref, edges, visiting, memo) do
                {:cycle, _} = cycle -> {:halt, cycle}
                {:depth, d, memo} -> {:cont, {:depth, max(best, d + 1), memo}}
              end
            end)
            |> case do
              {:cycle, _} = cycle -> cycle
              {:depth, d, memo} -> {:depth, d, Map.put(memo, node, d)}
            end
        end
    end
  end

  @doc "The one shape read surfaces see."
  def safe_map(%Query{} = q) do
    %{
      "name" => q.name,
      "kind" => q.kind,
      "data_source_id" => q.data_source_id,
      "sql" => q.sql,
      "version_number" => q.version_number,
      "deleted" => not is_nil(q.deleted_at),
      "created_at" => DateTime.to_iso8601(q.inserted_at)
    }
  end

  defp normalize_insert({:ok, q}), do: {:ok, q}

  defp normalize_insert({:error, %Ecto.Changeset{} = cs}) do
    msg =
      Enum.map_join(cs.errors, "; ", fn {field, {m, _}} -> "#{field} #{m}" end)

    {:error, :invalid_query, msg}
  end

  defp normalize_insert(other), do: other
end
