defmodule Aveline.SidebarFavorites.Favorite do
  @moduledoc """
  A per-user "star this tag" record. Stars bubble that tag to the top of
  the user's own sidebar. Different from global doc pinning, which
  everyone sees.
  """
  use Aveline.Schema

  alias Aveline.Accounts.User
  alias Aveline.Workspaces.Workspace

  schema "sidebar_favorites" do
    field :tag, :string
    field :inserted_at, :utc_datetime_usec

    belongs_to :user, User, type: :binary_id
    belongs_to :workspace, Workspace, type: :binary_id
  end
end
