defmodule Aveline.Repo.Migrations.DataSources do
  @moduledoc """
  External databases a workspace can chart from. House versioning model
  from day one (base id + version_number + superseded + deleted_at).

  The connection URL is encrypted at rest (AES-256-GCM via Cloak, key
  in a runtime secret) — what sits in this column is ciphertext. It is
  write-only through the API: reads echo name/adapter/host/database.
  """
  use Ecto.Migration

  def change do
    create table(:data_sources, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :base_data_source_id, :binary_id, null: false
      add :version_number, :integer, null: false, default: 1
      add :superseded, :boolean, null: false, default: false
      add :deleted_at, :utc_datetime_usec
      add :deleted_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :adapter, :string, null: false
      add :url_encrypted, :binary, null: false
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:data_sources, [:workspace_id, :name],
             where: "NOT superseded AND deleted_at IS NULL",
             name: :data_sources_workspace_id_name_index
           )

    create unique_index(:data_sources, [:base_data_source_id, :version_number])

    create unique_index(:data_sources, [:base_data_source_id],
             where: "NOT superseded",
             name: :data_sources_one_current_per_base_idx
           )

    create constraint(:data_sources, :data_sources_superseded_xor_deleted,
             check: "NOT (superseded AND deleted_at IS NOT NULL)"
           )

    create constraint(:data_sources, :data_sources_adapter_known,
             check: "adapter IN ('postgres', 'mysql')"
           )
  end
end
