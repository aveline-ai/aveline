//// GET /events — workspace activity feed. Ports EventController.index:
//// Gleam owns limit parsing and response assembly; the paginated
//// listing (ordering, cursor anchoring, private-doc hiding) is one
//// coarse SQL cap.

import aveline/caps/events.{type EventRow, EventQuery}
import aveline/core/ctx.{type Ctx}
import aveline/core/scope.{type Scope}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

pub type EventsResponse {
  EventsResponse(events: List(EventRow), next_before_id: Option(String))
}

pub fn index(
  ctx: Ctx,
  scope: Scope,
  limit_param: Option(String),
  before_id: Option(String),
) -> EventsResponse {
  let events =
    ctx.events.list_for_workspace(
      scope.workspace.id,
      EventQuery(
        limit: parse_limit(limit_param),
        before_id: before_id,
        viewer: scope.actor.id,
      ),
    )

  // Agents pass the oldest id from this batch as `before_id` for the
  // next page.
  let next = case list.last(events) {
    Ok(event) -> Some(event.id)
    Error(Nil) -> None
  }

  EventsResponse(events: events, next_before_id: next)
}

/// Default 50; only whole numbers in 1..200 are honored, anything else
/// falls back to the default (never an error — same as before the port).
fn parse_limit(raw: Option(String)) -> Int {
  case raw {
    None -> 50
    Some(s) ->
      case int.parse(s) {
        Ok(n) ->
          case n > 0 && n <= 200 {
            True -> n
            False -> 50
          }
        Error(Nil) -> 50
      }
  }
}
