//// Team-domain test fixtures.

import aveline/team/member.{type TeamUser, Member, TeamUser}
import gleam/option.{None}

pub fn user(id id: String, username username: String) -> TeamUser {
  TeamUser(id: id, username: username, display_name: None, email: None)
}

pub fn member(user user: TeamUser) -> member.Member {
  Member(user: user, role: "member", joined_at: "2026-01-01T00:00:00.000000Z")
}
