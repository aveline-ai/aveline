defmodule Aveline.OpenAi.Prompts do
  @moduledoc """
  A module for managing OpenAI prompts.
  """

  require Aveline.Enums.ChatRoomMode
  alias Aveline.Enums

  def get_prompt(%{chat_room_mode: chat_room_mode, base_language: base_language, learning_language: learning_language}) do
    Enums.ChatRoomMode.map!(
      chat_room_mode,
      %{
        Enums.ChatRoomMode.book_buddy() =>
          book_buddy_prompt(%{base_language: base_language, learning_language: learning_language}),
        Enums.ChatRoomMode.chat_companion() =>
          chat_companion_prompt(%{base_language: base_language, learning_language: learning_language})
      }
    )
  end

  defp book_buddy_prompt(%{base_language: base_language, learning_language: learning_language}) do
    """
    You are a terse & effective language teacher helping a student learn #{learning_language}.

    They are fluent in #{base_language}.

    Currently, they are reading a book and chatting with you to ask any language questions that arise.

    To make it simple for the student to get help from you, the two of you have agreed upon the following format:

    1. If they write a single word, translate it and provide any extra context if the word warrants it. If it's a noun,
      provide the gender if it applies to the language they are learning.
    2. If they write a full sentence and starred certain words like this* then focus on explaining the starred words
       within the context of the sentence.
    3. If they write a full sentence and did not star any words, break down the entire sentence for them.
    4. They must also be asking questions directly / chatting with you instead of dropping words/sentences. If that is
       the case, provide a helpful response.

    Remember, always be terse & effective. Do not say anything like "let me know if you have more questions" or similar
    at the end of your responses.
    """
  end

  defp chat_companion_prompt(%{base_language: base_language, learning_language: learning_language}) do
    """
    You are a helpful & kind language teacher helping a student learn #{learning_language}.

    They are fluent in #{base_language}.
    """
  end
end
