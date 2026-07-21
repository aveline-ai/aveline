defmodule Aveline.Repo.Migrations.DocVisibilityAndShares do
  use Ecto.Migration

  # Doc permissions v1 (see the doc-permissions TIP): visibility is
  # private | workspace on the doc row, carried across versions like
  # pin_slot and changed in place on the current row; "some people" is
  # private plus doc_shares rows. The orientation doc is forced
  # workspace-visible at the row level, same spirit as its undeletable
  # check.
  def change do
    alter table(:docs) do
      add :visibility, :text, null: false, default: "workspace"
    end

    create constraint(:docs, :docs_visibility_check,
             check: "visibility IN ('private', 'workspace')"
           )

    create constraint(:docs, :docs_orientation_workspace_check,
             check: "NOT orientation OR visibility = 'workspace'"
           )

    create table(:doc_shares, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :base_doc_id, :binary_id, null: false
      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :text, null: false
      add :granted_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:doc_shares, :doc_shares_role_check, check: "role IN ('viewer', 'editor')")

    create unique_index(:doc_shares, [:base_doc_id, :user_id],
             where: "deleted_at IS NULL",
             name: :doc_shares_live_unique
           )

    create index(:doc_shares, [:user_id])
    create index(:docs, [:workspace_id, :visibility])
  end
end
