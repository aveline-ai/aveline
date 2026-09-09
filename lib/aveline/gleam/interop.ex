defmodule Aveline.Gleam.Interop do
  @moduledoc "Tiny helpers for the Elixir<->Gleam value boundary."

  @doc "nil -> :none, value -> {:some, mapper.(value)}"
  def opt(value, mapper \\ & &1)
  def opt(nil, _mapper), do: :none
  def opt(value, mapper), do: {:some, mapper.(value)}

  @doc "{:some, v} -> v, :none -> nil"
  def unopt({:some, value}), do: value
  def unopt(:none), do: nil
end
