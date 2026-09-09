//// Team endpoints: GET/POST /members, DELETE /members/:user_id,
//// POST /invite, DELETE /invite. Ports TeamController plus the
//// decision logic in Aveline.Workspaces (add_member_by_username,
//// remove_member, ensure_invite, revoke_invite).

import aveline/core/ctx.{type Ctx}
import aveline/core/error.{type ApiError, Invalid, NotFound}
import aveline/core/events.{EventAttrs, Human}
import aveline/core/scope.{type Scope}
import aveline/team/member.{type Member}
import aveline/team/user_ref.{UserId, Username}
import gleam/option.{None, Some}
import gleam/result
import gleam/string

pub type InviteResponse {
  InviteResponse(code: String, url: String)
}

pub fn list(ctx: Ctx, scope: Scope) -> List(Member) {
  ctx.team.list_members(scope.workspace.id)
}

/// Add a member by username. An explicit invite: unlike the idempotent
/// signup flow (ensure_member), adding someone twice is surfaced as
/// already_member so the caller can branch.
pub fn add(ctx: Ctx, scope: Scope, username: String) -> Result(Nil, ApiError) {
  let username = string.lowercase(string.trim(username))

  case ctx.team.find_user_by_username(username) {
    None -> Error(NotFound)
    Some(user) ->
      case ctx.team.is_member(scope.workspace.id, user.id) {
        True -> Error(already_member())
        False -> {
          ctx.team.insert_member(scope.workspace.id, user.id)

          ctx.events.record(EventAttrs(
            workspace_id: scope.workspace.id,
            actor: scope.actor.id,
            actor_type: Human,
            action: "member_joined",
            target_kind: "user",
            target_id: user.id,
            target_slug: None,
            target_label: Some(user.username),
          ))

          Ok(Nil)
        }
      }
  }
}

/// Remove a member. `ref` is a user id (UUID) or a username — see
/// aveline/team/user_ref. Can't remove yourself.
pub fn remove(ctx: Ctx, scope: Scope, ref: String) -> Result(Nil, ApiError) {
  use target_id <- result.try(case user_ref.parse(ref) {
    UserId(id) -> Ok(id)
    Username(name) ->
      case ctx.team.find_user_by_username(name) {
        None -> Error(not_member())
        Some(user) -> Ok(user.id)
      }
  })

  case target_id == scope.actor.id {
    True ->
      Error(Invalid(
        "self_remove",
        "You can't remove yourself from a workspace.",
      ))
    False ->
      case ctx.team.get_membership(scope.workspace.id, target_id) {
        None -> Error(not_member())
        Some(membership) -> {
          ctx.team.delete_membership(
            membership.id,
            scope.workspace.id,
            target_id,
          )

          ctx.events.record(EventAttrs(
            workspace_id: scope.workspace.id,
            actor: scope.actor.id,
            actor_type: Human,
            action: "member_removed",
            target_kind: "user",
            target_id: target_id,
            target_slug: None,
            target_label: Some(membership.username),
          ))

          Ok(Nil)
        }
      }
  }
}

/// Return the workspace's invite URL, minting one if none is active.
/// Idempotent (ports Workspaces.ensure_invite).
pub fn invite(ctx: Ctx, scope: Scope) -> Result(InviteResponse, ApiError) {
  let code = case ctx.team.get_active_invite(scope.workspace.id) {
    Some(existing) -> existing.code
    None -> {
      let fresh = ctx.team.create_invite(scope.workspace.id, scope.actor.id)
      fresh.code
    }
  }

  Ok(InviteResponse(
    code: code,
    url: ctx.team.invite_base_url() <> "/invite/" <> code,
  ))
}

/// Revoke the active invite. No active invite is a quiet success —
/// the desired state (no working link) already holds.
pub fn revoke_invite(ctx: Ctx, scope: Scope) -> Result(Nil, ApiError) {
  case ctx.team.get_active_invite(scope.workspace.id) {
    None -> Ok(Nil)
    Some(existing) -> {
      ctx.team.revoke_invite(existing.id, scope.actor.id)
      Ok(Nil)
    }
  }
}

fn already_member() -> ApiError {
  Invalid("already_member", "User is already a member of this workspace.")
}

fn not_member() -> ApiError {
  Invalid("not_member", "User is not a member of this workspace.")
}
