defmodule Aveline.Repo.Migrations.CreateItems do
  use Ecto.Migration

  def change do
    create table(:items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workspace_id,
          references(:workspaces, type: :binary_id, on_delete: :delete_all),
          null: false

      add :slug, :string, null: false
      add :title, :string, null: false
      add :body, :text, null: false, default: ""
      add :summary, :text
      add :tags, {:array, :string}, null: false, default: []
      add :pinned, :boolean, null: false, default: false
      add :owner_id, references(:users, type: :binary_id, on_delete: :restrict), null: false

      add :created_by_id,
          references(:users, type: :binary_id, on_delete: :restrict),
          null: false

      add :created_via, :string, null: false
      add :deleted_at, :timestamptz
      add :deleted_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :timestamptz)
    end

    create index(:items, [:workspace_id], where: "deleted_at IS NULL")

    create unique_index(:items, [:workspace_id, :slug],
             where: "deleted_at IS NULL",
             name: :items_workspace_id_slug_active_index
           )

    execute "CREATE INDEX items_tags_gin_index ON items USING GIN (tags)",
            "DROP INDEX items_tags_gin_index"
  end
end
