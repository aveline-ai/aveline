defmodule Aveline.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all), null: false
      # Who did it. Nullable for system-originated events.
      add :actor_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      # "human" | "agent" — mirrors actor_type on docs/comments. Stored
      # per event so the timeline keeps reading correctly even if a user's
      # role changes later.
      add :actor_type, :string, null: false
      # Verb tag, snake_case. E.g. "doc_created", "comment_resolved",
      # "kudos_given". The history renderer matches on this.
      add :action, :string, null: false
      # The entity acted upon — denormalized so the timeline never has to
      # join to render. `target_slug` makes the link clickable even after
      # a target is renamed; `target_label` keeps the historical title.
      add :target_kind, :string
      add :target_id, :binary_id
      add :target_slug, :string
      add :target_label, :string
      # JSONB blob for action-specific context (tags, version_number,
      # comment excerpt, etc.). Keep it small; this is for display, not
      # for replay.
      add :data, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:events, [:workspace_id, :inserted_at])
    create index(:events, [:actor_user_id, :inserted_at])
    create index(:events, [:target_id])
  end
end
