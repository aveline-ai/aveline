defmodule Aveline.Repo.Migrations.CreateDocs do
  use Ecto.Migration

  def change do
    create table(:docs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :base_doc_id, :binary_id, null: false
      add :version_number, :integer, null: false

      add :workspace_id,
          references(:workspaces, type: :binary_id, on_delete: :restrict),
          null: false

      add :slug, :string, null: false
      add :title, :string, null: false
      add :summary, :string
      add :blocks, :jsonb, null: false, default: fragment("'[]'::jsonb")
      add :tags, {:array, :string}, null: false, default: []
      add :pinned, :boolean, null: false, default: false

      add :owner_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :actor_user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :actor_type, :string, null: false

      add :operations, :jsonb, null: false, default: fragment("'[]'::jsonb")
      add :intent, :text
      add :resolves_comment_ids, {:array, :binary_id}, null: false, default: []

      add :deleted_at, :timestamptz
      add :deleted_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :timestamptz)
    end

    create unique_index(:docs, [:base_doc_id],
             where: "deleted_at IS NULL",
             name: :docs_one_current_per_base_idx
           )

    create unique_index(:docs, [:base_doc_id, :version_number])
    create index(:docs, [:workspace_id], where: "deleted_at IS NULL")

    create unique_index(:docs, [:workspace_id, :slug],
             where: "deleted_at IS NULL",
             name: :docs_workspace_id_slug_active_index
           )

    execute "CREATE INDEX docs_tags_gin_index ON docs USING GIN (tags)",
            "DROP INDEX docs_tags_gin_index"

    create constraint(:docs, :actor_type_valid,
             check: "actor_type IN ('human', 'agent')"
           )
  end
end
