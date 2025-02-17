defmodule AvelineWeb.ChatLive do
  use AvelineWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-full w-full">
      <div class="w-full lg:w-96 border-r border-gray-200">
        chat boxes
      </div>
      <div class="hidden lg:block h-full flex-1">
        <h1 class="text-2xl font-bold">Chat</h1>
      </div>
    </div>
    """
  end
end
