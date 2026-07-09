defmodule Aveline.DataSources.Engine.SemaphoreTest do
  @moduledoc """
  The engine semaphore must free a slot when its holder DIES, not only on
  an explicit release — otherwise a LiveView chart run killed mid-flight
  (viewer navigates away) leaks capacity until the node restarts.
  """
  use ExUnit.Case, async: true

  alias Aveline.DataSources.Engine.Semaphore

  setup do
    # A private instance (custom name) so we don't touch the app-wide one.
    name = :"sem_#{System.unique_integer([:positive])}"
    pid = start_supervised!(%{id: name, start: {Semaphore, :start_link, [[max: 2, name: name]]}})
    {:ok, sem: pid}
  end

  # Spawn a process that acquires a slot and holds it until told to stop.
  defp holder(sem) do
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        :ok = GenServer.call(sem, :acquire)
        send(parent, {:held, self()})
        receive do: (:stop -> :ok)
      end)

    assert_receive {:held, ^pid}, 1000
    {pid, ref}
  end

  test "grants up to max, then returns :full", %{sem: sem} do
    {a, _} = holder(sem)
    {b, _} = holder(sem)
    assert GenServer.call(sem, :acquire) == :full
    send(a, :stop)
    send(b, :stop)
  end

  test "a slot frees when its holder dies without releasing", %{sem: sem} do
    {a, _} = holder(sem)
    {killed, ref} = holder(sem)
    assert GenServer.call(sem, :acquire) == :full

    # Kill the holder WITHOUT releasing — the leak scenario.
    Process.exit(killed, :kill)
    assert_receive {:DOWN, ^ref, :process, ^killed, :killed}, 1000

    assert eventually(fn -> GenServer.call(sem, :acquire) == :ok end)
    send(a, :stop)
  end

  defp eventually(fun, tries \\ 50) do
    cond do
      fun.() -> true
      tries <= 0 -> false
      true ->
        Process.sleep(10)
        eventually(fun, tries - 1)
    end
  end
end
