defmodule Aveline.Tokens.ApiToken do
  @moduledoc false
  use Aveline.Schema
  import Ecto.Changeset

  alias Aveline.Accounts.User

  schema "api_tokens" do
    field :name, :string
    field :token_hash, :string
    field :token_prefix, :string
    field :token_suffix, :string
    field :last_used_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    belongs_to :user, User, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:user_id, :name, :token_hash, :token_prefix, :token_suffix])
    |> validate_required([:user_id, :name, :token_hash, :token_prefix])
    |> unique_constraint(:token_hash)
  end
end
