defmodule Aveline.Enums.AuthorKind do
  @moduledoc """
  A wrapper around the author kinds we support.
  """

  alias Aveline.Enums.Helpers

  defmacro user, do: quote(do: :user)
  defmacro ai, do: quote(do: :ai)

  @doc """
  Returns a list of all supported author kinds.
  """
  def author_kinds, do: [user(), ai()]

  @doc """
  Converts a string to an author kind atom.
  """
  def from_string!("user"), do: user()
  def from_string!("ai"), do: ai()
  def from_string!(string), do: raise("Invalid author kind: #{string}")

  @doc """
  A type-smart enum mapper. Raises an error if the author kind is invalid.
  """
  def map!(author_kind, %{
        user() => user_value_or_fn,
        ai() => ai_value_or_fn
      }) do
    case author_kind do
      user() -> Helpers.run_fn_or_return_value(user_value_or_fn)
      ai() -> Helpers.run_fn_or_return_value(ai_value_or_fn)
      _ -> raise("Invalid author kind: #{author_kind}")
    end
  end
end
