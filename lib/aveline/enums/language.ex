defmodule Aveline.Enums.Language do
  @moduledoc """
  A wrapper around the languages we support.
  """
  @languages ~w(english french spanish german italian japanese korean)a

  @doc """
  Returns a list of all supported languages.
  """
  def languages, do: @languages

  @doc """
  Converts a string to a language atom.
  """
  def from_string!(string) when is_binary(string) do
    string
    |> String.to_existing_atom()
    |> case do
      language when language in @languages -> language
      _ -> raise "Invalid language: #{string}"
    end
  end
end
