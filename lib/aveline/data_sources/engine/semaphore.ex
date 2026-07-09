defmodule Aveline.DataSources.Engine.Semaphore do
  @moduledoc """
  A counting semaphore that caps concurrent DuckDB engine runs, and —
  crucially — releases a slot when the holder process dies, not just on
  an explicit release. Chart runs execute inside LiveView `start_async`
  tasks; a viewer navigating away mid-run kills that task with a
  non-`:normal` exit, so a `try/after` release never runs. This monitors
  each holder and frees its slot on `:DOWN`, so a leaked slot can't
  permanently shrink capacity.

  `acquire/0` grants immediately or returns `:full` (the caller
  spin-waits with a deadline); `release/0` frees the caller's slot.
  """
  use GenServer

  @default_max 4

  def start_link(opts) do
    max = Keyword.get(opts, :max, @default_max)
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, max, name: name)
  end

  @doc "Grab a slot for the calling process, or :full if at capacity."
  def acquire(server \\ __MODULE__), do: GenServer.call(server, :acquire)

  @doc "Release the calling process's slot."
  def release(server \\ __MODULE__), do: GenServer.cast(server, {:release, self()})

  @impl true
  def init(max), do: {:ok, %{max: max, holders: %{}}}

  @impl true
  def handle_call(:acquire, {pid, _tag}, %{max: max, holders: holders} = state) do
    if map_size(holders) >= max do
      {:reply, :full, state}
    else
      ref = Process.monitor(pid)
      {:reply, :ok, %{state | holders: Map.put(holders, pid, ref)}}
    end
  end

  @impl true
  def handle_cast({:release, pid}, state), do: {:noreply, drop(state, pid)}

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Holder died without releasing (killed mid-run) — free its slot.
    {:noreply, drop(state, pid, monitored: true)}
  end

  defp drop(state, pid, opts \\ []) do
    case Map.pop(state.holders, pid) do
      {nil, _holders} ->
        state

      {ref, holders} ->
        unless opts[:monitored], do: Process.demonitor(ref, [:flush])
        %{state | holders: holders}
    end
  end
end
