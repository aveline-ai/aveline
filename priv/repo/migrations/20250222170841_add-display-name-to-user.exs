defmodule :"Elixir.Aveline.Repo.Migrations.Add-display-name-to-user" do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :display_name, :string, null: false
    end
  end
end
