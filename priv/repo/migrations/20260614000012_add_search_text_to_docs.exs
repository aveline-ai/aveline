defmodule Aveline.Repo.Migrations.AddSearchTextToDocs do
  use Ecto.Migration

  def up do
    alter table(:docs) do
      # Pre-flattened, searchable text: title + summary + tags + every
      # block's text content. Maintained at insert time in Docs.apply_ops.
      # English tsvector lives in the GIN index below, not on the row —
      # keeps writes cheap and the column itself debuggable.
      add :search_text, :text, default: "", null: false
    end

    execute """
    CREATE INDEX docs_search_idx
      ON docs USING GIN (to_tsvector('english', search_text))
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS docs_search_idx"

    alter table(:docs) do
      remove :search_text
    end
  end
end
