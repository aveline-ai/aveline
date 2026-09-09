//// Team IO capabilities (memberships, invites, user lookup). Built for
//// real in lib/aveline/gleam/caps/team.ex; keep the two in lockstep
//// (tag + field order).

import aveline/team/member.{
  type Invite, type Member, type MembershipRef, type TeamUser,
}
import gleam/option.{type Option}

pub type TeamCaps {
  TeamCaps(
    /// All memberships of a workspace, oldest first, users preloaded.
    list_members: fn(String) -> List(Member),
    /// User by exact username (caller normalizes when the flow wants it).
    find_user_by_username: fn(String) -> Option(TeamUser),
    /// Does a (workspace_id, user_id) membership exist?
    is_member: fn(String, String) -> Bool,
    /// Insert a membership (workspace_id, user_id) and broadcast
    /// member_added, same as Workspaces.add_member_by_username did.
    insert_member: fn(String, String) -> Nil,
    /// Membership row for (workspace_id, user_id), if any.
    get_membership: fn(String, String) -> Option(MembershipRef),
    /// Delete a membership and broadcast member_removed:
    /// (membership_id, workspace_id, user_id).
    delete_membership: fn(String, String, String) -> Nil,
    /// The workspace's unrevoked invite, if any.
    get_active_invite: fn(String) -> Option(Invite),
    /// Mint a code + insert a fresh invite: (workspace_id, created_by_id).
    create_invite: fn(String, String) -> Invite,
    /// Revoke an invite: (invite_id, revoked_by_id).
    revoke_invite: fn(String, String) -> Nil,
    /// Endpoint base URL for building the invite link.
    invite_base_url: fn() -> String,
  )
}

pub fn stub() -> TeamCaps {
  TeamCaps(
    list_members: fn(_) { panic as "stub team.list_members" },
    find_user_by_username: fn(_) { panic as "stub team.find_user_by_username" },
    is_member: fn(_, _) { panic as "stub team.is_member" },
    insert_member: fn(_, _) { panic as "stub team.insert_member" },
    get_membership: fn(_, _) { panic as "stub team.get_membership" },
    delete_membership: fn(_, _, _) { panic as "stub team.delete_membership" },
    get_active_invite: fn(_) { panic as "stub team.get_active_invite" },
    create_invite: fn(_, _) { panic as "stub team.create_invite" },
    revoke_invite: fn(_, _) { panic as "stub team.revoke_invite" },
    invite_base_url: fn() { panic as "stub team.invite_base_url" },
  )
}
