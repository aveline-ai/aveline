import aveline/caps/docs.{DocsCaps}
import aveline/core/ctx.{Ctx}
import aveline/core/error.{Forbidden, Invalid, NotFound}
import aveline/docs/doc_error.{
  Api, NotUserDeleted, OrientationUndeletable, Passthrough,
}
import aveline/docs/doc_meta.{DocMeta, Viewer}
import aveline/docs/doc_writes.{
  BlockInvalid, CreateAttrs, DocPointer, OtherFailure, RestoreNotFound,
  RestoreNotUserDeleted, RestoredDoc,
}
import aveline/docs_fixtures
import aveline/fakes
import aveline/handlers/doc_write.{CreateRequest, UpdateRequest}
import gleam/dynamic
import gleam/option.{None, Some}

const hint = " Run `aveline contract` for every block type and op with a valid example."

fn pointer() -> doc_writes.DocPointer {
  DocPointer(
    slug: "notes",
    doc_id: "base-1",
    version_id: "v-9",
    version_number: 4,
  )
}

// ===== create =====

fn create_request() -> doc_write.CreateRequest {
  CreateRequest(
    title: Some("Notes"),
    slug: None,
    summary: None,
    tags: dynamic.list([]),
    blocks: dynamic.list([]),
    intent: None,
    actor: None,
    visibility: None,
  )
}

pub fn create_defaults_to_agent_and_private_test() {
  let expected =
    CreateAttrs(
      workspace_id: "ws-1",
      owner_id: "user-1",
      actor_user_id: "user-1",
      actor_type: "agent",
      title: Some("Notes"),
      slug: None,
      summary: None,
      intent: None,
      visibility: "private",
    )

  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(..docs.stub(), create_doc: fn(attrs, tags, blocks) {
        assert attrs == expected
        assert tags == dynamic.list([])
        assert blocks == dynamic.list([])
        Ok(pointer())
      }),
    )

  assert doc_write.create(ctx, fakes.scope(), create_request()) == Ok(pointer())
}

pub fn create_honors_explicit_actor_and_visibility_test() {
  let req =
    CreateRequest(
      ..create_request(),
      actor: Some("human"),
      visibility: Some("workspace"),
    )

  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs.stub(),
        create_doc: fn(attrs: doc_writes.CreateAttrs, _, _) {
          assert attrs.actor_type == "human"
          assert attrs.visibility == "workspace"
          Ok(pointer())
        },
      ),
    )

  assert doc_write.create(ctx, fakes.scope(), req) == Ok(pointer())
}

pub fn create_block_failure_gets_contract_hint_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(..docs.stub(), create_doc: fn(_, _, _) {
        Error(BlockInvalid("block 1: unknown type"))
      }),
    )

  assert doc_write.create(ctx, fakes.scope(), create_request())
    == Error(Api(Invalid("validation_failed", "block 1: unknown type" <> hint)))
}

pub fn create_other_failure_passes_through_test() {
  let reason = dynamic.string("raw-elixir-error")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(..docs.stub(), create_doc: fn(_, _, _) {
        Error(OtherFailure(reason))
      }),
    )

  assert doc_write.create(ctx, fakes.scope(), create_request())
    == Error(Passthrough(reason))
}

// ===== update =====

fn update_request() -> doc_write.UpdateRequest {
  UpdateRequest(
    blocks: None,
    ops_is_list: False,
    ops: dynamic.list([]),
    title: None,
    summary: None,
    tags: None,
    intent: None,
    actor: None,
    resolves: dynamic.list([]),
    dispositions: dynamic.list([]),
  )
}

pub fn update_missing_doc_is_not_found_test() {
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(None))

  assert doc_write.update(ctx, fakes.scope(), "nope", update_request())
    == Error(Api(NotFound))
}

pub fn update_viewer_share_is_forbidden_test() {
  let doc = docs_fixtures.private_doc(owner: "user-2")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs.stub(),
        get_current_by_slug: fn(_, _) { Some(doc) },
        share_role: fn(_, _) { Some(Viewer) },
      ),
    )

  assert doc_write.update(ctx, fakes.scope(), "notes", update_request())
    == Error(
      Api(Forbidden(
        "You have viewer access to this doc; editing needs an editor share or ownership.",
      )),
    )
}

pub fn update_rejects_blocks_and_ops_together_test() {
  let doc = docs_fixtures.doc(owner: "user-1")
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(Some(doc)))
  let req =
    UpdateRequest(
      ..update_request(),
      blocks: Some(dynamic.list([])),
      ops_is_list: True,
    )

  assert doc_write.update(ctx, fakes.scope(), "notes", req)
    == Error(
      Api(Invalid(
        "bad_request",
        "send either blocks (full replace) or operations (surgical), not both",
      )),
    )
}

pub fn update_blocks_take_the_replace_path_test() {
  let doc = docs_fixtures.doc(owner: "user-1")
  let blocks = dynamic.string("blocks-payload")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs.stub(),
        get_current_by_slug: fn(_, _) { Some(doc) },
        replace_blocks: fn(
          workspace_id,
          slug,
          payload,
          attrs: doc_writes.UpdateAttrs,
        ) {
          assert workspace_id == "ws-1"
          assert slug == "notes"
          assert payload == blocks
          assert attrs.actor_type == "agent"
          assert attrs.actor_user_id == "user-1"
          Ok(pointer())
        },
      ),
    )
  let req = UpdateRequest(..update_request(), blocks: Some(blocks))

  assert doc_write.update(ctx, fakes.scope(), "notes", req) == Ok(pointer())
}

pub fn update_without_blocks_takes_the_ops_path_test() {
  let doc = docs_fixtures.doc(owner: "user-1")
  let ops = dynamic.string("ops-payload")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs.stub(),
        get_current_by_slug: fn(_, _) { Some(doc) },
        apply_ops: fn(_, slug, payload, attrs: doc_writes.UpdateAttrs) {
          assert slug == "notes"
          assert payload == ops
          assert attrs.title == Some("Renamed")
          Ok(pointer())
        },
      ),
    )
  let req =
    UpdateRequest(
      ..update_request(),
      ops_is_list: True,
      ops: ops,
      title: Some("Renamed"),
    )

  assert doc_write.update(ctx, fakes.scope(), "notes", req) == Ok(pointer())
}

pub fn update_block_failure_gets_contract_hint_test() {
  let doc = docs_fixtures.doc(owner: "user-1")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs.stub(),
        get_current_by_slug: fn(_, _) { Some(doc) },
        apply_ops: fn(_, _, _, _) { Error(BlockInvalid("bad op")) },
      ),
    )

  assert doc_write.update(ctx, fakes.scope(), "notes", update_request())
    == Error(Api(Invalid("validation_failed", "bad op" <> hint)))
}

// ===== delete =====

pub fn delete_orientation_doc_is_rejected_test() {
  let doc = DocMeta(..docs_fixtures.doc(owner: "user-1"), orientation: True)
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(Some(doc)))

  assert doc_write.delete(ctx, fakes.scope(), "notes")
    == Error(OrientationUndeletable)
}

pub fn delete_viewer_share_is_forbidden_test() {
  let doc = docs_fixtures.private_doc(owner: "user-2")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs.stub(),
        get_current_by_slug: fn(_, _) { Some(doc) },
        share_role: fn(_, _) { Some(Viewer) },
      ),
    )

  assert doc_write.delete(ctx, fakes.scope(), "notes")
    == Error(
      Api(Forbidden(
        "You have viewer access to this doc; editing needs an editor share or ownership.",
      )),
    )
}

pub fn delete_soft_deletes_and_succeeds_test() {
  let doc = docs_fixtures.doc(owner: "user-1")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs.stub(),
        get_current_by_slug: fn(_, _) { Some(doc) },
        soft_delete: fn(workspace_id, slug, deleted_by) {
          assert workspace_id == "ws-1"
          assert slug == "notes"
          assert deleted_by == "user-1"
          Nil
        },
      ),
    )

  assert doc_write.delete(ctx, fakes.scope(), "notes") == Ok(Nil)
}

// ===== restore =====

pub fn restore_missing_doc_is_not_found_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(..docs.stub(), latest_version_by_slug: fn(_, _) { None }),
    )

  assert doc_write.restore(ctx, fakes.scope(), "nope") == Error(Api(NotFound))
}

pub fn restore_deleted_private_doc_invisible_to_non_owner_test() {
  let doc = docs_fixtures.private_doc(owner: "user-2")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(..docs.stub(), latest_version_by_slug: fn(_, _) {
        Some(doc)
      }),
    )

  assert doc_write.restore(ctx, fakes.scope(), "notes") == Error(Api(NotFound))
}

pub fn restore_private_doc_by_owner_succeeds_test() {
  let doc = docs_fixtures.private_doc(owner: "user-1")
  let restored = RestoredDoc(slug: "notes", doc_id: "base-1", version_number: 3)
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs.stub(),
        latest_version_by_slug: fn(_, _) { Some(doc) },
        restore: fn(base_doc_id) {
          assert base_doc_id == "base-1"
          Ok(restored)
        },
      ),
    )

  assert doc_write.restore(ctx, fakes.scope(), "notes") == Ok(restored)
}

pub fn restore_live_doc_is_not_user_deleted_test() {
  let doc = docs_fixtures.doc(owner: "user-2")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs.stub(),
        latest_version_by_slug: fn(_, _) { Some(doc) },
        restore: fn(_) { Error(RestoreNotUserDeleted) },
      ),
    )

  assert doc_write.restore(ctx, fakes.scope(), "notes") == Error(NotUserDeleted)
}

pub fn restore_vanished_base_is_not_found_test() {
  let doc = docs_fixtures.doc(owner: "user-2")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs.stub(),
        latest_version_by_slug: fn(_, _) { Some(doc) },
        restore: fn(_) { Error(RestoreNotFound) },
      ),
    )

  assert doc_write.restore(ctx, fakes.scope(), "notes") == Error(Api(NotFound))
}
