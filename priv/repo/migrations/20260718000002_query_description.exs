defmodule Aveline.Repo.Migrations.QueryDescription do
  use Ecto.Migration

  # One-line human description per catalog query (Metabase-style):
  # what this query answers, shown wherever the query is listed.
  def change do
    alter table(:queries) do
      add :description, :text
    end
  end
end
