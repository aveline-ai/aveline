defmodule Aveline.Repo.Migrations.ApiTokenSuffix do
  use Ecto.Migration

  # Last 4 plaintext chars, persisted at mint for masked display (…a1b2).
  # Nullable: keys minted before this migration fall back to the stored
  # prefix for display.
  def change do
    alter table(:api_tokens) do
      add :token_suffix, :string
    end
  end
end
