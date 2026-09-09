//// Team domain types: workspace members and the invite link.

import gleam/option.{type Option}

pub type TeamUser {
  TeamUser(
    id: String,
    username: String,
    display_name: Option(String),
    email: Option(String),
  )
}

pub type Member {
  /// One workspace membership row, user preloaded. `joined_at` is
  /// ISO8601 (display value — see PORTING.md timestamp convention).
  Member(user: TeamUser, role: String, joined_at: String)
}

pub type MembershipRef {
  /// Just enough of a membership to delete it and label the event.
  MembershipRef(id: String, username: String)
}

pub type Invite {
  Invite(id: String, code: String)
}
