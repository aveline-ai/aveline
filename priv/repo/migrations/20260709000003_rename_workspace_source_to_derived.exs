defmodule Aveline.Repo.Migrations.RenameWorkspaceSourceToDerived do
  @moduledoc """
  The built-in catalog source is renamed \"workspace\" → \"derived\" so
  the name matches how it reads everywhere else (charts on it are
  \"derived · duckdb · …\"). Its adapter stays \"workspace\" (the internal
  discriminator); only the user-facing name changes.

  Pure SQL, no app context — safe in a cold migrate.
  """
  use Ecto.Migration

  def up do
    # Free the name if a user source already holds \"derived\", then rename
    # the built-in. The partial unique on (workspace_id, name) forbids two
    # live sources sharing a name.
    execute """
    UPDATE data_sources SET name = name || '-db'
    WHERE name = 'derived' AND adapter <> 'workspace'
      AND NOT superseded AND deleted_at IS NULL
    """

    execute "UPDATE data_sources SET name = 'derived' WHERE adapter = 'workspace'"
  end

  def down do
    execute "UPDATE data_sources SET name = 'workspace' WHERE adapter = 'workspace'"
  end
end
