defmodule Aveline.Repo.Migrations.CreateItems do
  use Ecto.Migration

  def change do
    create table(:items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :base_item_id, :binary_id, null: false
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

    # Only one CURRENT row per logical item.
    create unique_index(:items, [:base_item_id],
             where: "deleted_at IS NULL",
             name: :items_one_current_per_base_idx
           )

    # version_number unique within a base item.
    create unique_index(:items, [:base_item_id, :version_number])

    # Browse current items in a workspace.
    create index(:items, [:workspace_id], where: "deleted_at IS NULL")

    # Slug uniqueness — workspace-scoped, current-row only.
    create unique_index(:items, [:workspace_id, :slug],
             where: "deleted_at IS NULL",
             name: :items_workspace_id_slug_active_index
           )

    execute "CREATE INDEX items_tags_gin_index ON items USING GIN (tags)",
            "DROP INDEX items_tags_gin_index"

    create constraint(:items, :actor_type_valid,
             check: "actor_type IN ('human', 'agent')"
           )
  end
end
