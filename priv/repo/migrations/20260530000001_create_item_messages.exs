defmodule Aveline.Repo.Migrations.CreateItemMessages do
  use Ecto.Migration

  def change do
    create table(:item_messages, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :item_id, references(:items, type: :uuid, on_delete: :delete_all), null: false
      add :author_id, references(:users, type: :uuid), null: false
      add :body, :text, null: false
      add :created_via, :text, null: false
      add :edited_at, :timestamptz
      add :deleted_at, :timestamptz
      add :deleted_by_id, references(:users, type: :uuid)

      timestamps(type: :timestamptz)
    end

    create index(:item_messages, [:item_id, :inserted_at],
             where: "deleted_at IS NULL",
             name: :item_messages_item_id_inserted_at_active_idx
           )
  end
end
