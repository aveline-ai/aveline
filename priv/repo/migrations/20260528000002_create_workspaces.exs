defmodule Aveline.Repo.Migrations.CreateWorkspaces do
  use Ecto.Migration

  def change do
    create table(:workspaces, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :deleted_at, :timestamptz
      add :deleted_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :timestamptz)
    end

    create unique_index(:workspaces, [:slug])
  end
end
