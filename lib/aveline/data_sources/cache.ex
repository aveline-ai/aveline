defmodule Aveline.DataSources.Cache do
  @moduledoc """
  60-second in-memory cache over `Runner.run/2`, keyed by
  {base_data_source_id, query}. Exists so a busy doc can't hammer a
  customer database: N reads within the window cost one query.

  Single-flight: concurrent misses on the same key coalesce into one
  Runner call and all callers get its result — parallel chart runs on
  a page (or several viewers mounting at once) dial the customer
  database once, not once each.

  ETS only — results never touch disk or our database. Errors are
  cached too (a down database shouldn't be re-dialed on every read).
  """
  use GenServer

  alias Aveline.DataSources.Runner

  @table __MODULE__
  @ttl_ms 60_000
  # Runner's worst case is ~12s (connect + query + margin); waiters
  # must outlive it comfortably.
  @call_timeout 30_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Runner.run/2 through the TTL cache (single-flight on miss)."
  def run(%{base_data_source_id: base} = ds, sql) do
    key = {base, sql}

    case fresh(key) do
      {:ok, result} -> result
      :miss -> GenServer.call(__MODULE__, {:run, key, ds, sql}, @call_timeout)
    end
  end

  @doc "Drop one cached entry so the next run re-dials the source (re-run button)."
  def bust(base, sql), do: :ets.delete(@table, {base, sql})

  @doc "Test hook: drop everything."
  def flush, do: :ets.delete_all_objects(@table)

  defp fresh(key) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, result, expires_at}] when expires_at > now -> {:ok, result}
      _ -> :miss
    end
  end

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    schedule_sweep()
    {:ok, %{inflight: %{}}}
  end

  @impl true
  def handle_call({:run, key, ds, sql}, from, state) do
    # The entry may have landed while this call was queued.
    case fresh(key) do
      {:ok, result} ->
        {:reply, result, state}

      :miss ->
        case state.inflight do
          %{^key => waiters} ->
            {:noreply, put_in(state.inflight[key], [from | waiters])}

          _ ->
            server = self()

            Task.start(fn ->
              result =
                try do
                  Runner.run(ds, sql)
                rescue
                  _ -> {:error, "query runner crashed"}
                end

              send(server, {:done, key, result})
            end)

            {:noreply, put_in(state.inflight[key], [from])}
        end
    end
  end

  @impl true
  def handle_info({:done, key, result}, state) do
    :ets.insert(@table, {key, result, System.monotonic_time(:millisecond) + @ttl_ms})

    {waiters, inflight} = Map.pop(state.inflight, key, [])
    Enum.each(waiters, &GenServer.reply(&1, result))

    {:noreply, %{state | inflight: inflight}}
  end

  def handle_info(:sweep, state) do
    now = System.monotonic_time(:millisecond)
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @ttl_ms)
end
