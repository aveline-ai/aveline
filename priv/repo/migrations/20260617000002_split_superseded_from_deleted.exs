defmodule Aveline.Repo.Migrations.SplitSupersededFromDeleted do
  @moduledoc """
  Split `deleted_at` into two: `superseded_at` (mechanism — a newer
  comment-version was created) and `deleted_at` (intent — author or
  agent intentionally deleted the thread).

  Until now both meanings shared the same column, copying what docs do.
  Comments need to distinguish because time-travel rendering needs to
  separate "this row is no longer the current one" from "this thread
  was user-deleted." Docs don't need this — they're loaded by id, not
  by version arithmetic against their children.

  Backfill: for every row whose `deleted_at` is set AND a newer version
  exists for the same `base_comment_id`, move the timestamp into
  `superseded_at` and clear `deleted_at`. All other `deleted_at` rows
  stay — they're real user deletions (or, for rows predating versioning,
  they're rows whose semantics we leave alone).
  """
  use Ecto.Migration

  def up do
    alter table(:doc_comments) do
      add :superseded_at, :timestamptz
    end

    flush()

    # Rows where deleted_at was actually a supersede (a newer version
    # exists for this base) get migrated to superseded_at.
    execute("""
    UPDATE doc_comments c
    SET superseded_at = c.deleted_at,
        deleted_at = NULL,
        deleted_by_id = NULL
    WHERE c.deleted_at IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM doc_comments c2
        WHERE c2.base_comment_id = c.base_comment_id
          AND c2.version_number > c.version_number
      );
    """)

    create index(:doc_comments, [:superseded_at])
  end

  def down do
    alter table(:doc_comments) do
      remove :superseded_at
    end
  end
end
