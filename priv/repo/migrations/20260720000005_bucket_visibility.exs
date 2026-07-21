defmodule Aveline.Repo.Migrations.BucketVisibility do
  use Ecto.Migration

  # Buckets gain the docs' visibility enum: private (owner + members)
  # | workspace (everyone, current and future members). Team buckets
  # are workspace by definition and personal ones private by
  # definition, enforced at the row level; only project buckets choose.
  def change do
    alter table(:view_buckets) do
      add :visibility, :text, null: false, default: "private"
    end

    execute "UPDATE view_buckets SET visibility = 'workspace' WHERE kind = 'team'", ""

    create constraint(:view_buckets, :view_buckets_visibility_check,
             check: "visibility IN ('private', 'workspace')"
           )

    create constraint(:view_buckets, :view_buckets_kind_visibility_check,
             check: """
             (kind = 'team' AND visibility = 'workspace')
             OR (kind = 'personal' AND visibility = 'private')
             OR kind = 'project'
             """
           )
  end
end
