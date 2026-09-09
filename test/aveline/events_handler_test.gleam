import aveline/caps/events.{type EventData, type EventRow, EventRow, EventsCaps} as events_caps
import aveline/core/ctx.{Ctx}
import aveline/fakes
import aveline/handlers/events.{EventsResponse} as handler
import gleam/option.{type Option, None, Some}

@external(erlang, "gleam_stdlib", "identity")
fn event_data(value: String) -> EventData

fn row(id: String) -> EventRow {
  EventRow(
    id: id,
    action: Some("doc_created"),
    target_kind: Some("doc"),
    target_id: Some("base-1"),
    target_slug: Some("notes"),
    target_label: Some("Notes"),
    actor_type: Some("human"),
    actor_user: None,
    data: event_data("payload"),
    occurred_at: "2026-09-01T00:00:00Z",
  )
}

fn ctx_expecting(
  limit limit: Int,
  before_id before_id: Option(String),
  returning rows: List(EventRow),
) -> ctx.Ctx {
  Ctx(
    ..fakes.ctx(),
    events: EventsCaps(
      ..events_caps.stub(),
      list_for_workspace: fn(ws_id, query) {
        assert ws_id == "ws-1"
        assert query
          == events_caps.EventQuery(
            limit: limit,
            before_id: before_id,
            viewer: "user-1",
          )
        rows
      },
    ),
  )
}

pub fn default_limit_is_fifty_test() {
  let ctx = ctx_expecting(limit: 50, before_id: None, returning: [])

  assert handler.index(ctx, fakes.scope(), None, None)
    == EventsResponse(events: [], next_before_id: None)
}

pub fn garbage_limits_fall_back_to_fifty_test() {
  let ctx = ctx_expecting(limit: 50, before_id: None, returning: [])
  let expected = EventsResponse(events: [], next_before_id: None)

  assert handler.index(ctx, fakes.scope(), Some(""), None) == expected
  assert handler.index(ctx, fakes.scope(), Some("abc"), None) == expected
  assert handler.index(ctx, fakes.scope(), Some("0"), None) == expected
  assert handler.index(ctx, fakes.scope(), Some("-3"), None) == expected
  assert handler.index(ctx, fakes.scope(), Some("201"), None) == expected
  assert handler.index(ctx, fakes.scope(), Some("5x"), None) == expected
}

pub fn in_range_limits_are_honored_test() {
  let ctx = ctx_expecting(limit: 7, before_id: None, returning: [])
  assert handler.index(ctx, fakes.scope(), Some("7"), None)
    == EventsResponse(events: [], next_before_id: None)

  let ctx = ctx_expecting(limit: 200, before_id: None, returning: [])
  assert handler.index(ctx, fakes.scope(), Some("200"), None)
    == EventsResponse(events: [], next_before_id: None)
}

pub fn before_id_cursor_passes_through_test() {
  let ctx = ctx_expecting(limit: 50, before_id: Some("e-5"), returning: [])

  assert handler.index(ctx, fakes.scope(), None, Some("e-5"))
    == EventsResponse(events: [], next_before_id: None)
}

pub fn next_cursor_is_the_oldest_id_in_the_batch_test() {
  let rows = [row("e-3"), row("e-2"), row("e-1")]
  let ctx = ctx_expecting(limit: 50, before_id: None, returning: rows)

  assert handler.index(ctx, fakes.scope(), None, None)
    == EventsResponse(events: rows, next_before_id: Some("e-1"))
}
