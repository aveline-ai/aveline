defmodule Aveline.Repo.Migrations.CreateDocComments do
  use Ecto.Migration

  def change do
    create table(:doc_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :doc_id, references(:docs, type: :binary_id, on_delete: :delete_all), null: false
      add :block_id, :string

      add :body, :text, null: false
      add :actor_user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :actor_type, :string, null: false

      add :resolved_at, :timestamptz
      add :resolved_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :edited_at, :timestamptz
      add :deleted_at, :timestamptz
      add :deleted_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :timestamptz)
    end

    create index(:doc_comments, [:doc_id, :resolved_at],
             where: "deleted_at IS NULL",
             name: :doc_comments_doc_resolved_active_idx
           )

    create constraint(:doc_comments, :comment_actor_type_valid,
             check: "actor_type IN ('human', 'agent')"
           )
  end
end
