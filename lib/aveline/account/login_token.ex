defmodule Aveline.Account.LoginToken do
  @moduledoc """
  Schema for storing login tokens that can be used to authenticate users.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @rand_size 32

  schema "login_tokens" do
    field :code, :string
    belongs_to :user, Aveline.Account.User

    timestamps()
  end

  @doc """
  Creates a changeset for a new login token.
  """
  def new_login_token_changeset(user_id, code_type \\ :url_friendly) do
    %__MODULE__{}
    |> cast(%{user_id: user_id}, [:user_id])
    |> validate_required([:user_id])
    |> put_change(:code, generate_code(code_type))
    |> foreign_key_constraint(:user_id)
  end

  # Private

  defp generate_code(:url_friendly) do
    @rand_size
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
