defmodule Aveline.Enums.AuthorKind do
  @moduledoc """
  A wrapper around the author kinds we support.
  """

  @doc """
  Returns a list of all supported author kinds.
  """
  def author_kinds, do: [user(), ai()]

  def user, do: :user
  def ai, do: :ai

  @doc """
  Converts a string to an author kind atom.
  """
  def from_string!("user"), do: user()
  def from_string!("ai"), do: ai()
  def from_string!(string), do: raise("Invalid author kind: #{string}")
end
