defmodule Aveline.Repo.Migrations.PinsUniversalForViews do
  use Ecto.Migration

  # Pin = in the sidebar, universally. The pinned-implies-workspace
  # constraint predated visibility-aware sidebars: now a pinned private
  # view only renders for people who can use it (owner under Yours,
  # shared users under Shared with you), so privacy no longer needs to
  # block pinning.
  def up do
    drop constraint(:views, :views_pinned_workspace_check)
  end

  def down do
    execute "UPDATE views SET pinned = false WHERE visibility = 'private' AND pinned"

    create constraint(:views, :views_pinned_workspace_check,
             check: "NOT pinned OR visibility = 'workspace'"
           )
  end
end
