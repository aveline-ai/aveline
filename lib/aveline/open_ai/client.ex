defmodule Aveline.OpenAi.Client do
  @moduledoc """
  A client for the OpenAI API.
  """

  alias OpenaiEx

  def create_client do
    OpenaiEx.new(get_api_key(), get_organization_key())
  end

  # Private

  defp get_api_key do
    Application.get_env(:aveline, :openai)[:api_key]
  end

  defp get_organization_key do
    Application.get_env(:aveline, :openai)[:organization_key]
  end
end
