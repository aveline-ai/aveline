defmodule Aveline.Repo.Migrations.WorkspaceTemplate do
  use Ecto.Migration

  # Every new workspace starts from one named template (tags, boards,
  # docs, orientation text) and remembers which, so an agent can say which
  # setup a team is on. Nullable: workspaces created before templates
  # existed have no answer, and that is the honest value.
  def change do
    alter table(:workspaces) do
      add :template, :string
    end
  end
end
