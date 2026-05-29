defmodule Aveline.Accounts.User do
  @moduledoc """
  User schema for v0. Email is optional — signups only require a username.
  """
  use Aveline.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:id, :username, :email, :display_name, :avatar_url]}
  schema "users" do
    field :username, :string
    field :email, :string
    field :display_name, :string
    field :avatar_url, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :email, :display_name, :avatar_url])
    |> validate_required([:username])
    |> validate_length(:username, min: 2, max: 60)
    |> validate_format(:username, ~r/^[a-z0-9][a-z0-9-]*$/,
      message: "lowercase letters, digits, and hyphens only (starts with a letter or digit)"
    )
    |> validate_length(:display_name, max: 120)
    |> maybe_validate_email()
    |> unique_constraint(:username)
    |> unique_constraint(:email)
  end

  defp maybe_validate_email(changeset) do
    case get_field(changeset, :email) do
      nil ->
        changeset

      "" ->
        put_change(changeset, :email, nil)

      _ ->
        changeset
        |> validate_length(:email, min: 3, max: 255)
        |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "must be a valid email")
    end
  end
end
