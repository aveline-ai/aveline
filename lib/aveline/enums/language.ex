defmodule Aveline.Enums.Language do
  @moduledoc """
  A wrapper around the languages we support.
  """

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
end
