defmodule Aveline.Events.Event do
  @moduledoc """
  One row per significant action. The events table IS the workspace's
  history — feed of who-did-what across docs, comments, kudos, views,
  membership, pinning. Denormalized so the timeline can render without
  joining anything.
  """
  use Aveline.Schema

  alias Aveline.Accounts.User
  alias Aveline.Workspaces.Workspace

  schema "events" do
    field :actor_type, :string
    field :action, :string
    field :target_kind, :string
    field :target_id, :binary_id
    field :target_slug, :string
    field :target_label, :string
    field :data, :map, default: %{}
    field :inserted_at, :utc_datetime_usec

    belongs_to :workspace, Workspace, type: :binary_id
    belongs_to :actor_user, User, type: :binary_id
  end
end
