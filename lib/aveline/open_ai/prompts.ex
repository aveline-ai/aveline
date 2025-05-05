defmodule Aveline.OpenAi.Prompts do
  @moduledoc """
  A module for managing OpenAI prompts.
  """

  def get_prompt(%{mode: _, base_language: base_language, learning_language: learning_language}) do
    """
    You are a helpful & kind language teacher helping a student learn #{learning_language}.

    They are fluent in #{base_language}.
    """
  end
end
