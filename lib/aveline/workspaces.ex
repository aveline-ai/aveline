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
  def add_member_by_username(workspace_id, username, actor_user_id \\ nil)

  def add_member_by_username(workspace_id, username, actor_user_id) when is_binary(username) do
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

          Aveline.Events.record(%{
            workspace_id: workspace_id,
            actor: actor_user_id || user.id,
            actor_type: "human",
            action: "member_joined",
            target_kind: "user",
            target_id: user.id,
            target_label: user.username
          })

          {:ok, membership, user}
        end
    end
  end

  def add_member_by_username(_, _, _), do: {:error, :user_not_found}

  def remove_member(workspace_id, user_id, actor_user_id \\ nil) do
    case get_membership(workspace_id, user_id) do
      nil ->
        {:error, :not_found}

      m ->
        m = Repo.preload(m, :user)

        case Repo.delete(m) do
          {:ok, deleted} ->
            broadcast_member(workspace_id, :member_removed, %{user_id: user_id})

            Aveline.Events.record(%{
              workspace_id: workspace_id,
              actor: actor_user_id || user_id,
              actor_type: "human",
              action: "member_removed",
              target_kind: "user",
              target_id: user_id,
              target_label: m.user && m.user.username
            })

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

  # ===== Invites =====

  alias Aveline.Workspaces.Invite

  @invite_prefix "inv_"

  def mint_invite_code do
    rand = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
    @invite_prefix <> binary_part(rand, 0, 22)
  end

  def get_active_invite_for_workspace(workspace_id) when is_binary(workspace_id) do
    Repo.one(
      from i in Invite,
        where: i.workspace_id == ^workspace_id and is_nil(i.revoked_at)
    )
  end

  def get_active_invite_by_code(code) when is_binary(code) do
    Repo.one(
      from i in Invite,
        where: i.code == ^code and is_nil(i.revoked_at),
        preload: [:workspace, :created_by]
    )
  end

  def get_active_invite_by_code(_), do: nil

  @doc """
  Get or create the active invite for the workspace. Idempotent.
  """
  def ensure_invite(workspace_id, created_by_id) do
    case get_active_invite_for_workspace(workspace_id) do
      %Invite{} = invite ->
        {:ok, invite}

      nil ->
        %Invite{}
        |> Invite.changeset(%{
          workspace_id: workspace_id,
          code: mint_invite_code(),
          created_by_id: created_by_id
        })
        |> Repo.insert()
    end
  end

  @doc """
  Rotate: revoke the existing active invite (if any) and mint a fresh one.
  Old links stop working immediately.
  """
  def rotate_invite(workspace_id, user_id) do
    Repo.transaction(fn ->
      case get_active_invite_for_workspace(workspace_id) do
        nil -> :ok
        %Invite{} = i ->
          {:ok, _} =
            i
            |> Ecto.Changeset.change(%{revoked_at: DateTime.utc_now(), revoked_by_id: user_id})
            |> Repo.update()
      end

      {:ok, fresh} =
        %Invite{}
        |> Invite.changeset(%{
          workspace_id: workspace_id,
          code: mint_invite_code(),
          created_by_id: user_id
        })
        |> Repo.insert()

      fresh
    end)
  end

  def revoke_invite(%Invite{} = invite, user_id) do
    invite
    |> Ecto.Changeset.change(%{revoked_at: DateTime.utc_now(), revoked_by_id: user_id})
    |> Repo.update()
  end
end
