defmodule Aveline.Repo.Migrations.Milestones do
  use Ecto.Migration

  # Timeline milestones: dated workspace facts (a release, a pricing
  # change) that overlay every time-series chart in range as vertical
  # markers. Metabase's Timeline Events, minus the grouping layer.
  # Soft-delete only, no version chain: a milestone is a dated fact and
  # its edits are typo fixes, not history worth keeping.
  def change do
    create table(:milestones, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :date, :date, null: false
      add :description, :text
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :deleted_at, :utc_datetime_usec
      add :deleted_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:milestones, [:workspace_id, :date])
  end
end
