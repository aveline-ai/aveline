defmodule Aveline.Enums.Helpers do
  @moduledoc """
  A module for helper functions for enums.
  """

  def run_fn_or_return_value(value_or_fn) when is_function(value_or_fn, 0), do: value_or_fn.()
  def run_fn_or_return_value(value_or_fn), do: value_or_fn
end
