defmodule Aveline.Repo.Migrations.TagSortKey do
  @moduledoc """
  Optional tag ordering: every read orders tags by
  `COALESCE(sort_key, slug), slug`. NULL means alphabetical by slug;
  a sort_key overrides just that tag's position. Scope values use keys
  like "stage:1".."stage:4" so lifecycles read in order while the
  cluster still lands where the scope name sorts alphabetically.

  A string key means a reorder touches exactly one tag (insert between
  "stage:1" and "stage:2" with "stage:15"), so reordering is an ordinary
  versioned edit like rename or recolor. No renumbering machinery.
  """
  use Ecto.Migration

  def change do
    alter table(:tags) do
      add :sort_key, :string
    end
  end
end
