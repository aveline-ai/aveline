defmodule Aveline.Views.BucketMember do
  @moduledoc """
  Binary membership in a project bucket: you're in or you're out, and
  in means you can use (and edit) every view the bucket holds. Team and
  personal buckets have implicit audiences and never carry member rows.
  """
  use Aveline.Schema
  import Ecto.Changeset

  alias Aveline.Accounts.User
  alias Aveline.Views.Bucket

  schema "view_bucket_members" do
    field :deleted_at, :utc_datetime_usec

    belongs_to :bucket, Bucket, type: :binary_id
    belongs_to :user, User, type: :binary_id
    belongs_to :added_by, User, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:bucket_id, :user_id, :added_by_id])
    |> validate_required([:bucket_id, :user_id])
    |> unique_constraint([:bucket_id, :user_id], name: :view_bucket_members_live_unique)
  end
end
