import aveline/caps/docs.{DocsCaps}
import aveline/core/ctx.{Ctx}
import aveline/core/error.{Invalid, NotFound}
import aveline/docs/doc_error.{Api, PinLimitReached, PinSlotTaken}
import aveline/docs/doc_meta.{DocMeta}
import aveline/docs_fixtures
import aveline/fakes
import aveline/handlers/doc_pins.{BadSlot, IntSlot, NoSlot, PinResponse, RawSlot}
import gleam/option.{None, Some}

fn pinnable_ctx(
  taken taken: List(#(Int, String)),
  expect_slot expected: option.Option(Int),
) -> ctx.Ctx {
  let doc = docs_fixtures.doc(owner: "user-2")
  Ctx(
    ..fakes.ctx(),
    docs: DocsCaps(
      ..docs.stub(),
      get_current_by_slug: fn(_, _) { Some(doc) },
      pinned_slots: fn(workspace_id, base_doc_id) {
        assert workspace_id == "ws-1"
        assert base_doc_id == "base-1"
        taken
      },
      set_pin_slot: fn(_, slug, slot, actor) {
        assert slug == "notes"
        assert slot == expected
        assert actor == "user-1"
        Nil
      },
    ),
  )
}

pub fn pin_missing_doc_is_not_found_test() {
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(None))

  assert doc_pins.pin(ctx, fakes.scope(), "nope", NoSlot)
    == Error(Api(NotFound))
}

pub fn pin_bad_slot_string_test() {
  let doc = docs_fixtures.doc(owner: "user-2")
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(Some(doc)))

  assert doc_pins.pin(ctx, fakes.scope(), "notes", RawSlot("first"))
    == Error(
      Api(Invalid(
        "validation_failed",
        "pin slot must be an integer between 1 and 6",
      )),
    )

  assert doc_pins.pin(ctx, fakes.scope(), "notes", BadSlot)
    == Error(
      Api(Invalid(
        "validation_failed",
        "pin slot must be an integer between 1 and 6",
      )),
    )
}

pub fn pin_orientation_doc_is_rejected_test() {
  let doc = DocMeta(..docs_fixtures.doc(owner: "user-2"), orientation: True)
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(Some(doc)))

  assert doc_pins.pin(ctx, fakes.scope(), "notes", NoSlot)
    == Error(
      Api(Invalid(
        "validation_failed",
        "the orientation doc has its own card on the home page; it can't take a pin slot",
      )),
    )
}

pub fn pin_private_doc_is_rejected_test() {
  let doc = docs_fixtures.private_doc(owner: "user-1")
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(Some(doc)))

  assert doc_pins.pin(ctx, fakes.scope(), "notes", NoSlot)
    == Error(
      Api(Invalid(
        "validation_failed",
        "private docs can't be pinned; make the doc workspace-visible first",
      )),
    )
}

pub fn pin_out_of_range_slot_is_rejected_test() {
  let doc = docs_fixtures.doc(owner: "user-2")
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(Some(doc)))

  assert doc_pins.pin(ctx, fakes.scope(), "notes", IntSlot(9))
    == Error(
      Api(Invalid("validation_failed", "pin slot must be between 1 and 6")),
    )
}

pub fn pin_explicit_free_slot_test() {
  let ctx = pinnable_ctx(taken: [#(1, "a")], expect_slot: Some(4))

  assert doc_pins.pin(ctx, fakes.scope(), "notes", RawSlot("4"))
    == Ok(PinResponse(slug: "notes", pin_slot: Some(4)))
}

pub fn pin_takes_lowest_free_slot_test() {
  let ctx =
    pinnable_ctx(taken: [#(1, "a"), #(2, "b"), #(4, "d")], expect_slot: Some(3))

  assert doc_pins.pin(ctx, fakes.scope(), "notes", NoSlot)
    == Ok(PinResponse(slug: "notes", pin_slot: Some(3)))
}

pub fn pin_occupied_slot_never_displaces_test() {
  let ctx = pinnable_ctx(taken: [#(2, "deploy-guide")], expect_slot: None)

  assert doc_pins.pin(ctx, fakes.scope(), "notes", IntSlot(2))
    == Error(PinSlotTaken(2, "deploy-guide"))
}

pub fn pin_full_shelf_is_limit_reached_test() {
  let taken = [#(1, "a"), #(2, "b"), #(3, "c"), #(4, "d"), #(5, "e"), #(6, "f")]
  let ctx = pinnable_ctx(taken: taken, expect_slot: None)

  assert doc_pins.pin(ctx, fakes.scope(), "notes", NoSlot)
    == Error(PinLimitReached)
}

pub fn unpin_unpinned_doc_is_rejected_test() {
  let doc = docs_fixtures.doc(owner: "user-2")
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(Some(doc)))

  assert doc_pins.unpin(ctx, fakes.scope(), "notes")
    == Error(Api(Invalid("validation_failed", "doc is not pinned")))
}

pub fn unpin_frees_the_slot_test() {
  let doc = DocMeta(..docs_fixtures.doc(owner: "user-2"), pin_slot: Some(3))
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs.stub(),
        get_current_by_slug: fn(_, _) { Some(doc) },
        set_pin_slot: fn(_, slug, slot, _) {
          assert slug == "notes"
          assert slot == None
          Nil
        },
      ),
    )

  assert doc_pins.unpin(ctx, fakes.scope(), "notes")
    == Ok(PinResponse(slug: "notes", pin_slot: None))
}
