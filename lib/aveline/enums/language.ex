defmodule Aveline.Enums.Language do
  @moduledoc """
  A wrapper around the languages we support.
  """

  alias Aveline.Enums.Helpers

  defmacro english, do: quote(do: :english)
  defmacro french, do: quote(do: :french)
  defmacro spanish, do: quote(do: :spanish)
  defmacro german, do: quote(do: :german)
  defmacro italian, do: quote(do: :italian)
  defmacro japanese, do: quote(do: :japanese)
  defmacro korean, do: quote(do: :korean)

  @doc """
  Returns a list of all supported languages.
  """
  def languages, do: [english(), french(), spanish(), german(), italian(), japanese(), korean()]

  @doc """
  Converts a string to a language atom.
  """
  def from_string!("english"), do: english()
  def from_string!("french"), do: french()
  def from_string!("spanish"), do: spanish()
  def from_string!("german"), do: german()
  def from_string!("italian"), do: italian()
  def from_string!("japanese"), do: japanese()
  def from_string!("korean"), do: korean()
  def from_string!(string), do: raise("Invalid language: #{string}")

  @doc """
  A type-smart enum mapper. Raises an error if the language is invalid.
  """
  def map!(language, %{
        english() => english_value_or_fn,
        french() => french_value_or_fn,
        spanish() => spanish_value_or_fn,
        german() => german_value_or_fn,
        italian() => italian_value_or_fn,
        japanese() => japanese_value_or_fn,
        korean() => korean_value_or_fn
      }) do
    case language do
      english() -> Helpers.run_fn_or_return_value(english_value_or_fn)
      french() -> Helpers.run_fn_or_return_value(french_value_or_fn)
      spanish() -> Helpers.run_fn_or_return_value(spanish_value_or_fn)
      german() -> Helpers.run_fn_or_return_value(german_value_or_fn)
      italian() -> Helpers.run_fn_or_return_value(italian_value_or_fn)
      japanese() -> Helpers.run_fn_or_return_value(japanese_value_or_fn)
      korean() -> Helpers.run_fn_or_return_value(korean_value_or_fn)
      _ -> raise("Invalid language: #{language}")
    end
  end
end
