defmodule Aveline.Accounts do
  @moduledoc """
  The Accounts context. Minimal v0 — just enough to fetch users by id/username.
  Real auth will be wired up later.
  """

  alias Aveline.Accounts.User
  alias Aveline.Repo

  def get_user(id), do: Repo.get(User, id)

  def get_user_by_username(username) when is_binary(username) do
    Repo.get_by(User, username: username)
  end

  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end
end
