//// DELETE /members/:user_id accepts either a user id (UUID) or a
//// username — agents know usernames from list-members and shouldn't
//// need a second roundtrip for the UUID. Ports
//// TeamController.resolve_user_ref: a valid UUID is used as-is
//// (downcased, matching Ecto.UUID.cast), anything else is a username
//// to look up.

import gleam/list
import gleam/string

pub type UserRef {
  UserId(String)
  Username(String)
}

pub fn parse(ref: String) -> UserRef {
  case is_uuid(ref) {
    True -> UserId(string.lowercase(ref))
    False -> Username(ref)
  }
}

fn is_uuid(s: String) -> Bool {
  case string.split(s, "-") {
    [a, b, c, d, e] ->
      hex_of_length(a, 8)
      && hex_of_length(b, 4)
      && hex_of_length(c, 4)
      && hex_of_length(d, 4)
      && hex_of_length(e, 12)
    _ -> False
  }
}

fn hex_of_length(s: String, n: Int) -> Bool {
  string.length(s) == n
  && list.all(string.to_graphemes(s), fn(g) {
    string.contains("0123456789abcdefABCDEF", g)
  })
}
