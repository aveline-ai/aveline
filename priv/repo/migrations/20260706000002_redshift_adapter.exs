defmodule Aveline.Repo.Migrations.RedshiftAdapter do
  @moduledoc """
  Third adapter: redshift — Postgres wire protocol, its own dialect.
  Stored distinctly (not mapped to postgres) so audit surfaces say the
  true engine and dialect-aware features (SQL formatting) key off it.
  """
  use Ecto.Migration

  def up do
    drop constraint(:data_sources, :data_sources_adapter_known)

    create constraint(:data_sources, :data_sources_adapter_known,
             check: "adapter IN ('postgres', 'mysql', 'redshift')"
           )
  end

  def down do
    drop constraint(:data_sources, :data_sources_adapter_known)

    create constraint(:data_sources, :data_sources_adapter_known,
             check: "adapter IN ('postgres', 'mysql')"
           )
  end
end
