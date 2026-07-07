defmodule Aveline.DataSources.DataSource do
  @moduledoc """
  An external database this workspace can chart from. Ordinary house
  versioning: edits mint new versions on the base id; chart blocks pin
  the base id and resolve the current version at read, so renames and
  credential rotations never break a doc.

  The connection value splits along the secrecy boundary:
  `url_template` (the full string with a literal `<password>`
  placeholder — no secret, plain, rendered verbatim everywhere) and
  `password` (encrypted at rest, write-only, scrubbed the moment a row
  stops being live — see the migration for the whole story).
  """
  use Aveline.Schema
  import Ecto.Changeset

  alias Aveline.Accounts.User
  alias Aveline.Slug
  alias Aveline.Workspaces.Workspace

  @adapters ~w(postgres mysql redshift)
  @placeholder "<password>"

  schema "data_sources" do
    field :base_data_source_id, :binary_id
    field :version_number, :integer, default: 1
    field :name, :string
    field :adapter, :string
    field :url_template, :string
    field :password, Aveline.Encrypted.Binary, source: :password_encrypted
    field :superseded, :boolean, default: false
    field :deleted_at, :utc_datetime_usec

    belongs_to :workspace, Workspace, type: :binary_id
    belongs_to :created_by, User, type: :binary_id
    belongs_to :deleted_by, User, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def adapters, do: @adapters
  def placeholder, do: @placeholder

  def insert_changeset(ds, attrs) do
    ds
    |> cast(attrs, [
      :workspace_id,
      :base_data_source_id,
      :version_number,
      :name,
      :adapter,
      :url_template,
      :password,
      :created_by_id
    ])
    |> validate_required([:workspace_id, :base_data_source_id, :name, :adapter, :url_template])
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
