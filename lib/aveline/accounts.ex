defmodule Aveline.Accounts do
  @moduledoc """
  The Accounts context.
  """

  alias Aveline.Accounts.User
  alias Aveline.Accounts.UserToken
  alias Aveline.Repo

  ## User

  def get_user_by_id(id) do
    Repo.get(User, id)
  end

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  def get_user_by_email_and_password(email, password) when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: false)
  end

  ## User Token

  def generate_user_session_token!(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end
end
