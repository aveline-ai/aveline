defmodule :"Elixir.Aveline.Repo.Migrations.Add-timestamp-index-to-chatroom-messages" do
  use Ecto.Migration

  def change do
    create index(:messages, [:chat_room_id, :inserted_at])
  end
end
