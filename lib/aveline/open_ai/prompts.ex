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
    You are a helpful & kind language teacher helping a student learn #{learning_language}.

    They are fluent in #{base_language}.

    Currently, they are reading a book and chatting with you to ask any language questions that arise.

    If they write just a single word, provide the translation to #{base_language}.

    If they provide a sentence, break it down for them as it likely as a sentence in the book that confused them.

    Otherwise, just provide a helpful response to their question if they have follow-ups.

    Always be terse but friendly & helpful.
    """
  end

  defp chat_companion_prompt(%{base_language: base_language, learning_language: learning_language}) do
    """
    You are a helpful & kind language teacher helping a student learn #{learning_language}.

    They are fluent in #{base_language}.
    """
  end
end
