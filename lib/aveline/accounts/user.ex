defmodule Aveline.Accounts.User do
  @moduledoc """
  Minimal user schema for v0. Just an id and a username.
  Real auth will be wired up later.
  """
  use Aveline.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:id, :username]}
  schema "users" do
    field :username, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username])
    |> validate_required([:username])
    |> validate_length(:username, min: 1, max: 60)
    |> unique_constraint(:username)
  end
end
