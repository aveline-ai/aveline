defmodule Aveline.Repo.Migrations.QueryCatalog do
  @moduledoc """
  The workspace query catalog: named, versioned queries built on data
  sources. Two kinds — `raw` ({name, source, sql} in the source's
  dialect) and `derived` ({name, sql} in the analytics dialect, built
  from other catalog queries by name). House versioning model, same as
  data_sources.

  Also seeds the built-in "workspace" data source per workspace: a
  virtual source whose tables ARE the catalog. It's a real data_sources
  row (adapter 'workspace', no credential, sentinel template) so chart
  blocks, name resolution, and get_latest_by_base reuse as-is. Three
  invariants bend for it:

    * live_iff_credentialed exempts adapter 'workspace' (it has no
      credential to hold)
    * adapter_known gains 'workspace'
    * the name "workspace" becomes reserved — any user source already
      wearing it gets suffixed '-db' first
  """
  use Ecto.Migration

  def up do
    # ── queries table ────────────────────────────────────────────────
    create table(:queries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :base_query_id, :binary_id, null: false
      add :version_number, :integer, null: false, default: 1
      add :superseded, :boolean, null: false, default: false
      add :deleted_at, :utc_datetime_usec
      add :deleted_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :kind, :string, null: false
      # Base id of the raw query's data source (not a FK: sources are
      # versioned rows, blocks and queries pin the stable base id).
      add :data_source_id, :binary_id
      add :sql, :text, null: false
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:queries, [:workspace_id, :name],
             where: "NOT superseded AND deleted_at IS NULL",
             name: :queries_workspace_id_name_index
           )

    create unique_index(:queries, [:base_query_id, :version_number])

    create unique_index(:queries, [:base_query_id],
             where: "NOT superseded",
             name: :queries_one_current_per_base_idx
           )

    create constraint(:queries, :queries_superseded_xor_deleted,
             check: "NOT (superseded AND deleted_at IS NOT NULL)"
           )

    create constraint(:queries, :queries_kind_known, check: "kind IN ('raw', 'derived')")

    # Exactly raw queries point at a source.
    create constraint(:queries, :queries_raw_iff_sourced,
             check: "(kind = 'raw') = (data_source_id IS NOT NULL)"
           )

    # ── the built-in workspace source ────────────────────────────────
    drop constraint(:data_sources, :data_sources_adapter_known)

    create constraint(:data_sources, :data_sources_adapter_known,
             check: "adapter IN ('postgres', 'mysql', 'redshift', 'workspace')"
           )

    drop constraint(:data_sources, :data_sources_live_iff_credentialed)

    create constraint(:data_sources, :data_sources_live_iff_credentialed,
             check: """
             CASE WHEN adapter = 'workspace' THEN password_encrypted IS NULL
                  ELSE ((NOT superseded) AND deleted_at IS NULL) = (password_encrypted IS NOT NULL)
             END
             """
           )

    # Free the reserved name, then seed one workspace source per
    # existing workspace (new workspaces seed at creation).
    execute """
    UPDATE data_sources SET name = name || '-db'
    WHERE name = 'workspace' AND adapter <> 'workspace'
      AND NOT superseded AND deleted_at IS NULL
    """

    execute """
    INSERT INTO data_sources
      (id, base_data_source_id, version_number, superseded, workspace_id,
       name, adapter, url_template, inserted_at, updated_at)
    SELECT gen_random_uuid(), gen_random_uuid(), 1, false, w.id,
           'workspace', 'workspace', 'workspace://catalog', now(), now()
    FROM workspaces w
    """
  end

  def down do
    execute "DELETE FROM data_sources WHERE adapter = 'workspace'"

    drop constraint(:data_sources, :data_sources_live_iff_credentialed)

    create constraint(:data_sources, :data_sources_live_iff_credentialed,
             check: "((NOT superseded) AND deleted_at IS NULL) = (password_encrypted IS NOT NULL)"
           )

    drop constraint(:data_sources, :data_sources_adapter_known)

    create constraint(:data_sources, :data_sources_adapter_known,
             check: "adapter IN ('postgres', 'mysql', 'redshift')"
           )

    drop table(:queries)
  end
end
