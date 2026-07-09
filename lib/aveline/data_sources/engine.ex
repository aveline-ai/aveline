defmodule Aveline.DataSources.Engine do
  @moduledoc """
  The analytics engine: a vendored DuckDB CLI driven as a sandboxed OS
  process per run (never a NIF — a NIF can't be interrupted, shares
  fate with the node, and shares an address space with every
  workspace's credentials).

  Each run spawns `/usr/bin/env -i <duckdb>` (scrubbed environment: no
  DATABASE_URL, no SECRET_KEY_BASE, no release cookie), writes one SQL
  script over stdin, reads JSON from stdout, and SIGKILLs the OS pid at
  the timeout. The script's first statements harden the SQL surface —
  external access off, extensions off, memory capped, then the
  configuration locked so the payload SQL can't turn anything back on.
  `-bail` aborts the script on the first error, so nothing runs
  unhardened.

  Two modes:

    * `parse/1` — syntax-check a SELECT and extract the table names it
      references (via `json_serialize_sql`; CTE names subtracted). No
      data is touched. This backs write-time validation of derived
      queries and run-time dependency resolution.
    * `run/3` — materialize leaf tables (typed, value-sniffed), CREATE
      each derived layer in dependency order, execute the top-level
      SELECT, return up to `row_cap` rows. Everything lives and dies in
      one in-memory process; nothing is ever written anywhere.

  A global semaphore (`:engine_semaphore` counter) caps concurrent
  runs. Results are plain maps shaped like `Runner.run/2` results:
  `%{"columns" => [...], "rows" => [...], "truncated" => bool}`.
  """

  alias Aveline.DataSources.Engine.Semaphore
  alias Aveline.DataSources.Runner

  @timeout_ms 2_000
  @parse_timeout_ms 2_000
  @memory_limit "256MB"
  @dollar_tag "$aveline_sql$"

  @doc "Absolute path to the vendored binary, or nil when not fetched."
  def binary_path do
    priv = :code.priv_dir(:aveline) |> to_string() |> Path.join("duckdb/duckdb")
    if File.exists?(priv), do: priv, else: System.find_executable("duckdb")
  end

  def available?, do: binary_path() != nil

  @doc """
  Parse-only: `{:ok, table_names}` for a single SELECT statement,
  `{:error, msg}` for anything else (syntax error, non-SELECT,
  multiple statements). Table names exclude the statement's own CTEs.
  """
  def parse(sql) when is_binary(sql) do
    with :ok <- guard_dollar_tag(sql),
         {:ok, payload} <-
           script(["SELECT json_serialize_sql(#{dollar_quote(sql)}) AS ast;"], @parse_timeout_ms),
         {:ok, [%{"ast" => ast}]} <- decode_rows(payload) do
      cond do
        ast["error"] == true ->
          {:error, parse_error_message(ast)}

        length(ast["statements"] || []) != 1 ->
          {:error, "exactly one SELECT statement, please (got #{length(ast["statements"] || [])})"}

        true ->
          {tables, ctes} = collect_refs(ast, MapSet.new(), MapSet.new())
          {:ok, tables |> MapSet.difference(ctes) |> Enum.sort()}
      end
    end
  end

  @doc """
  Compose and execute. `leaves` are `{name, %{"columns" => _, "rows" => _}}`
  materialized as typed temp tables; `derived` are `{name, sql}` created
  bottom-up in the given order; `final_sql` is the SELECT whose rows come
  back. Output is capped at `Runner.row_cap()` rows with `"truncated"`.
  """
  def run(leaves, derived, final_sql) do
    cap = Runner.row_cap()

    with :ok <- guard_dollar_tag(final_sql) do
      statements =
        Enum.flat_map(leaves, fn {name, result} -> leaf_statements(name, result) end) ++
          Enum.map(derived, fn {name, sql} ->
            "CREATE TEMP TABLE #{quote_ident(name)} AS SELECT * FROM (\n#{sql}\n) AS __aveline_derived;"
          end) ++
          [
            "CREATE TEMP TABLE __aveline_out AS SELECT * FROM (\n#{final_sql}\n) AS __aveline_q LIMIT #{cap + 1};",
            # Row alias is namespaced so it can't collide with a user
            # column named `t` — to_json(row) must see the ROW, not a
            # same-named column.
            """
            SELECT to_json(struct_pack(
              columns := (SELECT coalesce(list(name ORDER BY cid), []) FROM pragma_table_info('__aveline_out')),
              rows := coalesce((SELECT json_group_array(to_json(__aveline_row)) FROM __aveline_out AS __aveline_row), to_json([]))
            )) AS payload;
            """
          ]

      with {:ok, out} <- script(statements, @timeout_ms),
           {:ok, [%{"payload" => %{"columns" => cols, "rows" => row_objs}}]} <- decode_rows(out) do
        rows = Enum.map(row_objs, fn obj -> Enum.map(cols, &Map.get(obj, &1)) end)
        truncated? = length(rows) > cap

        {:ok,
         %{
           "columns" => cols,
           "rows" => Enum.take(rows, cap),
           "truncated" => truncated?
         }}
      else
        {:error, msg} -> {:error, msg}
        _other -> {:error, "engine returned an unexpected shape"}
      end
    end
  end

  # ── script execution over a sandboxed port ─────────────────────────

  defp script(statements, timeout_ms) do
    case binary_path() do
      nil ->
        {:error, "analytics engine not installed — run `mix duckdb.fetch` (or rebuild the image)"}

      binary ->
        with :ok <- acquire() do
          try do
            input = Enum.join(hardening() ++ statements, "\n")
            exec(binary, input, timeout_ms)
          after
            Semaphore.release()
          end
        end
    end
  end

  # The SQL-surface sandbox. Order matters: lock_configuration LAST, so
  # the payload can't SET anything back on; -bail means a failed SET
  # aborts the whole script rather than running the payload unhardened.
  defp hardening do
    [
      "SET memory_limit='#{@memory_limit}';",
      "SET temp_directory='';",
      "SET autoinstall_known_extensions=false;",
      "SET autoload_known_extensions=false;",
      "SET enable_external_access=false;",
      "SET lock_configuration=true;"
    ]
  end

  defp exec(binary, input, timeout_ms) do
    # /usr/bin/env -i: the child starts with an EMPTY environment. SQL
    # flags constrain the SQL; the scrubbed env constrains an exploited
    # process — no DATABASE_URL, no secrets, no cookie to steal.
    port =
      Port.open(
        {:spawn_executable, "/usr/bin/env"},
        [
          :binary,
          :exit_status,
          :hide,
          :stderr_to_stdout,
          args: ["-i", binary, "-batch", "-json", "-bail", "-noheader"]
        ]
      )

    os_pid =
      case Port.info(port, :os_pid) do
        {:os_pid, pid} -> pid
        _ -> nil
      end

    # Erlang ports can't half-close stdin, so the script ends with the
    # CLI's own exit command; -bail exits earlier (nonzero) on any error.
    Port.command(port, [input, "\n.exit\n"])

    try do
      collect(port, os_pid, [], System.monotonic_time(:millisecond) + timeout_ms, timeout_ms)
    after
      safe_close(port)
    end
  end

  defp collect(port, os_pid, acc, deadline, timeout_ms) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      kill(os_pid)
      {:error, "transform timed out after #{timeout_ms}ms and was killed"}
    else
      receive do
        {^port, {:data, chunk}} ->
          collect(port, os_pid, [acc | [chunk]], deadline, timeout_ms)

        {^port, {:exit_status, 0}} ->
          {:ok, IO.iodata_to_binary(acc)}

        {^port, {:exit_status, _nonzero}} ->
          {:error, engine_error(IO.iodata_to_binary(acc))}
      after
        min(remaining, 100) ->
          collect(port, os_pid, acc, deadline, timeout_ms)
      end
    end
  end

  # A port close doesn't kill a hung child — SIGKILL the OS pid.
  defp kill(nil), do: :ok

  defp kill(os_pid) do
    System.cmd("kill", ["-9", Integer.to_string(os_pid)], stderr_to_stdout: true)
    :ok
  end

  defp safe_close(port) do
    if Port.info(port) != nil, do: Port.close(port)
  rescue
    ArgumentError -> :ok
  end

  # ── typed leaf materialization ─────────────────────────────────────
  # Leaf rows arrive JSON-flattened from the runner/cache (timestamps as
  # ISO strings, decimals as floats). Column types are value-sniffed —
  # the drivers expose values, not type metadata — so timestamps become
  # real TIMESTAMPs and ASOF JOIN / time_bucket work. All-NULL columns
  # default to VARCHAR.

  defp leaf_statements(name, %{"columns" => cols, "rows" => rows}) do
    types = Enum.map(0..(length(cols) - 1)//1, fn i -> sniff_type(rows, i) end)

    col_defs =
      cols
      |> Enum.zip(types)
      |> Enum.map_join(", ", fn {c, t} -> "#{quote_ident(c)} #{t}" end)

    create = "CREATE TEMP TABLE #{quote_ident(name)} (#{col_defs});"

    inserts =
      rows
      |> Enum.chunk_every(200)
      |> Enum.map(fn chunk ->
        values =
          Enum.map_join(chunk, ",\n", fn row ->
            "(" <>
              Enum.map_join(Enum.zip(row, types), ", ", fn {v, t} -> literal(v, t) end) <> ")"
          end)

        "INSERT INTO #{quote_ident(name)} VALUES\n#{values};"
      end)

    [create | if(rows == [], do: [], else: inserts)]
  end

  @iso_date ~r/^\d{4}-\d{2}-\d{2}$/
  @iso_ts ~r/^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}/

  defp sniff_type(rows, i) do
    rows
    |> Enum.map(&Enum.at(&1, i))
    |> Enum.reject(&is_nil/1)
    |> case do
      [] ->
        "VARCHAR"

      values ->
        cond do
          Enum.all?(values, &is_boolean/1) -> "BOOLEAN"
          Enum.all?(values, &is_integer/1) -> "BIGINT"
          Enum.all?(values, &is_number/1) -> "DOUBLE"
          Enum.all?(values, &(is_binary(&1) and &1 =~ @iso_ts)) -> "TIMESTAMP"
          Enum.all?(values, &(is_binary(&1) and &1 =~ @iso_date)) -> "DATE"
          true -> "VARCHAR"
        end
    end
  end

  defp literal(nil, _t), do: "NULL"
  defp literal(true, _t), do: "true"
  defp literal(false, _t), do: "false"
  defp literal(v, _t) when is_integer(v) or is_float(v), do: to_string(v)

  defp literal(v, t) when is_binary(v) do
    escaped = v |> String.replace("'", "''") |> String.replace("\0", "")

    case t do
      "TIMESTAMP" -> "TIMESTAMP '#{escaped}'"
      "DATE" -> "DATE '#{escaped}'"
      _ -> "'#{escaped}'"
    end
  end

  defp literal(v, t), do: literal(to_string(v), t)

  defp quote_ident(name), do: "\"" <> String.replace(name, "\"", "\"\"") <> "\""

  # Dollar-quoting sidesteps escaping for parse/1's SQL-in-SQL; the tag
  # is long and namespaced, so colliding input is rejected, not mangled.
  defp dollar_quote(sql), do: @dollar_tag <> sql <> @dollar_tag

  defp guard_dollar_tag(sql) do
    if String.contains?(sql, @dollar_tag),
      do: {:error, "SQL may not contain the reserved marker #{@dollar_tag}"},
      else: :ok
  end

  # ── output decoding ────────────────────────────────────────────────

  defp decode_rows(out) do
    case Jason.decode(String.trim(out)) do
      {:ok, rows} when is_list(rows) -> {:ok, rows}
      _ -> {:error, "engine output was not JSON: #{String.slice(out, 0, 200)}"}
    end
  end

  defp parse_error_message(ast) do
    "invalid analytics SQL: #{ast["error_message"] || "parse error"}" <>
      if ast["error_type"] == "not implemented",
        do: " (only SELECT statements are allowed)",
        else: ""
  end

  # DuckDB error lines read like "Binder Error: ..." — keep the first
  # line, it names the stage and the problem.
  defp engine_error(out) do
    out
    |> String.split("\n", trim: true)
    |> List.first()
    |> case do
      nil -> "engine failed with no output"
      line -> String.slice(line, 0, 500)
    end
  end

  # AST walk: BASE_TABLE nodes are references; cte_map keys are the
  # statement's own names and don't count.
  defp collect_refs(node, tables, ctes) when is_map(node) do
    tables =
      case node do
        %{"type" => "BASE_TABLE", "table_name" => t} when is_binary(t) ->
          MapSet.put(tables, String.downcase(t))

        _ ->
          tables
      end

    ctes =
      case node do
        %{"cte_map" => %{"map" => entries}} when is_list(entries) ->
          Enum.reduce(entries, ctes, fn
            %{"key" => k}, acc when is_binary(k) -> MapSet.put(acc, String.downcase(k))
            _, acc -> acc
          end)

        _ ->
          ctes
      end

    Enum.reduce(Map.values(node), {tables, ctes}, fn v, {t, c} -> collect_refs(v, t, c) end)
  end

  defp collect_refs(node, tables, ctes) when is_list(node) do
    Enum.reduce(node, {tables, ctes}, fn v, {t, c} -> collect_refs(v, t, c) end)
  end

  defp collect_refs(_other, tables, ctes), do: {tables, ctes}

  # ── concurrency cap ────────────────────────────────────────────────
  # A monitored semaphore (Engine.Semaphore): at most @max_concurrent
  # engine processes at once; the rest briefly spin-wait (runs are
  # seconds at worst). Slots free on holder death, so a killed LiveView
  # run can't leak capacity.

  defp acquire, do: acquire(System.monotonic_time(:millisecond) + 10_000)

  defp acquire(deadline) do
    case Semaphore.acquire() do
      :ok ->
        :ok

      :full ->
        if System.monotonic_time(:millisecond) > deadline do
          {:error, "analytics engine is saturated; try again shortly"}
        else
          Process.sleep(25)
          acquire(deadline)
        end
    end
  end
end
