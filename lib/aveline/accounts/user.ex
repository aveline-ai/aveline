defmodule Aveline.Accounts.User do
  @moduledoc """
  User schema for v0.
  """
  use Aveline.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:id, :username, :email, :display_name]}
  schema "users" do
    field :username, :string
    field :email, :string
    field :display_name, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :email, :display_name])
    |> validate_required([:username, :email])
    |> validate_length(:username, min: 1, max: 60)
    |> validate_format(:username, ~r/^[a-z0-9][a-z0-9-]*$/,
      message: "must be lowercase alphanumeric with optional hyphens"
    )
    |> validate_length(:email, min: 3, max: 255)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "must be a valid email")
    |> validate_length(:display_name, max: 120)
    |> unique_constraint(:username)
    |> unique_constraint(:email)
  end
end
