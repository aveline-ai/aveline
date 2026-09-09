defmodule Aveline.Gleam.Caps.Team do
  @moduledoc "Real IO for src/aveline/caps/team.gleam. Keep field order in lockstep."

  import Aveline.Gleam.Interop

  alias Aveline.Accounts
  alias Aveline.Repo
  alias Aveline.Workspaces
  alias Aveline.Workspaces.Invite
  alias Aveline.Workspaces.Membership
  alias Phoenix.PubSub

  def build do
    {:team_caps,
     fn workspace_id ->
       workspace_id |> Workspaces.list_members() |> Enum.map(&member/1)
     end,
     fn username ->
       username |> Accounts.get_user_by_username() |> opt(&team_user/1)
     end,
     fn workspace_id, user_id -> Workspaces.member?(workspace_id, user_id) end,
     fn workspace_id, user_id ->
       {:ok, membership} = Workspaces.add_member(workspace_id, user_id)

       broadcast(workspace_id, :member_added, %{
         membership: membership,
         user: Accounts.get_user!(user_id)
       })

       nil
     end,
     fn workspace_id, user_id ->
       Workspaces.get_membership(workspace_id, user_id)
       |> opt(fn m ->
         m = Repo.preload(m, :user)
         {:membership_ref, m.id, m.user.username}
       end)
     end,
     fn membership_id, workspace_id, user_id ->
       Repo.delete!(Repo.get!(Membership, membership_id))
       broadcast(workspace_id, :member_removed, %{user_id: user_id})
       nil
     end,
     fn workspace_id ->
       workspace_id |> Workspaces.get_active_invite_for_workspace() |> opt(&invite/1)
     end,
     fn workspace_id, created_by_id ->
       {:ok, fresh} =
         %Invite{}
         |> Invite.changeset(%{
           workspace_id: workspace_id,
           code: Workspaces.mint_invite_code(),
           created_by_id: created_by_id
         })
         |> Repo.insert()

       invite(fresh)
     end,
     fn invite_id, user_id ->
       {:ok, _} = Workspaces.revoke_invite(Repo.get!(Invite, invite_id), user_id)
       nil
     end,
     fn -> AvelineWeb.Endpoint.url() end}
  end

  defp member(m) do
    {:member, team_user(m.user), m.role, DateTime.to_iso8601(m.inserted_at)}
  end

  defp team_user(u) do
    {:team_user, u.id, u.username, opt(u.display_name), opt(u.email)}
  end

  defp invite(i), do: {:invite, i.id, i.code}

  defp broadcast(workspace_id, event, payload) do
    PubSub.broadcast(
      Aveline.PubSub,
      Workspaces.members_topic(workspace_id),
      {event, payload}
    )
  end
end
