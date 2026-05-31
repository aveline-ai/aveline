defmodule Aveline.Repo.Migrations.CreateWorkspaceInvites do
  use Ecto.Migration

  def change do
    create table(:workspace_invites, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all),
        null: false

      add :code, :string, null: false
      add :created_by_id, references(:users, type: :binary_id, on_delete: :restrict), null: false

      add :revoked_at, :timestamptz
      add :revoked_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :timestamptz)
    end

    # Code is globally unique (URL surface).
    create unique_index(:workspace_invites, [:code])

    # Only one ACTIVE invite per workspace.
    create unique_index(:workspace_invites, [:workspace_id],
             where: "revoked_at IS NULL",
             name: :workspace_invites_one_active_per_workspace_idx
           )
  end
end
