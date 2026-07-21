defmodule Aveline.Views.Bucket do
  @moduledoc """
  A bucket: the space a view lives in and the unit views are shared at
  (see the view-buckets TIP). Three kinds:

    * `team`     — one per workspace, everyone, the default. Undeletable.
    * `personal` — one per person, just them, created lazily.
    * `project`  — created by a member, shared by binary membership.

  Audience comes from the kind: team = workspace members, personal =
  the owner, project = owner + live member rows.
  """
  use Aveline.Schema
  import Ecto.Changeset

  alias Aveline.Accounts.User
  alias Aveline.Workspaces.Workspace

  @kinds ~w(team personal project)

  schema "view_buckets" do
    field :name, :string
    field :kind, :string
    field :deleted_at, :utc_datetime_usec

    belongs_to :workspace, Workspace, type: :binary_id
    belongs_to :owner, User, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def kinds, do: @kinds

  def changeset(bucket, attrs) do
    bucket
    |> cast(attrs, [:workspace_id, :name, :kind, :owner_id])
    |> validate_required([:workspace_id, :name, :kind])
    |> update_change(:name, fn n ->
      if is_binary(n), do: n |> String.trim() |> String.downcase(), else: n
    end)
    |> validate_inclusion(:kind, @kinds)
    |> validate_name()
    |> unique_constraint([:workspace_id, :name],
      name: :view_buckets_live_name_unique,
      message: "already exists"
    )
  end

  defp validate_name(changeset) do
    case get_field(changeset, :name) do
      nil ->
        changeset

      name ->
        if Aveline.Slug.validate(name) == :ok,
          do: changeset,
          else: add_error(changeset, :name, "must be a slug (lowercase letters, digits, dashes)")
    end
  end
end
