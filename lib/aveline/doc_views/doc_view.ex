defmodule Aveline.DocViews.DocView do
  @moduledoc """
  One row per "I read this doc" event, recorded from both the web LV and
  the API doc-show endpoint. We don't dedup by session — popularity is
  computed as count-of-rows in a time window.
  """
  use Aveline.Schema

  alias Aveline.Accounts.User
  alias Aveline.Workspaces.Workspace

  schema "doc_views" do
    field :base_doc_id, :binary_id
    field :actor_type, :string
    field :viewed_at, :utc_datetime_usec

    belongs_to :workspace, Workspace, type: :binary_id
    belongs_to :user, User, type: :binary_id
  end
end
