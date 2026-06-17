defmodule Aveline.Repo.Migrations.VersionDocComments do
  @moduledoc """
  Mirror the docs "version-as-row" model onto comments. Every comment now
  carries a stable `base_comment_id` (the logical thread id) plus a
  `version_number`. Editing a comment inserts a new row with the same
  `base_comment_id`, version+1, marking the prior row's `deleted_at`
  (same convention docs use for "superseded"). The CURRENT row of a
  comment = the one with `deleted_at IS NULL` for a given base_comment_id.

  Drops the FK constraint on `parent_comment_id` because that column now
  references the parent's `base_comment_id` (logical id), which is not
  unique per row.
  """
  use Ecto.Migration

  def change do
    alter table(:doc_comments) do
      add :base_comment_id, :binary_id
      add :version_number, :integer, default: 1, null: false
    end

    # Backfill: every existing comment is its own base + version 1.
    execute(
      "UPDATE doc_comments SET base_comment_id = id WHERE base_comment_id IS NULL",
      "UPDATE doc_comments SET base_comment_id = NULL"
    )

    alter table(:doc_comments) do
      modify :base_comment_id, :binary_id, null: false
    end

    # parent_comment_id now points at the parent's `base_comment_id` —
    # a UUID that's not unique per row, so the FK constraint has to go.
    execute(
      "ALTER TABLE doc_comments DROP CONSTRAINT IF EXISTS doc_comments_parent_comment_id_fkey",
      ""
    )

    create index(:doc_comments, [:base_comment_id])
    create index(:doc_comments, [:base_comment_id, :version_number])

    # Hot path: "give me the current row for each base_comment_id."
    create index(:doc_comments, [:base_comment_id],
             where: "deleted_at IS NULL",
             name: :doc_comments_current_by_base_idx
           )
  end
end
