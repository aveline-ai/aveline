defmodule Aveline.Repo.Migrations.AddResolvedByDocToComments do
  use Ecto.Migration

  def change do
    alter table(:doc_comments) do
      # When a doc version resolves a comment as part of its dispositions,
      # this points at THAT version. Null means a human resolved it manually
      # (or the comment isn't resolved).
      add :resolved_by_doc_id, references(:docs, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:doc_comments, [:resolved_by_doc_id])
  end
end
