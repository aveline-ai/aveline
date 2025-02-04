defmodule Aveline.Repo.Migrations.AddChatRoomsAndMembershipsAndMessages do
  use Ecto.Migration

  def change do
    create table(:chat_rooms) do
      add :name, :string, null: false
      add :ai_settings, :map, null: false
      add :parent_chat_room_id, references(:chat_rooms, on_delete: :nilify_all)

      timestamps()
    end

    create table(:chat_room_memberships) do
      add :chat_room_id, references(:chat_rooms, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:chat_room_memberships, [:chat_room_id, :user_id])
    create index(:chat_room_memberships, [:user_id])
    create index(:chat_room_memberships, [:chat_room_id])

    create table(:messages) do
      add :content, :text, null: false
      add :author_kind, :string, null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :chat_room_id, references(:chat_rooms, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:messages, [:user_id])
    create index(:messages, [:chat_room_id])
  end
end
