defmodule AvelineWeb.HomeLive do
  use AvelineWeb, :live_view

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl font-bold">Home</h1>
    </div>
    """
  end
end
