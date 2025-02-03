defmodule Aveline.Schema do
  @moduledoc """
  A simple wrapper around Ecto.Schema to use project defaults.
   * utc_datetime for timestamps by default
   * binary_id for primary / foreign keys by default
  """

  defmacro __using__(_) do
    quote do
      use Ecto.Schema
      @timestamps_opts [type: :utc_datetime]
      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
    end
  end
end
