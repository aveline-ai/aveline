import aveline/caps/events.{EventsCaps} as caps_events
import aveline/caps/team.{TeamCaps}
import aveline/core/ctx.{Ctx}
import aveline/core/error.{Invalid, NotFound}
import aveline/core/events.{Human}
import aveline/core/scope.{type Scope, Actor, Scope}
import aveline/fakes
import aveline/handlers/team as handlers
import aveline/team/member.{Invite}
import aveline/team_fixtures
import gleam/option.{None, Some}

// scope() is ws-1 / user-1 "arie" (see fakes.gleam).
const actor_id = "user-1"

// ===== index =====

pub fn list_returns_the_members_cap_result_test() {
  let members = [
    team_fixtures.member(user: team_fixtures.user(id: "user-2", username: "bob")),
  ]
  let ctx =
    Ctx(
      ..fakes.ctx(),
      team: TeamCaps(..team.stub(), list_members: fn(ws_id) {
        assert ws_id == "ws-1"
        members
      }),
    )

  assert handlers.list(ctx, fakes.scope()) == members
}

// ===== add =====

pub fn add_unknown_username_is_not_found_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      team: TeamCaps(..team.stub(), find_user_by_username: fn(_) { None }),
    )

  assert handlers.add(ctx, fakes.scope(), "ghost") == Error(NotFound)
}

pub fn add_normalizes_the_username_before_lookup_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      team: TeamCaps(..team.stub(), find_user_by_username: fn(name) {
        // trimmed + downcased, same as Workspaces.add_member_by_username
        assert name == "bob"
        None
      }),
    )

  assert handlers.add(ctx, fakes.scope(), "  BoB ") == Error(NotFound)
}

pub fn add_existing_member_is_already_member_test() {
  let bob = team_fixtures.user(id: "user-2", username: "bob")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      team: TeamCaps(
        ..team.stub(),
        find_user_by_username: fn(_) { Some(bob) },
        is_member: fn(_, _) { True },
      ),
    )

  assert handlers.add(ctx, fakes.scope(), "bob")
    == Error(Invalid(
      "already_member",
      "User is already a member of this workspace.",
    ))
}

pub fn add_inserts_membership_and_records_event_test() {
  let bob = team_fixtures.user(id: "user-2", username: "bob")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      team: TeamCaps(
        ..team.stub(),
        find_user_by_username: fn(_) { Some(bob) },
        is_member: fn(_, _) { False },
        insert_member: fn(ws_id, user_id) {
          assert ws_id == "ws-1"
          assert user_id == "user-2"
          Nil
        },
      ),
      events: EventsCaps(..caps_events.stub(), record: fn(attrs: events.EventAttrs) {
        assert attrs.action == "member_joined"
        assert attrs.actor == actor_id
        assert attrs.actor_type == Human
        assert attrs.target_kind == "user"
        assert attrs.target_id == "user-2"
        assert attrs.target_slug == None
        assert attrs.target_label == Some("bob")
        Nil
      }),
    )

  assert handlers.add(ctx, fakes.scope(), "bob") == Ok(Nil)
}

// ===== remove =====

pub fn remove_self_by_id_is_rejected_test() {
  // A UUID form of "self" proves the id path is taken without a
  // username lookup (the team stub would panic on one).
  let uuid = "0b8228b5-72f4-4d47-9d23-0e94c9a4d63a"
  let self_scope = aveline_scope_with_actor_id(fakes.scope(), uuid)

  assert handlers.remove(fakes.ctx(), self_scope, uuid)
    == Error(Invalid(
      "self_remove",
      "You can't remove yourself from a workspace.",
    ))
}

pub fn remove_self_by_uppercase_uuid_is_rejected_test() {
  let uuid = "0b8228b5-72f4-4d47-9d23-0e94c9a4d63a"
  let self_scope = aveline_scope_with_actor_id(fakes.scope(), uuid)

  assert handlers.remove(
      fakes.ctx(),
      self_scope,
      "0B8228B5-72F4-4D47-9D23-0E94C9A4D63A",
    )
    == Error(Invalid(
      "self_remove",
      "You can't remove yourself from a workspace.",
    ))
}

pub fn remove_self_by_username_is_rejected_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      team: TeamCaps(..team.stub(), find_user_by_username: fn(name) {
        assert name == "arie"
        Some(team_fixtures.user(id: actor_id, username: "arie"))
      }),
    )

  assert handlers.remove(ctx, fakes.scope(), "arie")
    == Error(Invalid(
      "self_remove",
      "You can't remove yourself from a workspace.",
    ))
}

pub fn remove_unknown_username_is_not_member_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      team: TeamCaps(..team.stub(), find_user_by_username: fn(_) { None }),
    )

  assert handlers.remove(ctx, fakes.scope(), "ghost")
    == Error(Invalid("not_member", "User is not a member of this workspace."))
}

pub fn remove_non_member_id_is_not_member_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      team: TeamCaps(..team.stub(), get_membership: fn(_, _) { None }),
    )

  assert handlers.remove(
      ctx,
      fakes.scope(),
      "0b8228b5-72f4-4d47-9d23-0e94c9a4d63a",
    )
    == Error(Invalid("not_member", "User is not a member of this workspace."))
}

pub fn remove_deletes_membership_and_records_event_test() {
  let target = "0b8228b5-72f4-4d47-9d23-0e94c9a4d63a"
  let ctx =
    Ctx(
      ..fakes.ctx(),
      team: TeamCaps(
        ..team.stub(),
        get_membership: fn(ws_id, user_id) {
          assert ws_id == "ws-1"
          assert user_id == target
          Some(member.MembershipRef(id: "m-1", username: "bob"))
        },
        delete_membership: fn(membership_id, ws_id, user_id) {
          assert membership_id == "m-1"
          assert ws_id == "ws-1"
          assert user_id == target
          Nil
        },
      ),
      events: EventsCaps(..caps_events.stub(), record: fn(attrs: events.EventAttrs) {
        assert attrs.action == "member_removed"
        assert attrs.actor == actor_id
        assert attrs.actor_type == Human
        assert attrs.target_kind == "user"
        assert attrs.target_id == target
        assert attrs.target_slug == None
        assert attrs.target_label == Some("bob")
        Nil
      }),
    )

  assert handlers.remove(ctx, fakes.scope(), target) == Ok(Nil)
}

pub fn remove_by_username_resolves_then_deletes_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      team: TeamCaps(
        ..team.stub(),
        // Raw ref, no trim/downcase — parity with resolve_user_ref.
        find_user_by_username: fn(name) {
          assert name == "bob"
          Some(team_fixtures.user(id: "user-2", username: "bob"))
        },
        get_membership: fn(_, user_id) {
          assert user_id == "user-2"
          Some(member.MembershipRef(id: "m-1", username: "bob"))
        },
        delete_membership: fn(_, _, _) { Nil },
      ),
      events: EventsCaps(..caps_events.stub(), record: fn(_) { Nil }),
    )

  assert handlers.remove(ctx, fakes.scope(), "bob") == Ok(Nil)
}

// ===== invite =====

pub fn invite_reuses_the_active_invite_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      team: TeamCaps(
        ..team.stub(),
        get_active_invite: fn(ws_id) {
          assert ws_id == "ws-1"
          Some(Invite(id: "inv-1", code: "inv_abc"))
        },
        invite_base_url: fn() { "https://app.test" },
      ),
    )

  assert handlers.invite(ctx, fakes.scope())
    == Ok(handlers.InviteResponse(
      code: "inv_abc",
      url: "https://app.test/invite/inv_abc",
    ))
}

pub fn invite_mints_when_none_active_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      team: TeamCaps(
        ..team.stub(),
        get_active_invite: fn(_) { None },
        create_invite: fn(ws_id, created_by) {
          assert ws_id == "ws-1"
          assert created_by == actor_id
          Invite(id: "inv-2", code: "inv_fresh")
        },
        invite_base_url: fn() { "https://app.test" },
      ),
    )

  assert handlers.invite(ctx, fakes.scope())
    == Ok(handlers.InviteResponse(
      code: "inv_fresh",
      url: "https://app.test/invite/inv_fresh",
    ))
}

// ===== revoke invite =====

pub fn revoke_with_no_active_invite_is_a_quiet_success_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      team: TeamCaps(..team.stub(), get_active_invite: fn(_) { None }),
    )

  assert handlers.revoke_invite(ctx, fakes.scope()) == Ok(Nil)
}

pub fn revoke_revokes_the_active_invite_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      team: TeamCaps(
        ..team.stub(),
        get_active_invite: fn(_) { Some(Invite(id: "inv-1", code: "inv_abc")) },
        revoke_invite: fn(invite_id, user_id) {
          assert invite_id == "inv-1"
          assert user_id == actor_id
          Nil
        },
      ),
    )

  assert handlers.revoke_invite(ctx, fakes.scope()) == Ok(Nil)
}

// ===== helpers =====

fn aveline_scope_with_actor_id(base: Scope, id: String) -> Scope {
  Scope(..base, actor: Actor(..base.actor, id: id))
}
