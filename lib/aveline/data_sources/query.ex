defmodule Aveline.DataSources.Query do
  @moduledoc """
  A catalog query: a named, versioned definition of a result set. Raw
  queries ({name, source, sql}) run against an external data source in
  its dialect; derived queries ({name, sql}) run in the analytics
  dialect over other catalog queries by name. Names are table
  identifiers inside agent-written SQL, so the charset is strict and
  every identifier we emit is quoted anyway.

  Holds no data, ever — a query is config; results are computed per
  run and discarded. House versioning: edits mint new versions on the
  base id; references (chart SQL, derived SQL) bind to the NAME and
  resolve latest at run time.
  """
  use Aveline.Schema
  import Ecto.Changeset

  alias Aveline.Accounts.User
  alias Aveline.Workspaces.Workspace

  @name_format ~r/^[a-z][a-z0-9_]{0,39}$/
  @kinds ~w(raw derived)

  schema "queries" do
    field :base_query_id, :binary_id
    field :version_number, :integer, default: 1
    field :name, :string
    field :kind, :string
    # Base id of the raw query's data source; nil for derived.
    field :data_source_id, :binary_id
    field :sql, :string
    field :superseded, :boolean, default: false
    field :deleted_at, :utc_datetime_usec

    belongs_to :workspace, Workspace, type: :binary_id
    belongs_to :created_by, User, type: :binary_id
    belongs_to :deleted_by, User, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def name_format, do: @name_format

  def insert_changeset(query, attrs) do
    query
    |> cast(attrs, [
      :workspace_id,
      :base_query_id,
      :version_number,
      :name,
      :kind,
      :data_source_id,
      :sql,
      :created_by_id
    ])
    |> validate_required([:workspace_id, :base_query_id, :name, :kind, :sql])
    |> update_change(:name, fn n ->
      if is_binary(n), do: n |> String.trim() |> String.downcase(), else: n
    end)
    |> validate_format(:name, @name_format,
      message:
        "must be a table-safe identifier: lowercase letter first, then lowercase letters, digits, underscores (40 chars max)"
    )
    |> validate_inclusion(:kind, @kinds)
    |> validate_length(:sql, min: 1, max: 10_000)
    |> unique_constraint([:workspace_id, :name],
      name: :queries_workspace_id_name_index,
      message: "already exists"
    )
  end
end
