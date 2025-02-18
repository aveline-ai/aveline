defmodule :"Elixir.Aveline.Repo.Migrations.Add-language-and-chatroom-mode-to-chatrooms" do
  use Ecto.Migration

  def change do
    alter table(:chat_rooms) do
      add :learning_language, :string, null: false
      add :base_language, :string, null: false
      add :chat_room_mode, :string, null: false
      remove :ai_settings, :map, null: false
    end
  end
end
