defmodule Aveline.Views.ViewShare do
  @moduledoc """
  A per-user grant on a private view: the doc share model copied onto
  views. `viewer` can use the view; `editor` can also edit its config.
  Keyed by base_view_id, soft-deleted, one live row per (view, user).
  """
  use Aveline.Schema
  import Ecto.Changeset

  alias Aveline.Accounts.User
  alias Aveline.Workspaces.Workspace

  @roles ~w(viewer editor)

  @derive {Jason.Encoder, only: [:id, :base_view_id, :role, :inserted_at, :updated_at, :deleted_at]}
  schema "view_shares" do
    field :base_view_id, :binary_id
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
    |> cast(attrs, [:base_view_id, :workspace_id, :user_id, :role, :granted_by_id])
    |> validate_required([:base_view_id, :workspace_id, :user_id, :role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:base_view_id, :user_id], name: :view_shares_live_unique)
  end
end
