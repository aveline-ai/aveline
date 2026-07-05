defmodule Aveline.DataSources.Cache do
  @moduledoc """
  60-second in-memory cache over `Runner.run/2`, keyed by
  {base_data_source_id, query}. Exists so a busy doc can't hammer a
  customer database: N reads within the window cost one query.

  ETS only — results never touch disk or our database. Errors are
  cached too (a down database shouldn't be re-dialed on every read).
  """
  use GenServer

  alias Aveline.DataSources.Runner

  @table __MODULE__
  @ttl_ms 60_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Runner.run/2 through the TTL cache."
  def run(%{base_data_source_id: base} = ds, sql) do
    key = {base, sql}
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, result, expires_at}] when expires_at > now ->
        result

      _ ->
        result = Runner.run(ds, sql)
        :ets.insert(@table, {key, result, now + @ttl_ms})
        result
    end
  end

  @doc "Test hook: drop everything."
  def flush, do: :ets.delete_all_objects(@table)

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    schedule_sweep()
    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.monotonic_time(:millisecond)
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @ttl_ms)
end
