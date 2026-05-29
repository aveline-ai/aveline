defmodule Aveline.Accounts do
  @moduledoc """
  The Accounts context.

  Users are not soft-deleted in v0; they're a foundational table referenced
  everywhere. `base_query/0` is provided for shape consistency with other
  contexts.
  """

  import Ecto.Query
  alias Aveline.Accounts.User
  alias Aveline.Repo

  def base_query, do: from(u in User)

  def get_user(id) when is_binary(id), do: Repo.get(User, id)
  def get_user(_), do: nil

  def get_user!(id), do: Repo.get!(User, id)

  def get_user_by_username(username) when is_binary(username) do
    Repo.get_by(User, username: username)
  end

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: String.downcase(email))
  end

  def get_user_by_email(_), do: nil

  def create_user(attrs) do
    %User{}
    |> User.changeset(normalize_email(attrs))
    |> Repo.insert()
  end

  def upsert_user_by_email(attrs) do
    attrs = normalize_email(attrs)

    case get_user_by_email(attrs["email"] || attrs[:email]) do
      nil -> create_user(attrs)
      user -> {:ok, user}
    end
  end

  defp normalize_email(attrs) when is_map(attrs) do
    cond do
      Map.has_key?(attrs, "email") and is_binary(attrs["email"]) ->
        Map.put(attrs, "email", String.downcase(attrs["email"]))

      Map.has_key?(attrs, :email) and is_binary(attrs[:email]) ->
        Map.put(attrs, :email, String.downcase(attrs[:email]))

      true ->
        attrs
    end
  end
end
