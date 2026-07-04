defmodule Aveline.Repo.Migrations.PinSlots do
  use Ecto.Migration

  @moduledoc """
  Replace the doc-level `pinned` boolean with `pin_slot` (1..6): pinning
  now means exactly one thing — this doc holds a numbered slot on the
  workspace home page. Existing pinned docs are backfilled into slots by
  recency (max 6 per workspace; the orientation doc has its own card and
  never takes a slot).
  """

  def up do
    alter table(:docs) do
      add :pin_slot, :smallint
    end

    execute """
    UPDATE docs d
    SET pin_slot = r.rn
    FROM (
      SELECT id, ROW_NUMBER() OVER (
        PARTITION BY workspace_id ORDER BY updated_at DESC
      ) AS rn
      FROM docs
      WHERE deleted_at IS NULL AND pinned AND slug <> 'agents'
    ) r
    WHERE d.id = r.id AND r.rn <= 6
    """

    # One doc per slot per workspace, enforced over live rows only —
    # superseded/deleted versions carry historical values freely.
    create unique_index(:docs, [:workspace_id, :pin_slot],
             where: "deleted_at IS NULL AND pin_slot IS NOT NULL",
             name: :docs_workspace_pin_slot_index
           )

    alter table(:docs) do
      remove :pinned
    end
  end

  def down do
    alter table(:docs) do
      add :pinned, :boolean, default: false, null: false
    end

    execute "UPDATE docs SET pinned = TRUE WHERE pin_slot IS NOT NULL"

    drop index(:docs, [:workspace_id, :pin_slot], name: :docs_workspace_pin_slot_index)

    alter table(:docs) do
      remove :pin_slot
    end
  end
end
