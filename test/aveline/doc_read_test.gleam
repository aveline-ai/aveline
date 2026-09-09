import aveline/caps/docs.{DocsCaps}
import aveline/core/ctx.{Ctx}
import aveline/core/error.{Invalid, NotFound}
import aveline/docs_fixtures
import aveline/fakes
import aveline/handlers/doc_read
import gleam/dynamic
import gleam/option.{None, Some}

pub fn show_missing_doc_is_not_found_test() {
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(None))

  assert doc_read.show(ctx, fakes.scope(), "nope") == Error(NotFound)
}

pub fn show_private_doc_hidden_from_non_shared_member_test() {
  let doc = docs_fixtures.private_doc(owner: "user-2")
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(Some(doc)))

  assert doc_read.show(ctx, fakes.scope(), "notes") == Error(NotFound)
}

pub fn show_records_view_and_returns_payload_test() {
  let doc = docs_fixtures.doc(owner: "user-2")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs.stub(),
        get_current_by_slug: fn(_, _) { Some(doc) },
        record_view: fn(workspace_id, base_doc_id, user_id, source) {
          assert workspace_id == "ws-1"
          assert base_doc_id == "base-1"
          assert user_id == "user-1"
          assert source == "agent"
          Nil
        },
        read_full: fn(workspace_id, slug, viewer) {
          assert workspace_id == "ws-1"
          assert slug == "notes"
          assert viewer == "user-1"
          Some(dynamic.string("full-doc"))
        },
      ),
    )

  assert doc_read.show(ctx, fakes.scope(), "notes")
    == Ok(dynamic.string("full-doc"))
}

pub fn show_race_vanished_doc_is_not_found_test() {
  let doc = docs_fixtures.doc(owner: "user-2")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs.stub(),
        get_current_by_slug: fn(_, _) { Some(doc) },
        read_full: fn(_, _, _) { None },
      ),
    )

  assert doc_read.show(ctx, fakes.scope(), "notes") == Error(NotFound)
}

pub fn orientation_missing_is_not_found_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(..docs.stub(), get_orientation: fn(_) { None }),
    )

  assert doc_read.orientation(ctx, fakes.scope()) == Error(NotFound)
}

pub fn orientation_returns_payload_test() {
  let doc = docs_fixtures.doc(owner: "user-2")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs.stub(),
        get_orientation: fn(workspace_id) {
          assert workspace_id == "ws-1"
          Some(doc)
        },
        read_full: fn(_, slug, _) {
          assert slug == "notes"
          Some(dynamic.string("orientation-doc"))
        },
      ),
    )

  assert doc_read.orientation(ctx, fakes.scope())
    == Ok(dynamic.string("orientation-doc"))
}

pub fn run_block_missing_doc_is_not_found_test() {
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(None))

  assert doc_read.run_block(ctx, fakes.scope(), "nope", "b1") == Error(NotFound)
}

pub fn run_block_missing_block_is_not_found_test() {
  let doc = docs_fixtures.doc(owner: "user-2")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs.stub(),
        get_current_by_slug: fn(_, _) { Some(doc) },
        find_chart_block: fn(_, _, _) { None },
      ),
    )

  assert doc_read.run_block(ctx, fakes.scope(), "notes", "b1")
    == Error(NotFound)
}

pub fn run_block_engine_error_is_query_failed_test() {
  let doc = docs_fixtures.doc(owner: "user-2")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs.stub(),
        get_current_by_slug: fn(_, _) { Some(doc) },
        find_chart_block: fn(_, _, _) { Some(dynamic.string("chart-block")) },
        run_chart: fn(_, _) { Error("relation does not exist") },
      ),
    )

  assert doc_read.run_block(ctx, fakes.scope(), "notes", "b1")
    == Error(Invalid("query_failed", "relation does not exist"))
}

pub fn run_block_returns_rows_test() {
  let doc = docs_fixtures.doc(owner: "user-2")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs.stub(),
        get_current_by_slug: fn(_, _) { Some(doc) },
        find_chart_block: fn(_, _, block_id) {
          assert block_id == "b1"
          Some(dynamic.string("chart-block"))
        },
        run_chart: fn(workspace_id, block) {
          assert workspace_id == "ws-1"
          assert block == dynamic.string("chart-block")
          Ok(dynamic.string("rows"))
        },
      ),
    )

  assert doc_read.run_block(ctx, fakes.scope(), "notes", "b1")
    == Ok(dynamic.string("rows"))
}
