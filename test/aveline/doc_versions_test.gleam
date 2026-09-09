import aveline/caps/docs.{DocsCaps}
import aveline/core/ctx.{Ctx}
import aveline/core/error.{NotFound}
import aveline/docs_fixtures
import aveline/fakes
import aveline/handlers/doc_versions.{VersionList}
import gleam/dynamic
import gleam/option.{None, Some}

pub fn index_missing_doc_is_not_found_test() {
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(None))

  assert doc_versions.index(ctx, fakes.scope(), "nope") == Error(NotFound)
}

pub fn index_lists_versions_with_current_pointer_test() {
  let doc = docs_fixtures.doc(owner: "user-2")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs.stub(),
        get_current_by_slug: fn(_, _) { Some(doc) },
        list_versions: fn(base_doc_id) {
          assert base_doc_id == "base-1"
          dynamic.string("versions")
        },
      ),
    )

  assert doc_versions.index(ctx, fakes.scope(), "notes")
    == Ok(VersionList(versions: dynamic.string("versions"), current_version: 3))
}

// Parity with the legacy endpoint: listing versions never applied the
// private-doc readability rule — the doc only has to exist.
pub fn index_skips_the_readability_check_test() {
  let doc = docs_fixtures.private_doc(owner: "user-2")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs.stub(),
        get_current_by_slug: fn(_, _) { Some(doc) },
        list_versions: fn(_) { dynamic.string("versions") },
      ),
    )

  assert doc_versions.index(ctx, fakes.scope(), "notes")
    == Ok(VersionList(versions: dynamic.string("versions"), current_version: 3))
}

pub fn show_private_doc_hidden_from_non_shared_member_test() {
  let doc = docs_fixtures.private_doc(owner: "user-2")
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(Some(doc)))

  assert doc_versions.show(ctx, fakes.scope(), "notes", "1") == Error(NotFound)
}

pub fn show_unparseable_version_is_not_found_test() {
  let doc = docs_fixtures.doc(owner: "user-2")
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(Some(doc)))

  assert doc_versions.show(ctx, fakes.scope(), "notes", "abc")
    == Error(NotFound)
}

pub fn show_missing_version_is_not_found_test() {
  let doc = docs_fixtures.doc(owner: "user-2")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs.stub(),
        get_current_by_slug: fn(_, _) { Some(doc) },
        read_version_full: fn(_, _, _, _) { None },
      ),
    )

  assert doc_versions.show(ctx, fakes.scope(), "notes", "99") == Error(NotFound)
}

pub fn show_returns_the_version_body_test() {
  let doc = docs_fixtures.doc(owner: "user-2")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs.stub(),
        get_current_by_slug: fn(_, _) { Some(doc) },
        read_version_full: fn(workspace_id, base_doc_id, version, viewer) {
          assert workspace_id == "ws-1"
          assert base_doc_id == "base-1"
          assert version == 2
          assert viewer == "user-1"
          Some(dynamic.string("v2"))
        },
      ),
    )

  assert doc_versions.show(ctx, fakes.scope(), "notes", "2")
    == Ok(dynamic.string("v2"))
}
