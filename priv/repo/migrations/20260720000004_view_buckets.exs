defmodule Aveline.Repo.Migrations.ViewBuckets do
  use Ecto.Migration

  # View buckets (see the view-buckets TIP): views live in exactly one
  # bucket — Team (everyone, the default), Yours (personal), or a
  # project bucket shared by binary membership. Supersedes the per-view
  # shares model from earlier today: workspace views move to the Team
  # bucket, private views to their owner's personal bucket, and
  # view_shares + views.visibility are dropped (the bucket IS the
  # audience).
  def up do
    create table(:view_buckets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :text, null: false
      add :kind, :text, null: false
      add :owner_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:view_buckets, :view_buckets_kind_check,
             check: "kind IN ('team', 'personal', 'project')"
           )

    # One Team bucket per workspace; one personal bucket per person per
    # workspace; project names unique among live buckets.
    create unique_index(:view_buckets, [:workspace_id],
             where: "kind = 'team' AND deleted_at IS NULL",
             name: :view_buckets_one_team_per_workspace
           )

    create unique_index(:view_buckets, [:workspace_id, :owner_id],
             where: "kind = 'personal' AND deleted_at IS NULL",
             name: :view_buckets_one_personal_per_user
           )

    create unique_index(:view_buckets, [:workspace_id, :name],
             where: "deleted_at IS NULL",
             name: :view_buckets_live_name_unique
           )

    create table(:view_bucket_members, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :bucket_id, references(:view_buckets, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :added_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:view_bucket_members, [:bucket_id, :user_id],
             where: "deleted_at IS NULL",
             name: :view_bucket_members_live_unique
           )

    create index(:view_bucket_members, [:user_id])

    alter table(:views) do
      add :bucket_id, references(:view_buckets, type: :binary_id, on_delete: :nilify_all)
    end

    # Team bucket per existing workspace.
    execute """
    INSERT INTO view_buckets (id, workspace_id, name, kind, inserted_at, updated_at)
    SELECT gen_random_uuid(), w.id, 'team', 'team', NOW(), NOW()
    FROM workspaces w
    """

    # Personal bucket for every owner of a private view (others created
    # lazily at runtime).
    execute """
    INSERT INTO view_buckets (id, workspace_id, name, kind, owner_id, inserted_at, updated_at)
    SELECT gen_random_uuid(), f.workspace_id, 'personal-' || u.username, 'personal', f.owner_id, NOW(), NOW()
    FROM (
      SELECT DISTINCT workspace_id, owner_id
      FROM views
      WHERE visibility = 'private' AND owner_id IS NOT NULL
    ) f
    JOIN users u ON u.id = f.owner_id
    """

    # Route every view row (all versions) into its bucket.
    execute """
    UPDATE views v
    SET bucket_id = b.id
    FROM view_buckets b
    WHERE b.workspace_id = v.workspace_id
      AND ((v.visibility = 'workspace' AND b.kind = 'team')
        OR (v.visibility = 'private' AND b.kind = 'personal' AND b.owner_id = v.owner_id))
    """

    drop table(:view_shares)
    drop constraint(:views, :views_visibility_check)

    alter table(:views) do
      remove :visibility
    end
  end

  def down do
    raise "irreversible: the per-view shares model was deleted, not deprecated"
  end
end
