defmodule Aveline.OpenAi do
  @moduledoc """
  A module for interacting with the OpenAI API.
  """

  alias OpenaiEx
  alias Aveline.OpenAi.Client

  def generate_chat_completion!(%{chat_room_id: chat_room_id, message_id: message_id}) do
    # TODO fetch messages from the database, convert to OpenAI format, call the API, return the response.
    Process.sleep(1000)
    "Placeholder AI response..."
  end

  defp open_ai_client, do: Client.create_client()
end
