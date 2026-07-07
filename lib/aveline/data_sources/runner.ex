defmodule Aveline.DataSources.Runner do
  @moduledoc """
  Runs one read-only SQL statement against a workspace data source and
  returns `{:ok, %{"columns" => [...], "rows" => [[...]]}}` or
  `{:error, reason_string}`. Results only ever live in memory.

  Safety posture (both adapters):
    * the session is forced read-only before the user query runs
    * one statement per call (both drivers reject multi-statement)
    * #{5} second query timeout, #{5} second connect timeout
    * rows capped at 1000 (result carries `"truncated" => true`)
    * a fresh connection per call, closed in `after` — no pooled
      credentials lingering; the 60s cache keeps call volume low

  Errors come back as strings, not raises: a chart with a broken query
  is a state on the block, never a failed doc read.
  """

  @query_timeout_ms 5_000
  @connect_timeout_ms 5_000
  @row_cap 1000

  def row_cap, do: @row_cap

  # Hard ceiling on one run: connect + query + margin.
  @task_timeout_ms 12_000

  def run(%{adapter: adapter, password: password} = ds, sql) when is_binary(password) do
    url = Aveline.DataSources.dial_url(ds)

    # The drivers LINK the connection process to its starter, and a
    # failed connect (backoff_type: :stop) kills it — so the dial runs
    # in an unlinked supervised task, where a dying connection can only
    # take down the task, never the doc-read process. The task result
    # is already an {:ok, _} | {:error, _} tuple.
    task =
      Task.Supervisor.async_nolink(Aveline.TaskSupervisor, fn ->
        case adapter do
          "postgres" -> run_postgres(url, sql)
          "mysql" -> run_mysql(url, sql)
          _ -> {:error, "unsupported adapter"}
        end
      end)

    case Task.yield(task, @task_timeout_ms) do
      {:ok, result} ->
        result

      {:exit, reason} ->
        {:error, "connection failed: " <> exit_message(reason)}

      nil ->
        # Kill the hung dial; if a reply raced in during shutdown, take it.
        case Task.shutdown(task, :brutal_kill) do
          {:ok, result} -> result
          _ -> {:error, "timed out connecting or querying"}
        end
    end
  end

  def run(_, _), do: {:error, "data source has no live credential"}

  # The task dies with whatever killed the linked connection process —
  # usually a DBConnection/driver exception carrying the real story
  # ("connection refused", "password authentication failed", "ssl
  # required"). Surface it; debugging blind is worse than verbose.
  defp exit_message(%{__exception__: true} = e), do: Exception.message(e)
  defp exit_message({%{__exception__: true} = e, _stacktrace}), do: Exception.message(e)
  defp exit_message({:shutdown, reason}), do: exit_message(reason)
  defp exit_message(other), do: inspect(other) |> String.slice(0, 200)

  # ===== postgres =====

  defp run_postgres(url, sql) do
    {url, ssl} = Aveline.DataSources.TLS.split(url)

    opts =
      url
      |> Ecto.Repo.Supervisor.parse_url()
      |> with_socket_family()
      |> then(fn o -> if ssl, do: Keyword.put(o, :ssl, ssl), else: o end)
      |> Keyword.merge(
        timeout: @query_timeout_ms,
        connect_timeout: @connect_timeout_ms,
        pool_size: 1,
        # No reconnect loops: fail the one call, the block shows it.
        backoff_type: :stop,
        # Force every statement in this session read-only.
        after_connect: fn conn ->
          Postgrex.query!(conn, "SET default_transaction_read_only = on", [])
        end
      )

    case Postgrex.start_link(opts) do
      {:ok, pid} ->
        try do
          case Postgrex.query(pid, sql, [], timeout: @query_timeout_ms) do
            {:ok, %Postgrex.Result{columns: cols, rows: rows}} ->
              {:ok, shape(cols, rows)}

            {:error, %Postgrex.Error{postgres: %{message: msg}}} ->
              {:error, "query failed: #{msg}"}

            {:error, %DBConnection.ConnectionError{message: msg}} ->
              {:error, "connection failed: #{msg}"}

            {:error, other} ->
              {:error, "query failed: #{Exception.message(other)}"}
          end
        catch
          :exit, _ -> {:error, "connection failed or timed out"}
        after
          safe_stop(pid)
        end

      {:error, reason} ->
        {:error, "connection failed: #{inspect(reason)}"}
    end
  end

  # ===== mysql =====

  defp run_mysql(url, sql) do
    {url, ssl} = Aveline.DataSources.TLS.split(url)

    opts =
      url
      |> Ecto.Repo.Supervisor.parse_url()
      |> with_socket_family()
      |> then(fn o -> if ssl, do: Keyword.put(o, :ssl, ssl), else: o end)
      |> Keyword.merge(
        timeout: @query_timeout_ms,
        connect_timeout: @connect_timeout_ms,
        pool_size: 1,
        backoff_type: :stop,
        after_connect: fn conn ->
          MyXQL.query!(conn, "SET SESSION TRANSACTION READ ONLY")
        end
      )

    case MyXQL.start_link(opts) do
      {:ok, pid} ->
        try do
          case MyXQL.query(pid, sql, [], timeout: @query_timeout_ms) do
            {:ok, %MyXQL.Result{columns: cols, rows: rows}} ->
              {:ok, shape(cols, rows)}

            {:error, %MyXQL.Error{message: msg}} ->
              {:error, "query failed: #{msg}"}

            {:error, %DBConnection.ConnectionError{message: msg}} ->
              {:error, "connection failed: #{msg}"}

            {:error, other} ->
              {:error, "query failed: #{Exception.message(other)}"}
          end
        catch
          :exit, _ -> {:error, "connection failed or timed out"}
        after
          safe_stop(pid)
        end

      {:error, reason} ->
        {:error, "connection failed: #{inspect(reason)}"}
    end
  end

  # The connection process may already be dead (backoff_type: :stop
  # kills it on connect failure) — stopping a dead pid exits, and an
  # exit from an `after` block escapes the surrounding catch. Swallow it.
  defp safe_stop(pid) do
    GenServer.stop(pid, :normal, 1_000)
  catch
    :exit, _ -> :ok
  end

  # The BEAM's resolver looks up IPv4 by default, so an IPv6-only host
  # (e.g. Fly's private .flympg.net addresses) comes back :nxdomain even
  # though the system resolver sees it. If the host has no A record but
  # does have an AAAA, dial over IPv6.
  defp with_socket_family(opts) do
    host = opts |> Keyword.get(:hostname, "") |> to_charlist()

    case :inet.getaddr(host, :inet) do
      {:ok, _} ->
        opts

      {:error, _} ->
        case :inet.getaddr(host, :inet6) do
          {:ok, _} -> Keyword.put(opts, :socket_options, [:inet6])
          {:error, _} -> opts
        end
    end
  end

  # ===== shared =====

  defp shape(cols, rows) do
    rows = rows || []
    truncated? = length(rows) > @row_cap
    rows = rows |> Enum.take(@row_cap) |> Enum.map(fn row -> Enum.map(row, &json_safe/1) end)

    out = %{"columns" => cols || [], "rows" => rows}
    if truncated?, do: Map.put(out, "truncated", true), else: out
  end

  # Result cells must survive Jason encoding and block echoes.
  defp json_safe(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp json_safe(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp json_safe(%Date{} = d), do: Date.to_iso8601(d)
  defp json_safe(%Time{} = t), do: Time.to_iso8601(t)
  defp json_safe(%Decimal{} = d), do: Decimal.to_float(d)
  defp json_safe(v) when is_binary(v) do
    if String.valid?(v), do: v, else: Base.encode64(v)
  end
  defp json_safe(v) when is_number(v) or is_boolean(v) or is_nil(v), do: v
  defp json_safe(v), do: inspect(v)
end
