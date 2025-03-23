defmodule AvelineWeb.ChatRoomListSkeletonComponent do
  @moduledoc """
  This component is used to display a skeleton of a chat room list (while loading).
  """
  use Phoenix.Component

  def chat_room_list_skeleton(assigns) do
    ~H"""
    <div role="status" class="max-w-md flex flex-col gap-0 rounded-sm shadow-sm animate-pulse">
      <.chat_room_skeleton_item />
      <.chat_room_skeleton_item />
      <.chat_room_skeleton_item />
      <span class="sr-only">Loading...</span>
    </div>
    """
  end

  defp chat_room_skeleton_item(assigns) do
    ~H"""
    <div class="flex flex-col items-left p-4 gap-4 border-b border-border-secondary">
      <div class="flex flex-col justify-between gap-1">
        <div class="h-5 bg-gray-300 rounded dark:bg-gray-600 w-60"></div>
        <div class="flex flex-row gap-1">
          <div class="w-16 h-[22px] bg-gray-200 rounded dark:bg-gray-700"></div>
          <div class="w-20 h-[22px] bg-gray-200 rounded dark:bg-gray-700"></div>
        </div>
      </div>
      <div class="w-full h-10 flex flex-col justify-between gap-1">
        <div class="w-full h-4 bg-gray-200 rounded dark:bg-gray-700"></div>
        <div class="w-full h-4 bg-gray-200 rounded dark:bg-gray-700"></div>
      </div>
    </div>
    """
  end
end
