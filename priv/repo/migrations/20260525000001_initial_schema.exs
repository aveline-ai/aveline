defmodule Aveline.Repo.Migrations.InitialSchema do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :username, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:username])
  end
end
