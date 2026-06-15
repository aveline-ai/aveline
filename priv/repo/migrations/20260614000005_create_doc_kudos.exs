defmodule Aveline.Repo.Migrations.CreateDocKudos do
  use Ecto.Migration

  def change do
    create table(:doc_kudos, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all), null: false
      add :base_doc_id, :binary_id, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :given_at, :utc_datetime_usec, null: false
    end

    # One kudos per (user, base_doc) — toggling is delete-and-reinsert.
    create unique_index(:doc_kudos, [:base_doc_id, :user_id])
    create index(:doc_kudos, [:workspace_id])
  end
end
