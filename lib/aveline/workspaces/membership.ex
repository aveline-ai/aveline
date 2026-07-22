defmodule Aveline.Workspaces.Membership do
  @moduledoc false
  use Aveline.Schema
  import Ecto.Changeset

  alias Aveline.Accounts.User
  alias Aveline.Workspaces.Workspace

  schema "workspace_memberships" do
    field :role, :string, default: "member"
    # Onboarding: user clicked "skip for now" on the setup hero; the
    # card collapses to its compact form until an agent connects.
    field :setup_skipped_at, :utc_datetime_usec

    belongs_to :workspace, Workspace, type: :binary_id
    belongs_to :user, User, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:workspace_id, :user_id, :role])
    |> validate_required([:workspace_id, :user_id, :role])
    |> validate_inclusion(:role, ["member", "admin"])
    |> unique_constraint([:workspace_id, :user_id],
      name: :workspace_memberships_workspace_id_user_id_index
    )
  end
end
