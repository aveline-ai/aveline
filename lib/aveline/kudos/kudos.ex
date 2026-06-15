defmodule Aveline.Kudos.Kudos do
  @moduledoc """
  A "thanks, this helped" marker from a user on a logical doc. One per
  (user, base_doc). Toggle = delete-and-insert.
  """
  use Aveline.Schema

  alias Aveline.Accounts.User
  alias Aveline.Workspaces.Workspace

  schema "doc_kudos" do
    field :base_doc_id, :binary_id
    field :given_at, :utc_datetime_usec

    belongs_to :workspace, Workspace, type: :binary_id
    belongs_to :user, User, type: :binary_id
  end
end
