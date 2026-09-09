//// Activity-event IO capabilities. Built in lib/aveline/gleam/caps/events.ex.
//// `record` stays FIRST — it is shared surface every ported handler uses.

import aveline/accounts/user_info.{type UserInfo}
import aveline/core/events.{type EventAttrs}
import gleam/option.{type Option}

/// An event's free-form `data` payload — JSON-ish, passed through
/// opaquely (raw Elixir map at runtime), never inspected in Gleam.
pub type EventData

/// One feed row (mirrors AvelineWeb.Api.Views.event/1). Echo fields are
/// optional because legacy rows may carry nulls.
pub type EventRow {
  EventRow(
    id: String,
    action: Option(String),
    target_kind: Option(String),
    target_id: Option(String),
    target_slug: Option(String),
    target_label: Option(String),
    actor_type: Option(String),
    actor_user: Option(UserInfo),
    data: EventData,
    occurred_at: String,
  )
}

pub type EventQuery {
  EventQuery(limit: Int, before_id: Option(String), viewer: String)
}

pub type EventsCaps {
  EventsCaps(
    record: fn(EventAttrs) -> Nil,
    /// Cursor-paginated feed (one coarse read — ordering, cursor
    /// anchoring, and private-doc hiding stay in SQL).
    list_for_workspace: fn(String, EventQuery) -> List(EventRow),
  )
}

pub fn stub() -> EventsCaps {
  EventsCaps(record: fn(_) { Nil }, list_for_workspace: fn(_, _) {
    panic as "stub events.list_for_workspace"
  })
}
