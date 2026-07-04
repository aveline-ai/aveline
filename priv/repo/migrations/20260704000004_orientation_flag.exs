defmodule Aveline.Repo.Migrations.OrientationFlag do
  @moduledoc """
  The orientation doc is marked by a boolean on the doc, not by a
  well-known slug: the fact lives in the schema where constraints can
  see it. One per workspace among current rows (partial unique), and
  deletion is UNREPRESENTABLE (CHECK), not merely refused. Seeded at
  workspace creation; editable like any doc.

  Pre-launch — no backfill. Existing rows default to false.
  """
  use Ecto.Migration

  def up do
    alter table(:docs) do
      add :orientation, :boolean, null: false, default: false
    end

    create unique_index(:docs, [:workspace_id],
             where: "orientation AND NOT superseded",
             name: :docs_one_orientation_per_workspace_idx
           )

    create constraint(:docs, :docs_orientation_undeletable,
             check: "NOT (orientation AND deleted_at IS NOT NULL)"
           )
  end

  def down do
    drop constraint(:docs, :docs_orientation_undeletable)
    drop index(:docs, [:workspace_id], name: :docs_one_orientation_per_workspace_idx)

    alter table(:docs) do
      remove :orientation
    end
  end
end
