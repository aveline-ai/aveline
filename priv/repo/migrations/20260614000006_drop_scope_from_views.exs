defmodule Aveline.Repo.Migrations.DropScopeFromViews do
  use Ecto.Migration

  def change do
    alter table(:views) do
      remove :scope, :string
    end
  end
end
