defmodule Aveline.Repo.Migrations.CreateSidebarFavorites do
  use Ecto.Migration

  def change do
    create table(:sidebar_favorites, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all), null: false
      # "tag" or "view". `key` is the tag string for tag favorites or the
      # view slug for view favorites.
      add :kind, :string, null: false
      add :key, :string, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:sidebar_favorites, [:user_id, :workspace_id, :kind, :key])
    create index(:sidebar_favorites, [:user_id, :workspace_id])
  end
end
