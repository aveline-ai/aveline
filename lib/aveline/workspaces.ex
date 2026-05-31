defmodule Aveline.Workspaces do
  @moduledoc """
  Workspace + membership management.
  """

  import Ecto.Query

  alias Aveline.Accounts
  alias Aveline.Repo
  alias Aveline.Workspaces.Membership
  alias Aveline.Workspaces.Workspace
  alias Phoenix.PubSub

  @doc """
  Base query — excludes soft-deleted workspaces.
  """
  def base_query do
    from w in Workspace, where: is_nil(w.deleted_at)
  end

  @doc """
  List workspaces a user is a member of (non-deleted).
  """
  def list_for_user(user_id) do
    from(w in base_query(),
      join: m in Membership,
      on: m.workspace_id == w.id,
      where: m.user_id == ^user_id,
      order_by: [asc: w.name]
    )
    |> Repo.all()
  end

  @doc """
  Direct lookup by slug — does NOT filter soft-deleted (caller decides).
  """
  def get_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Workspace, slug: slug)
  end

  def get_by_slug(_), do: nil

  @doc """
  Lookup by slug that excludes soft-deleted.
  """
  def get_active_by_slug(slug) when is_binary(slug) do
    from(w in base_query(), where: w.slug == ^slug)
    |> Repo.one()
  end

  def get_active_by_slug(_), do: nil

  def get_workspace(id), do: Repo.get(Workspace, id)

  def create_workspace(attrs) do
    %Workspace{}
    |> Workspace.changeset(attrs)
    |> Repo.insert()
  end

  def update_workspace(%Workspace{} = workspace, attrs) do
    workspace
    |> Workspace.update_changeset(attrs)
    |> Repo.update()
  end

  def soft_delete_workspace(%Workspace{} = workspace, deleted_by_id) do
    workspace
    |> Ecto.Changeset.change(%{
      deleted_at: DateTime.utc_now(),
      deleted_by_id: deleted_by_id
    })
    |> Repo.update()
  end

  # ===== Memberships =====

  def add_member(workspace_id, user_id, role \\ "member") do
    %Membership{}
    |> Membership.changeset(%{
      workspace_id: workspace_id,
      user_id: user_id,
      role: role
    })
    |> Repo.insert()
  end

  def ensure_member(workspace_id, user_id, role \\ "member") do
    case Repo.get_by(Membership, workspace_id: workspace_id, user_id: user_id) do
      nil -> add_member(workspace_id, user_id, role)
      %Membership{} = m -> {:ok, m}
    end
  end

  def member?(workspace_id, user_id) do
    Repo.exists?(
      from m in Membership,
        where: m.workspace_id == ^workspace_id and m.user_id == ^user_id
    )
  end

  def get_membership(workspace_id, user_id) do
    Repo.get_by(Membership, workspace_id: workspace_id, user_id: user_id)
  end

  def list_members(workspace_id) do
    from(m in Membership,
      where: m.workspace_id == ^workspace_id,
      order_by: [asc: m.inserted_at],
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc """
  Add a workspace member by username. Returns
    * `{:ok, %Membership{}, %User{}}` on success (or if already a member — idempotent)
    * `{:error, :user_not_found}` if no user with that username exists
    * `{:error, changeset}` on validation failure
  """
  def add_member_by_username(workspace_id, username) when is_binary(username) do
    username = username |> String.trim() |> String.downcase()

    case Accounts.get_user_by_username(username) do
      nil ->
        {:error, :user_not_found}

      user ->
        with {:ok, membership} <- ensure_member(workspace_id, user.id) do
          broadcast_member(workspace_id, :member_added, %{
            membership: membership,
            user: user
          })

          {:ok, membership, user}
        end
    end
  end

  def add_member_by_username(_, _), do: {:error, :user_not_found}

  def remove_member(workspace_id, user_id) do
    case get_membership(workspace_id, user_id) do
      nil ->
        {:error, :not_found}

      m ->
        case Repo.delete(m) do
          {:ok, deleted} ->
            broadcast_member(workspace_id, :member_removed, %{user_id: user_id})
            {:ok, deleted}

          err ->
            err
        end
    end
  end

  def members_topic(workspace_id), do: "workspace:" <> workspace_id <> ":members"

  defp broadcast_member(workspace_id, event, payload) do
    PubSub.broadcast(Aveline.PubSub, members_topic(workspace_id), {event, payload})
  end
end
