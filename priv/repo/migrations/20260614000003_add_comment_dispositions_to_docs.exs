defmodule Aveline.Repo.Migrations.AddCommentDispositionsToDocs do
  use Ecto.Migration

  def change do
    alter table(:docs) do
      # JSONB array of %{comment_id, action, new_block_id?, note?}.
      # `action` ∈ "resolve" | "reanchor" | "leave". Required on every
      # agent-authored version that has open threads; optional for humans.
      # See Aveline.Comments.Disposition.
      add :comment_dispositions, {:array, :map}, default: [], null: false
    end
  end
end
