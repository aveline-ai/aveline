defmodule Aveline.Schema do
  @moduledoc """
  A simple wrapper around Ecto.Schema to use utc_datetime for timestamps by default.

  In the app, replace `use Ecto.Schema` with `use Aveline.Schema`.
  """
  defmacro __using__(_) do
    quote do
      use Ecto.Schema
      @timestamps_opts [type: :utc_datetime]
    end
  end
end
