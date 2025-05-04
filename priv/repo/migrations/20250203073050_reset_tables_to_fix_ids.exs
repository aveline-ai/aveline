defmodule Aveline.Repo.Migrations.ResetTablesToFixIds do
  use Ecto.Migration

  def change do
    drop table(:login_tokens)
    drop table(:users)

    create table(:users) do
      add :email, :string, null: false
      add :admin, :boolean, null: false
      add :local_timezone, :string, null: false

      timestamps()
    end

    create unique_index(:users, [:email])

    create table(:login_tokens) do
      add :code, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:login_tokens, [:code])
  end
end
