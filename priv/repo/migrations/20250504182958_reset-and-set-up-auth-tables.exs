defmodule :"Elixir.Aveline.Repo.Migrations.Reset-and-set-up-auth-tables" do
  use Ecto.Migration

  def up do
    # Enable citext extension, which allows us to use the citext type for emails (case-insensitive)
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    # Drop models related to chatting
    drop table(:messages)
    drop table(:chat_room_memberships)
    drop table(:chat_rooms)

    # Drop login_tokens because we're moving to the phx standard of user_tokens
    drop table(:login_tokens)

    # Drop users because we'll recreate it with the correct columns
    drop table(:users)

    # Recreate users with the correct columns
    create table(:users) do
      add :email, :citext, null: false
      add :admin, :boolean, null: false
      add :local_timezone, :string, null: false
      add :first_name, :string, null: false
      add :confirmed_at, :utc_datetime_usec
      add :hashed_password, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:email])

    # Create user_tokens table
    create table(:users_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
  end

  def down do
    raise "This migration is irreversible"
  end
end
