defmodule Aveline.Docs.Share do
  @moduledoc """
  A per-user grant on a private doc. `viewer` reads and comments;
  `editor` also edits. Keyed by base_doc_id (the stable logical doc),
  soft-deleted like everything else, one live row per (doc, user).
  """
  use Aveline.Schema
  import Ecto.Changeset

  alias Aveline.Accounts.User
  alias Aveline.Workspaces.Workspace

  @roles ~w(viewer editor)

  @derive {Jason.Encoder,
           only: [:id, :base_doc_id, :role, :inserted_at, :updated_at, :deleted_at]}
  schema "doc_shares" do
    field :base_doc_id, :binary_id
    field :role, :string
    field :deleted_at, :utc_datetime_usec

    belongs_to :workspace, Workspace, type: :binary_id
    belongs_to :user, User, type: :binary_id
    belongs_to :granted_by, User, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def roles, do: @roles

  def changeset(share, attrs) do
    share
    |> cast(attrs, [:base_doc_id, :workspace_id, :user_id, :role, :granted_by_id])
    |> validate_required([:base_doc_id, :workspace_id, :user_id, :role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:base_doc_id, :user_id], name: :doc_shares_live_unique)
  end
end
