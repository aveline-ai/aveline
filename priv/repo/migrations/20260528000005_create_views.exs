defmodule Aveline.Repo.Migrations.CreateViews do
  use Ecto.Migration

  def change do
    create table(:views, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workspace_id,
          references(:workspaces, type: :binary_id, on_delete: :delete_all),
          null: false

      add :slug, :string, null: false
      add :name, :string, null: false
      add :tag_filter, {:array, :string}, null: false, default: []
      add :description, :text
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :deleted_at, :timestamptz
      add :deleted_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :timestamptz)
    end

    create unique_index(:views, [:workspace_id, :slug],
             where: "deleted_at IS NULL",
             name: :views_workspace_id_slug_active_index
           )
  end
end
