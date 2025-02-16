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
      TODO
    </div>
    """
  end
end
