defmodule Aveline.Config do
  @moduledoc """
  Helper functions for accessing application configuration.
  """

  @doc """
  Returns the landing page URL for the application.
  Defaults to "https://aveline.ai" if not configured.
  """
  def landing_page_url! do
    Application.fetch_env!(:aveline, :landing_page_url)
  end
end
