defmodule :"Elixir.Aveline.Repo.Migrations.Update-to-usec-by-default-for-all-table-timestamps" do
  use Ecto.Migration

  def change do
    alter table(:chat_room_memberships) do
      modify :inserted_at, :utc_datetime_usec, from: :utc_datetime, to: :utc_datetime_usec
      modify :updated_at, :utc_datetime_usec, from: :utc_datetime, to: :utc_datetime_usec
    end

    alter table(:chat_rooms) do
      modify :inserted_at, :utc_datetime_usec, from: :utc_datetime, to: :utc_datetime_usec
      modify :updated_at, :utc_datetime_usec, from: :utc_datetime, to: :utc_datetime_usec
    end

    alter table(:login_tokens) do
      modify :inserted_at, :utc_datetime_usec, from: :utc_datetime, to: :utc_datetime_usec
      modify :updated_at, :utc_datetime_usec, from: :utc_datetime, to: :utc_datetime_usec
    end

    alter table(:messages) do
      modify :inserted_at, :utc_datetime_usec, from: :utc_datetime, to: :utc_datetime_usec
      modify :updated_at, :utc_datetime_usec, from: :utc_datetime, to: :utc_datetime_usec
    end

    alter table(:users) do
      modify :inserted_at, :utc_datetime_usec, from: :utc_datetime, to: :utc_datetime_usec
      modify :updated_at, :utc_datetime_usec, from: :utc_datetime, to: :utc_datetime_usec
    end
  end
end
