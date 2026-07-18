defmodule Aveline.Milestones.Milestone do
  @moduledoc false
  use Aveline.Schema
  import Ecto.Changeset

  alias Aveline.Accounts.User
  alias Aveline.Workspaces.Workspace

  schema "milestones" do
    field :name, :string
    field :date, :date
    field :description, :string
    field :deleted_at, :utc_datetime_usec

    belongs_to :workspace, Workspace, type: :binary_id
    belongs_to :created_by, User, type: :binary_id
    belongs_to :deleted_by, User, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(milestone, attrs) do
    milestone
    |> cast(attrs, [:workspace_id, :name, :date, :description, :created_by_id])
    |> update_change(:name, &String.trim/1)
    |> update_change(:description, fn
      nil -> nil
      d -> with "" <- String.trim(d), do: nil
    end)
    |> validate_required([:workspace_id, :name, :date])
    |> validate_length(:name, min: 1, max: 80)
  end
end
