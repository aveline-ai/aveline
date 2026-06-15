defmodule Aveline.Repo.Migrations.DropSidebarFavorites do
  use Ecto.Migration

  def change do
    drop table(:sidebar_favorites)
  end
end
