defmodule Aveline.Workspaces.Invite do
  @moduledoc false
  use Aveline.Schema
  import Ecto.Changeset

  alias Aveline.Accounts.User
  alias Aveline.Workspaces.Workspace

  schema "workspace_invites" do
    field :code, :string
    field :revoked_at, :utc_datetime_usec

    belongs_to :workspace, Workspace, type: :binary_id
    belongs_to :created_by, User, type: :binary_id
    belongs_to :revoked_by, User, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(invite, attrs) do
    invite
    |> cast(attrs, [:workspace_id, :code, :created_by_id])
    |> validate_required([:workspace_id, :code, :created_by_id])
    |> unique_constraint(:code)
    |> unique_constraint(:workspace_id,
      name: :workspace_invites_one_active_per_workspace_idx,
      message: "an active invite already exists for this workspace"
    )
  end
end
