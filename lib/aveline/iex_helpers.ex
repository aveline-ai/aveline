defmodule Aveline.IexHelpers do
  @moduledoc """
  Convenience aliases and helpers for IEx sessions.

  Do `use Aveline.IexHelpers` in your iex repl (iex -S mix) to get common aliases.
  """

  alias Aveline.Repo

  defmacro __using__(_) do
    quote do
      import Ecto.Query
      import Aveline.IexHelpers

      alias Aveline.Accounts
      alias Aveline.Accounts.User
      alias Aveline.Repo

      :ok
    end
  end

  def local_time_now(timezone \\ "America/Los_Angeles") do
    DateTime.utc_now()
    |> DateTime.shift_zone!(timezone)
  end

  def repo_count_all(x) do
    Repo.all(x) |> Enum.count()
  end
end
