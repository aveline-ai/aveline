defmodule AvelineWeb.ChatLive do
  use AvelineWeb, :live_view
  alias Aveline.ChatRoom

  @impl true
  def mount(params, session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl font-bold">Chat</h1>
    </div>
    """
  end
end
