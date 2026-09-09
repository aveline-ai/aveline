defmodule AvelineWeb.Api.GleamAdapter do
  @moduledoc """
  Maps Gleam handler results into the shapes FallbackController already
  understands, so the error-code catalog keeps one owner.
  """

  @doc "Convert a Gleam ApiError (src/aveline/core/error.gleam) to a fallback tuple."
  def error(:not_found), do: {:error, :not_found}
  def error({:forbidden, message}), do: {:error, :forbidden, message}
  def error({:invalid, code, message}), do: {:error, String.to_atom(code), message}

  @doc """
  Convert a Gleam docs-domain error (src/aveline/docs/doc_error.gleam)
  to a fallback tuple. The structured variants map onto tuples the
  FallbackController already renders (message text stays owned there);
  `passthrough` returns a raw Elixir error term from a coarse write cap
  unchanged.
  """
  def doc_error({:api, err}), do: error(err)
  def doc_error(:orientation_undeletable), do: {:error, :orientation_undeletable}
  def doc_error(:pin_limit_reached), do: {:error, :pin_limit_reached}
  def doc_error({:pin_slot_taken, slot, occupant}), do: {:error, {:pin_slot_taken, slot, occupant}}
  def doc_error(:not_user_deleted), do: {:error, :not_user_deleted}
  def doc_error({:unknown_authors, usernames}), do: {:error, {:unknown_authors, usernames}}
  def doc_error(:not_member), do: {:error, :not_member}
  def doc_error({:passthrough, reason}), do: reason
end
