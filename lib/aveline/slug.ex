defmodule Aveline.Slug do
  @moduledoc """
  Slug helpers — format `[a-z0-9][a-z0-9-]*`, length 1–60.

  Derivation: lowercase, replace runs of `[^a-z0-9]+` with `-`, then trim
  leading/trailing `-`. Returns `nil` if the result is empty.
  """

  @slug_regex ~r/^[a-z0-9][a-z0-9-]*$/
  @max_len 60

  def regex, do: @slug_regex
  def max_length, do: @max_len

  @doc """
  Derive a slug from arbitrary text. Returns nil if nothing remains.
  """
  def derive(nil), do: nil

  def derive(text) when is_binary(text) do
    derived =
      text
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.slice(0, @max_len)
      |> String.trim("-")

    if derived == "", do: nil, else: derived
  end

  @doc """
  Validate slug format. Returns :ok or {:error, reason}.
  """
  def validate(slug) when is_binary(slug) do
    if String.length(slug) >= 1 and String.length(slug) <= @max_len and
         Regex.match?(@slug_regex, slug) do
      :ok
    else
      {:error, :invalid_slug}
    end
  end

  def validate(_), do: {:error, :invalid_slug}
end
