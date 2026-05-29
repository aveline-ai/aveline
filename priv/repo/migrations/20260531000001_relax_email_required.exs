defmodule Aveline.Repo.Migrations.RelaxEmailRequired do
  use Ecto.Migration

  def change do
    alter table(:users) do
      modify :email, :text, null: true, from: {:text, null: false}
      add :avatar_url, :text
    end
  end
end
