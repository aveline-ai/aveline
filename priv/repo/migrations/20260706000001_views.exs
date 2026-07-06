defmodule Aveline.Repo.Migrations.Views do
  @moduledoc """
  Views: config-tier entities (like tags and data sources), NOT docs.
  A view is a named, described, versioned snapshot of the Docs page's
  display knobs: filter tags, group_by scope (nil = list, scope =
  kanban), sort. No comments, no blocks, no body — the comment test:
  nobody comments on a saved filter, so a view is not content.

  `pinned` lives outside the versioned config (like doc pin slots):
  pinning is placement, not an edit to what the view means.
  """
  use Ecto.Migration

  def change do
    create table(:views, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :base_view_id, :binary_id, null: false
      add :version_number, :integer, null: false, default: 1
      add :superseded, :boolean, null: false, default: false
      add :deleted_at, :utc_datetime_usec
      add :deleted_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :description, :string, null: false
      add :config, :map, null: false, default: %{}
      add :pinned, :boolean, null: false, default: false
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:views, [:workspace_id, :name],
             where: "NOT superseded AND deleted_at IS NULL",
             name: :views_workspace_id_name_index
           )

    create unique_index(:views, [:base_view_id, :version_number])

    create unique_index(:views, [:base_view_id],
             where: "NOT superseded",
             name: :views_one_current_per_base_idx
           )

    create constraint(:views, :views_superseded_xor_deleted,
             check: "NOT (superseded AND deleted_at IS NOT NULL)"
           )
  end
end
