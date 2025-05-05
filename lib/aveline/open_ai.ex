defmodule Aveline.OpenAi do
  @moduledoc """
  A module for interacting with the OpenAI API.
  """

  alias Aveline.OpenAi.Client
  alias Aveline.OpenAi.Prompts
  alias OpenaiEx.Chat.Completions

  @model "gpt-4o"

  # NOTE: This is a bit nonsensical because it's ported from Aveline v0. I'm leaving this as helpful boilerplate for
  #       future reference.
  def generate_chat_completion!(%{
        base_language: base_language,
        learning_language: learning_language
      }) do
    prompt =
      Prompts.get_prompt(%{
        mode: "todo",
        base_language: base_language,
        learning_language: learning_language
      })

    chat_completion_messages_with_system_prompt =
      [%{role: "system", content: prompt} | %{role: "user", content: "Hello!"}]

    %{"choices" => [%{"message" => %{"content" => content}}]} =
      Completions.create!(open_ai_client(), %{
        model: @model,
        messages: chat_completion_messages_with_system_prompt
      })

    content
  end

  # Private

  defp open_ai_client, do: Client.create_client()
end
