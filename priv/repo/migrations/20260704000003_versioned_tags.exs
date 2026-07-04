defmodule Aveline.Repo.Migrations.VersionedTags do
  @moduledoc """
  Tags join the house versioning model (see 20260704000002): versioned
  edits (rename/redescribe/recolor insert a new version sharing
  `base_tag_id`), soft delete + restore, optional `color`.

  Doc rows KEEP tag slugs in their tags array when a tag is deleted —
  the tag just turns invisible to live reads until restored, making
  delete/restore perfect inverses with zero cascade.
  """
  use Ecto.Migration

  def up do
    alter table(:tags) do
      add :base_tag_id, :binary_id
      add :version_number, :integer, null: false, default: 1
      add :color, :string
      add :superseded, :boolean, null: false, default: false
      add :deleted_at, :utc_datetime_usec
      add :deleted_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    execute "UPDATE tags SET base_tag_id = id"

    alter table(:tags) do
      modify :base_tag_id, :binary_id, null: false
    end

    drop unique_index(:tags, [:workspace_id, :slug])

    create unique_index(:tags, [:workspace_id, :slug],
             where: "NOT superseded AND deleted_at IS NULL",
             name: :tags_workspace_id_slug_index
           )

    create unique_index(:tags, [:base_tag_id, :version_number])

    create unique_index(:tags, [:base_tag_id],
             where: "NOT superseded",
             name: :tags_one_current_per_base_idx
           )

    create constraint(:tags, :tags_superseded_xor_deleted,
             check: "NOT (superseded AND deleted_at IS NOT NULL)"
           )
  end

  def down do
    drop constraint(:tags, :tags_superseded_xor_deleted)
    drop index(:tags, [:base_tag_id], name: :tags_one_current_per_base_idx)
    drop unique_index(:tags, [:base_tag_id, :version_number])
    drop index(:tags, [:workspace_id, :slug], name: :tags_workspace_id_slug_index)
    execute "DELETE FROM tags WHERE superseded OR deleted_at IS NOT NULL"
    create unique_index(:tags, [:workspace_id, :slug])

    alter table(:tags) do
      remove :base_tag_id
      remove :version_number
      remove :color
      remove :superseded
      remove :deleted_at
      remove :deleted_by_id
    end
  end
end
