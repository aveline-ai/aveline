defmodule Aveline.Repo.Migrations.CreateTags do
  use Ecto.Migration

  def change do
    create table(:tags, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all), null: false
      # The tag string as it appears on docs (e.g. "oncall"). Slug format.
      add :slug, :string, null: false
      # Required. Capped via changeset to keep the index/cards readable.
      add :description, :text, null: false
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tags, [:workspace_id, :slug])
  end
end
