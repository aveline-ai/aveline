defmodule Aveline.Repo.Migrations.AddThreadingToDocComments do
  use Ecto.Migration

  def change do
    alter table(:doc_comments) do
      add :parent_comment_id, references(:doc_comments, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:doc_comments, [:parent_comment_id])
  end
end
