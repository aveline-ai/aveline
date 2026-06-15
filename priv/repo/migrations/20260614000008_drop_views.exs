defmodule Aveline.Repo.Migrations.DropViews do
  use Ecto.Migration

  def change do
    drop table(:views)
  end
end
