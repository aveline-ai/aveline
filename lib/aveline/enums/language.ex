defmodule Aveline.Enums.Language do
  @moduledoc """
  A wrapper around the languages we support.
  """

  @doc """
  Returns a list of all supported languages.
  """
  def languages, do: [english(), french(), spanish(), german(), italian(), japanese(), korean()]

  def english, do: :english
  def french, do: :french
  def spanish, do: :spanish
  def german, do: :german
  def italian, do: :italian
  def japanese, do: :japanese
  def korean, do: :korean

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
