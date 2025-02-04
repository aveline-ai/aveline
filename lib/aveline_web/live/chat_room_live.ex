defmodule AvelineWeb.ChatRoomLive do
  use AvelineWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1>Chat Room</h1>
    </div>
    """
  end
end
