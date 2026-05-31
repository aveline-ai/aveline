defmodule Aveline.Repo.Migrations.CreateItemMessages do
  use Ecto.Migration

  def change do
    create table(:item_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :item_id, references(:items, type: :binary_id, on_delete: :delete_all), null: false
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

    create index(:item_messages, [:item_id, :resolved_at],
             where: "deleted_at IS NULL",
             name: :item_messages_item_resolved_active_idx
           )

    create constraint(:item_messages, :msg_actor_type_valid,
             check: "actor_type IN ('human', 'agent')"
           )
  end
end
