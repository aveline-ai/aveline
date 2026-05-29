defmodule Aveline.Repo.Migrations.CreateWorkspaceMemberships do
  use Ecto.Migration

  def change do
    create table(:workspace_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workspace_id,
          references(:workspaces, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, null: false, default: "member"

      timestamps(type: :timestamptz)
    end

    create unique_index(:workspace_memberships, [:workspace_id, :user_id])
    create index(:workspace_memberships, [:user_id])
  end
end
