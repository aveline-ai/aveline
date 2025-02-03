defmodule AvelineWeb.CounterLive do
  use AvelineWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, count: 0)}
  end

  def handle_event("increment", _, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end

  def handle_event("decrement", _, socket) do
    {:noreply, update(socket, :count, &(&1 - 1))}
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center space-y-4">
      <h1 class="text-2xl font-bold">Counter: {@count}</h1>
      <div class="flex space-x-4">
        <button phx-click="decrement" class="px-4 py-2 text-white bg-red-500 rounded hover:bg-red-600">
          -
        </button>
        <button
          phx-click="increment"
          class="px-4 py-2 text-white bg-green-500 rounded hover:bg-green-600"
        >
          +
        </button>
      </div>
    </div>
    """
  end
end
