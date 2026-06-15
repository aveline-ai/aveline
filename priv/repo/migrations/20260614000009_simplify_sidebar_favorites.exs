defmodule Aveline.Repo.Migrations.SimplifySidebarFavorites do
  use Ecto.Migration

  def change do
    # Drop old composite uniqueness + the kind column. Sidebar favorites
    # are tag-only now — `key` is the tag string.
    drop unique_index(:sidebar_favorites, [:user_id, :workspace_id, :kind, :key])

    alter table(:sidebar_favorites) do
      remove :kind, :string
    end

    rename table(:sidebar_favorites), :key, to: :tag

    create unique_index(:sidebar_favorites, [:user_id, :workspace_id, :tag])
  end
end
