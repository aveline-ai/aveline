defmodule Aveline.IexHelpers do
  @moduledoc """
  This module is not to be used in the codebase, it is specifically to make using IEX easier both in dev and prod.

  Do `use Aveline.IexHelpers` in your iex repl (iex -S mix) to get some helpful aliases for you.

  Additional iex-only helpers can be placed here (eg. to help inspect logs manually in prod).
  """

  alias Aveline.Accounts.User
  alias Aveline.Repo

  defmacro __using__(_) do
    quote do
      import Ecto.Query
      import Aveline.IexHelpers

      alias Aveline.Accounts
      alias Aveline.Accounts.User

      alias Aveline.Enums.Language
      alias Aveline.Repo

      :ok
    end
  end

  def get_user(:arie) do
    Repo.get_by!(User, email: "arie.milner@hey.com")
  end

  def local_time_now(timezone \\ "America/Los_Angeles") do
    DateTime.utc_now()
    |> DateTime.shift_zone!(timezone)
  end

  def repo_count_all(x) do
    Repo.all(x) |> Enum.count()
  end
end
