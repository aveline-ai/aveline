defmodule Aveline.Repo.Migrations.HouseVersioningModel do
  @moduledoc """
  One versioning model for every versioned entity (docs, comments, and —
  in the next migration — tags):

    * `base_*_id` + `version_number` — identity and order. Nothing
      points at other versions; adjacency is arithmetic.
    * `superseded` (boolean) — mechanism: a newer version replaced this
      row. Carries no actor and no time (the successor row holds both);
      a boolean has no value that a sibling row could contradict.
    * `deleted_at` + `deleted_by_id` — intent: a human deleted the
      THING. Only ever set on a current row; cleared by restore.
    * live = `NOT superseded AND deleted_at IS NULL`, enforced by the
      partial unique indexes; `CHECK` makes superseded-and-deleted
      unrepresentable.

  Previously docs overloaded `deleted_at` (supersede stamped it, and
  even stamped `deleted_by_id` with the editing actor), so a row's state
  wasn't readable without version arithmetic. Comments had already
  split mechanism from intent (20260617000002) but used a timestamp
  whose value duplicated the successor's `inserted_at`; only its
  NULL-ness was ever read.
  """
  use Ecto.Migration

  def up do
    # ===== Docs =====
    alter table(:docs) do
      add :superseded, :boolean, null: false, default: false
    end

    flush()

    # Old live-scoped indexes must go BEFORE the backfill: clearing
    # deleted_at on superseded history would collide with
    # `UNIQUE (base) WHERE deleted_at IS NULL` while it still stands.
    drop index(:docs, [:base_doc_id], name: :docs_one_current_per_base_idx)
    drop index(:docs, [:workspace_id, :slug], name: :docs_workspace_id_slug_active_index)
    drop index(:docs, [:workspace_id, :pin_slot], name: :docs_workspace_pin_slot_index)

    # Overloaded deleted_at → the split model: any "deleted" row with a
    # newer version was actually superseded.
    execute """
    UPDATE docs d
    SET superseded = TRUE,
        deleted_at = NULL,
        deleted_by_id = NULL
    WHERE d.deleted_at IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM docs d2
        WHERE d2.base_doc_id = d.base_doc_id
          AND d2.version_number > d.version_number
      )
    """

    # One CURRENT row per base — current may be live or deleted, but
    # never plural. Inserting a successor without superseding fails here.
    create unique_index(:docs, [:base_doc_id],
             where: "NOT superseded",
             name: :docs_one_current_per_base_idx
           )

    create unique_index(:docs, [:workspace_id, :slug],
             where: "NOT superseded AND deleted_at IS NULL",
             name: :docs_workspace_id_slug_active_index
           )

    create constraint(:docs, :docs_superseded_xor_deleted,
             check: "NOT (superseded AND deleted_at IS NOT NULL)"
           )

    # Pin slots ride on current rows; superseded history must not hold
    # them hostage. (Deleting a doc clears its slot in code.)
    create unique_index(:docs, [:workspace_id, :pin_slot],
             where: "NOT superseded AND pin_slot IS NOT NULL",
             name: :docs_workspace_pin_slot_index
           )

    # ===== Comments =====
    alter table(:doc_comments) do
      add :superseded, :boolean, null: false, default: false
    end

    flush()

    execute "UPDATE doc_comments SET superseded = TRUE WHERE superseded_at IS NOT NULL"

    alter table(:doc_comments) do
      remove :superseded_at
    end

    create unique_index(:doc_comments, [:base_comment_id],
             where: "NOT superseded",
             name: :doc_comments_one_current_per_base_idx
           )

    create constraint(:doc_comments, :doc_comments_superseded_xor_deleted,
             check: "NOT (superseded AND deleted_at IS NOT NULL)"
           )
  end

  # Prod is pre-launch; down just needs to not strand dev databases.
  def down do
    drop constraint(:doc_comments, :doc_comments_superseded_xor_deleted)
    drop index(:doc_comments, [:base_comment_id], name: :doc_comments_one_current_per_base_idx)

    alter table(:doc_comments) do
      add :superseded_at, :utc_datetime_usec
    end

    flush()
    execute "UPDATE doc_comments SET superseded_at = updated_at WHERE superseded"

    alter table(:doc_comments) do
      remove :superseded
    end

    drop constraint(:docs, :docs_superseded_xor_deleted)
    drop index(:docs, [:base_doc_id], name: :docs_one_current_per_base_idx)
    drop index(:docs, [:workspace_id, :slug], name: :docs_workspace_id_slug_active_index)

    execute "UPDATE docs SET deleted_at = updated_at WHERE superseded"

    create unique_index(:docs, [:base_doc_id],
             where: "deleted_at IS NULL",
             name: :docs_one_current_per_base_idx
           )

    create unique_index(:docs, [:workspace_id, :slug],
             where: "deleted_at IS NULL",
             name: :docs_workspace_id_slug_active_index
           )

    alter table(:docs) do
      remove :superseded
    end
  end
end
