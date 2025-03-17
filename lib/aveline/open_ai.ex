defmodule Aveline.OpenAi do
  @moduledoc """
  A module for interacting with the OpenAI API.
  """

  require Aveline.Enums.AuthorKind
  alias Aveline.Chat
  alias Aveline.Enums
  alias Aveline.OpenAi.Client
  alias Aveline.OpenAi.Prompts
  alias OpenaiEx.Chat.Completions

  # How many messages to include in the context of the AI response.
  @context_message_limit 10

  # Warning: Does not perform any validation. Should not be used directly by the user.
  def generate_chat_completion!(%{
        chat_room_mode: chat_room_mode,
        chat_room_base_language: chat_room_base_language,
        chat_room_learning_language: chat_room_learning_language,
        message_id: message_id,
        user_id: _user_id,
        user_local_timezone: _user_local_timezone
      }) do
    messages = Chat.get_messages_for_ai_completion(%{message_id: message_id, message_limit: @context_message_limit})

    prompt =
      Prompts.get_prompt(%{
        chat_room_mode: chat_room_mode,
        base_language: chat_room_base_language,
        learning_language: chat_room_learning_language
      })

    chat_completion_messages =
      messages
      |> Enum.reverse()
      |> Enum.map(&open_ai_chat_completion_message_from_chat_message/1)

    chat_completion_messages_with_system_prompt =
      [%{role: "system", content: prompt} | chat_completion_messages]

    %{"choices" => [%{"message" => %{"content" => content}}]} =
      Completions.create!(open_ai_client(), %{
        model: "gpt-4o-mini",
        messages: chat_completion_messages_with_system_prompt
      })

    content
  end

  # Private

  defp open_ai_client, do: Client.create_client()

  defp open_ai_chat_completion_message_from_chat_message(%{author_kind: author_kind, content: content}) do
    Enums.AuthorKind.map!(author_kind, %{
      Enums.AuthorKind.user() => %{role: "user", content: content},
      Enums.AuthorKind.ai() => %{role: "assistant", content: content}
    })
  end
end
