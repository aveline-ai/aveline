defmodule Aveline.Repo.Migrations.ExtendUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :email, :string, null: false
      add :display_name, :string
    end

    create unique_index(:users, [:email])
  end
end
