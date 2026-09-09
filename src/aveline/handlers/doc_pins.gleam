//// Home-page pin endpoints: POST /docs/:slug/pin, DELETE /docs/:slug/pin.
//// Ports DocController.pin/unpin plus the decision logic of
//// Docs.pin/unpin: slot parsing, the orientation/private rules, slot
//// resolution (lowest free), and the no-silent-displacement rule. The
//// mutation + broadcast + activity event stay behind `set_pin_slot`.

import aveline/core/ctx.{type Ctx}
import aveline/core/scope.{type Scope}
import aveline/docs/access
import aveline/docs/doc_error.{
  type DocError, PinLimitReached, PinSlotTaken, invalid,
}
import aveline/docs/doc_meta.{type DocMeta, Private}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

pub const pin_limit = 6

/// The raw ?slot param as the controller marshals it: absent, already an
/// integer, a string to parse, or some other JSON value.
pub type SlotParam {
  NoSlot
  IntSlot(Int)
  RawSlot(String)
  BadSlot
}

pub type PinResponse {
  PinResponse(slug: String, pin_slot: Option(Int))
}

pub fn pin(
  ctx: Ctx,
  scope: Scope,
  slug: String,
  slot_param: SlotParam,
) -> Result(PinResponse, DocError) {
  use doc <- result.try(doc_error.api(access.fetch_readable(ctx, scope, slug)))
  use slot <- result.try(parse_slot(slot_param))
  use _ <- result.try(check_pinnable(doc, slot))

  let taken = ctx.docs.pinned_slots(scope.workspace.id, doc.base_doc_id)
  use resolved <- result.try(resolve_slot(slot, taken))

  ctx.docs.set_pin_slot(
    scope.workspace.id,
    slug,
    Some(resolved),
    scope.actor.id,
  )
  Ok(PinResponse(slug: doc.slug, pin_slot: Some(resolved)))
}

pub fn unpin(
  ctx: Ctx,
  scope: Scope,
  slug: String,
) -> Result(PinResponse, DocError) {
  use doc <- result.try(doc_error.api(access.fetch_readable(ctx, scope, slug)))
  case doc.pin_slot {
    None -> Error(invalid("validation_failed", "doc is not pinned"))
    Some(_) -> {
      ctx.docs.set_pin_slot(scope.workspace.id, slug, None, scope.actor.id)
      Ok(PinResponse(slug: doc.slug, pin_slot: None))
    }
  }
}

pub fn parse_slot(param: SlotParam) -> Result(Option(Int), DocError) {
  case param {
    NoSlot -> Ok(None)
    IntSlot(n) -> Ok(Some(n))
    RawSlot(s) ->
      case int.parse(s) {
        Ok(n) -> Ok(Some(n))
        Error(_) ->
          Error(invalid(
            "validation_failed",
            "pin slot must be an integer between 1 and 6",
          ))
      }
    BadSlot ->
      Error(invalid(
        "validation_failed",
        "pin slot must be an integer between 1 and 6",
      ))
  }
}

// Rule order matches the legacy Docs.pin clauses: orientation, then
// private, then the slot-range guard.
fn check_pinnable(doc: DocMeta, slot: Option(Int)) -> Result(Nil, DocError) {
  case doc.orientation {
    True ->
      Error(invalid(
        "validation_failed",
        "the orientation doc has its own card on the home page; it can't take a pin slot",
      ))
    False ->
      case doc.visibility {
        // The home page is a team surface; a pinned private doc would
        // leak its title to everyone.
        Private ->
          Error(invalid(
            "validation_failed",
            "private docs can't be pinned; make the doc workspace-visible first",
          ))
        _ ->
          case slot {
            Some(n) if n < 1 || n > pin_limit ->
              Error(invalid(
                "validation_failed",
                "pin slot must be between 1 and " <> int.to_string(pin_limit),
              ))
            _ -> Ok(Nil)
          }
      }
  }
}

// With no explicit slot the lowest free one is taken. An explicit slot
// held by another doc errors — slots never displace silently.
fn resolve_slot(
  slot: Option(Int),
  taken: List(#(Int, String)),
) -> Result(Int, DocError) {
  let resolved = case slot {
    Some(n) -> Some(n)
    None ->
      [1, 2, 3, 4, 5, 6]
      |> list.find(fn(n) { !list.any(taken, fn(entry) { entry.0 == n }) })
      |> option.from_result
  }

  case resolved {
    None -> Error(PinLimitReached)
    Some(n) ->
      case list.find(taken, fn(entry) { entry.0 == n }) {
        Ok(#(_, occupant)) -> Error(PinSlotTaken(n, occupant))
        Error(_) -> Ok(n)
      }
  }
}
