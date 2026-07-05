defmodule Aveline.DataSources.DataSource do
  @moduledoc """
  An external database this workspace can chart from. The connection
  URL is encrypted at rest (see `Aveline.Vault`) and write-only through
  the API: reads echo name/adapter/host/database, never the credential.

  House versioning model: base id + version_number + superseded
  (mechanism) + deleted_at/by (intent). Live = NOT superseded AND
  deleted_at IS NULL.
  """
  use Aveline.Schema
  import Ecto.Changeset

  alias Aveline.Accounts.User
  alias Aveline.Slug
  alias Aveline.Workspaces.Workspace

  @adapters ~w(postgres mysql)

  schema "data_sources" do
    field :base_data_source_id, :binary_id
    field :version_number, :integer, default: 1
    field :name, :string
    field :adapter, :string
    field :url, Aveline.Encrypted.Binary, source: :url_encrypted
    field :superseded, :boolean, default: false
    field :deleted_at, :utc_datetime_usec

    belongs_to :workspace, Workspace, type: :binary_id
    belongs_to :created_by, User, type: :binary_id
    belongs_to :deleted_by, User, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def adapters, do: @adapters

  def create_changeset(ds, attrs) do
    ds
    |> cast(attrs, [
      :workspace_id,
      :base_data_source_id,
      :version_number,
      :name,
      :adapter,
      :url,
      :created_by_id
    ])
    |> validate_required([:workspace_id, :base_data_source_id, :name, :adapter, :url])
    |> update_change(:name, fn n -> if is_binary(n), do: n |> String.trim() |> String.downcase(), else: n end)
    |> validate_name()
    |> validate_inclusion(:adapter, @adapters,
      message: "unsupported adapter; expected one of #{Enum.join(@adapters, ", ")}"
    )
    |> unique_constraint([:workspace_id, :name],
      name: :data_sources_workspace_id_name_index,
      message: "already exists"
    )
  end

  defp validate_name(changeset) do
    case get_field(changeset, :name) do
      nil ->
        changeset

      name ->
        if Slug.validate(name) == :ok,
          do: changeset,
          else: add_error(changeset, :name, "must be a slug (lowercase letters, digits, dashes)")
    end
  end
end
