defmodule Aveline.Account do
  @moduledoc """
  The context module for all things related to user accounts.
  """

  alias Aveline.Account.LoginToken
  alias Aveline.Account.User
  alias Aveline.Repo

  def get_user_by_id(id) do
    Repo.get(User, id)
  end

  def get_user_by_id!(id) do
    Repo.get!(User, id)
  end

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user (!) from the `user_id` in the session or returns `nil` if there is no `user_id` in the session.
  """
  def get_user_from_session_if_present!(%{"user_id" => user_id}), do: get_user_by_id!(user_id)
  def get_user_from_session_if_present!(_), do: nil

  @doc """
  Returns the user for a valid login token, or nil.
  """
  def get_user_for_valid_login_code(code) do
    case get_login_token_by_code(code) do
      %LoginToken{user_id: user_id} ->
        get_user_by_id!(user_id)

      _ ->
        nil
    end
  end

  @doc """
  Insert a login token for a given `user_id`.
  """
  def insert_new_login_token!(user_id) do
    LoginToken.new_login_token_changeset(user_id)
    |> Repo.insert!()
  end

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.
  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, check_unique_email: false)
  end

  # Private

  defp get_login_token_by_code(code) do
    Repo.get_by(LoginToken, %{code: code})
  end
end
