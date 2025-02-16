defmodule AvelineWeb.LearnLive do
  use AvelineWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl font-bold">Learn</h1>
    </div>
    """
  end
end
