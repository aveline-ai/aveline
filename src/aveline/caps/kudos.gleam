//// Kudos IO capabilities. Built for real in lib/aveline/gleam/caps/kudos.ex.

import gleam/option.{type Option}

pub type KudosCaps {
  KudosCaps(
    /// Kudos row id for (base_doc_id, user_id), if one exists.
    find: fn(String, String) -> Option(String),
    /// Insert a kudos row: (workspace_id, base_doc_id, user_id).
    give: fn(String, String, String) -> Nil,
    /// Delete a kudos row by id.
    revoke: fn(String) -> Nil,
    count_for_base: fn(String) -> Int,
  )
}

pub fn stub() -> KudosCaps {
  KudosCaps(
    find: fn(_, _) { panic as "stub kudos.find" },
    give: fn(_, _, _) { panic as "stub kudos.give" },
    revoke: fn(_) { panic as "stub kudos.revoke" },
    count_for_base: fn(_) { panic as "stub kudos.count_for_base" },
  )
}
