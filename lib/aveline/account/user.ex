defmodule Aveline.Account.User do
  @moduledoc """
  The schema for the user model.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :admin, :boolean
    field :local_timezone, :string

    timestamps()
  end

  @doc """
  A user changeset for registration.

  It is important to validate the length of email to prevent database truncation
  without warnings, which could lead to unpredictable behaviour.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :local_timezone])
    |> change(admin: false)
    |> validate_email(opts)
    |> validate_required([:admin, :local_timezone])
  end

  defp validate_email(changeset, opts) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> maybe_validate_unique_email(opts)
  end

  defp maybe_validate_unique_email(changeset, opts) do
    if Keyword.get(opts, :check_unique_email, true) do
      changeset
      |> unsafe_validate_unique(:email, Aveline.Repo)
      |> unique_constraint(:email)
    else
      changeset
    end
  end
end
