defmodule Aveline.Repo.Migrations.CreateDocViews do
  use Ecto.Migration

  def change do
    create table(:doc_views, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all), null: false
      # base_doc_id is the logical doc id (stable across versions). We
      # intentionally don't reference a specific Doc version row, since
      # versions can be soft-deleted as part of supersede.
      add :base_doc_id, :binary_id, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :actor_type, :string, null: false
      add :viewed_at, :utc_datetime_usec, null: false
    end

    create index(:doc_views, [:base_doc_id, :viewed_at])
    create index(:doc_views, [:workspace_id, :viewed_at])
    create index(:doc_views, [:user_id, :viewed_at])
  end
end
