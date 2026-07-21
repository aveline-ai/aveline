defmodule Aveline.Repo.Migrations.ViewVisibilityAndShares do
  use Ecto.Migration

  # View permissions: the doc model copied onto views. visibility is
  # private | workspace on the view row; view_shares grant specific
  # members viewer (use) or editor (also edit config) access. Views
  # never had an owner (created_by_id moves with each edit), so owner_id
  # is added and backfilled from each base view's version-1 creator.
  def up do
    alter table(:views) do
      add :owner_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :visibility, :text, null: false, default: "workspace"
    end

    execute """
    UPDATE views v
    SET owner_id = f.created_by_id
    FROM (
      SELECT DISTINCT ON (base_view_id) base_view_id, created_by_id
      FROM views
      ORDER BY base_view_id, version_number ASC
    ) f
    WHERE v.base_view_id = f.base_view_id
    """

    # Fallback for views whose v1 creator was since deleted (FK niled):
    # the workspace's earliest member takes ownership.
    execute """
    UPDATE views v
    SET owner_id = m.user_id
    FROM (
      SELECT DISTINCT ON (workspace_id) workspace_id, user_id
      FROM workspace_memberships
      ORDER BY workspace_id, inserted_at ASC
    ) m
    WHERE v.owner_id IS NULL AND v.workspace_id = m.workspace_id
    """

    create constraint(:views, :views_visibility_check,
             check: "visibility IN ('private', 'workspace')"
           )

    # The sidebar is a team surface: a pinned view can never be private.
    create constraint(:views, :views_pinned_workspace_check,
             check: "NOT pinned OR visibility = 'workspace'"
           )

    create table(:view_shares, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :base_view_id, :binary_id, null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :text, null: false
      add :granted_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:view_shares, :view_shares_role_check,
             check: "role IN ('viewer', 'editor')"
           )

    create unique_index(:view_shares, [:base_view_id, :user_id],
             where: "deleted_at IS NULL",
             name: :view_shares_live_unique
           )

    create index(:view_shares, [:user_id])
  end

  def down do
    drop table(:view_shares)
    drop constraint(:views, :views_pinned_workspace_check)
    drop constraint(:views, :views_visibility_check)

    alter table(:views) do
      remove :visibility
      remove :owner_id
    end
  end
end
