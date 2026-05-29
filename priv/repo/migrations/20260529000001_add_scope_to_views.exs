defmodule Aveline.Repo.Migrations.AddScopeToViews do
  use Ecto.Migration

  def up do
    alter table(:views) do
      add :scope, :text, null: false, default: "personal"
    end

    # Existing views were created before scope existed and were treated as
    # workspace-wide canonical — mark them all as team so behavior is
    # preserved.
    execute("UPDATE views SET scope = 'team'")

    create constraint(:views, :scope_valid, check: "scope IN ('personal', 'team')")
  end

  def down do
    drop constraint(:views, :scope_valid)

    alter table(:views) do
      remove :scope
    end
  end
end
