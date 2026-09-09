//// Pure handler tests for the comment lifecycle endpoints. Stubs panic
//// on untouched IO, so each test also proves which caps did NOT run.

import aveline/caps/comments.{CommentsCaps} as comments_caps
import aveline/comments/comment.{type NewComment, Comment, NewComment}
import aveline/comments/events.{type CommentEventAttrs} as _comment_events
import aveline/comments_fixtures
import aveline/core/ctx.{Ctx}
import aveline/core/error.{Forbidden, Invalid, NotFound}
import aveline/core/events.{Agent, Human}
import aveline/docs/doc_meta.{DocMeta, Private}
import aveline/docs_fixtures
import aveline/fakes
import aveline/handlers/comments.{CreateRequest} as handlers
import gleam/option.{None, Some}
import gleam/string

const forbidden = Forbidden("You don't have access to this resource.")

const validation_failed = Invalid("validation_failed", "Validation failed.")

fn create_request() -> handlers.CreateRequest {
  CreateRequest(
    body: Some("I have a question."),
    block_id: None,
    parent_comment_id: None,
    actor: None,
  )
}

/// Ctx with a readable workspace-visible doc owned by someone else.
fn doc_ctx(caps: comments_caps.CommentsCaps) -> ctx.Ctx {
  Ctx(
    ..fakes.ctx(),
    docs: docs_fixtures.docs_returning(Some(docs_fixtures.doc(owner: "user-2"))),
    comments: caps,
  )
}

/// Caps for happy-path writes: doc_ref resolves and record_event
/// asserts the recorded action.
fn logging_caps(expected_action: String) -> comments_caps.CommentsCaps {
  CommentsCaps(
    ..comments_caps.stub(),
    doc_ref: fn(doc_id) {
      assert doc_id == "doc-v3"
      Some(comments_fixtures.doc_ref())
    },
    record_event: fn(attrs: CommentEventAttrs) {
      assert attrs.action == expected_action
      Nil
    },
  )
}

// ===== index =====

pub fn index_missing_doc_is_not_found_test() {
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(None))

  assert handlers.index(ctx, fakes.scope(), "nope") == Error(NotFound)
}

pub fn index_private_doc_hidden_from_non_shared_member_test() {
  let doc = DocMeta(..docs_fixtures.doc(owner: "user-2"), visibility: Private)
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(Some(doc)))

  assert handlers.index(ctx, fakes.scope(), "notes") == Error(NotFound)
}

pub fn index_returns_the_doc_version_snapshot_test() {
  let ctx =
    doc_ctx(
      CommentsCaps(..comments_caps.stub(), list_for_doc_version: fn(doc_id) {
        assert doc_id == "doc-v3"
        [comments_fixtures.view()]
      }),
    )

  assert handlers.index(ctx, fakes.scope(), "notes")
    == Ok([comments_fixtures.view()])
}

// ===== create =====

pub fn create_missing_doc_is_not_found_test() {
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(None))

  assert handlers.create(ctx, fakes.scope(), "nope", create_request())
    == Error(NotFound)
}

pub fn create_private_doc_hidden_test() {
  let doc = DocMeta(..docs_fixtures.doc(owner: "user-2"), visibility: Private)
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(Some(doc)))

  assert handlers.create(ctx, fakes.scope(), "notes", create_request())
    == Error(NotFound)
}

pub fn create_missing_body_fails_validation_test() {
  let ctx = doc_ctx(comments_caps.stub())
  let request = CreateRequest(..create_request(), body: None)

  assert handlers.create(ctx, fakes.scope(), "notes", request)
    == Error(validation_failed)
}

pub fn create_empty_body_fails_validation_test() {
  let ctx = doc_ctx(comments_caps.stub())
  let request = CreateRequest(..create_request(), body: Some(""))

  assert handlers.create(ctx, fakes.scope(), "notes", request)
    == Error(validation_failed)
}

pub fn create_overlong_body_fails_validation_test() {
  let ctx = doc_ctx(comments_caps.stub())
  let request =
    CreateRequest(..create_request(), body: Some(string.repeat("x", 10_001)))

  assert handlers.create(ctx, fakes.scope(), "notes", request)
    == Error(validation_failed)
}

pub fn create_unknown_actor_fails_validation_test() {
  let ctx = doc_ctx(comments_caps.stub())
  let request = CreateRequest(..create_request(), actor: Some("robot"))

  assert handlers.create(ctx, fakes.scope(), "notes", request)
    == Error(validation_failed)
}

pub fn create_inserts_v1_defaulting_to_agent_test() {
  let ctx =
    doc_ctx(
      CommentsCaps(
        ..logging_caps("comment_created"),
        insert: fn(new: NewComment) {
          assert new
            == NewComment(
              doc_id: "doc-v3",
              block_id: None,
              parent_comment_id: None,
              body: string.repeat("x", 10_000),
              actor_user_id: "user-1",
              actor_type: Agent,
            )
          Ok(
            Comment(
              ..comments_fixtures.comment(author: "user-1"),
              actor_type: Agent,
            ),
          )
        },
      ),
    )

  let request =
    CreateRequest(..create_request(), body: Some(string.repeat("x", 10_000)))

  assert handlers.create(ctx, fakes.scope(), "notes", request) == Ok("c-base-1")
}

pub fn create_human_actor_is_kept_test() {
  let ctx =
    doc_ctx(
      CommentsCaps(
        ..logging_caps("comment_created"),
        insert: fn(new: NewComment) {
          assert new.actor_type == Human
          Ok(comments_fixtures.comment(author: "user-1"))
        },
      ),
    )

  let request = CreateRequest(..create_request(), actor: Some("human"))

  assert handlers.create(ctx, fakes.scope(), "notes", request) == Ok("c-base-1")
}

pub fn create_explicit_block_wins_without_parent_lookup_test() {
  // get_current_by_base stays a panicking stub: passing block_id must
  // not trigger the parent-inheritance read.
  let ctx =
    doc_ctx(
      CommentsCaps(
        ..logging_caps("comment_created"),
        insert: fn(new: NewComment) {
          assert new.block_id == Some("b_explicit")
          assert new.parent_comment_id == Some("c-parent")
          Ok(comments_fixtures.comment(author: "user-1"))
        },
      ),
    )

  let request =
    CreateRequest(
      ..create_request(),
      block_id: Some("b_explicit"),
      parent_comment_id: Some("c-parent"),
    )

  assert handlers.create(ctx, fakes.scope(), "notes", request) == Ok("c-base-1")
}

pub fn create_reply_inherits_parent_block_test() {
  let parent =
    Comment(
      ..comments_fixtures.comment(author: "user-2"),
      base_comment_id: "c-parent",
      block_id: Some("b_parent"),
    )

  let ctx =
    doc_ctx(
      CommentsCaps(
        ..logging_caps("comment_created"),
        get_current_by_base: fn(base_id) {
          assert base_id == "c-parent"
          Some(parent)
        },
        insert: fn(new: NewComment) {
          assert new.block_id == Some("b_parent")
          Ok(comments_fixtures.comment(author: "user-1"))
        },
      ),
    )

  let request =
    CreateRequest(..create_request(), parent_comment_id: Some("c-parent"))

  assert handlers.create(ctx, fakes.scope(), "notes", request) == Ok("c-base-1")
}

pub fn create_reply_to_missing_parent_gets_no_anchor_test() {
  let ctx =
    doc_ctx(
      CommentsCaps(
        ..logging_caps("comment_created"),
        get_current_by_base: fn(_) { None },
        insert: fn(new: NewComment) {
          assert new.block_id == None
          Ok(comments_fixtures.comment(author: "user-1"))
        },
      ),
    )

  let request =
    CreateRequest(..create_request(), parent_comment_id: Some("c-gone"))

  assert handlers.create(ctx, fakes.scope(), "notes", request) == Ok("c-base-1")
}

pub fn create_insert_rejection_fails_validation_test() {
  let ctx =
    doc_ctx(CommentsCaps(..comments_caps.stub(), insert: fn(_) { Error(Nil) }))

  assert handlers.create(ctx, fakes.scope(), "notes", create_request())
    == Error(validation_failed)
}

pub fn create_without_doc_ref_skips_the_event_test() {
  let ctx =
    doc_ctx(
      CommentsCaps(
        ..comments_caps.stub(),
        insert: fn(_) { Ok(comments_fixtures.comment(author: "user-1")) },
        doc_ref: fn(_) { None },
      ),
    )

  assert handlers.create(ctx, fakes.scope(), "notes", create_request())
    == Ok("c-base-1")
}

// ===== update =====

pub fn update_missing_comment_is_not_found_test() {
  let ctx = current_returning(None)

  assert handlers.update(ctx, fakes.scope(), "c-base-1", Some("new"))
    == Error(NotFound)
}

pub fn update_non_author_is_forbidden_test() {
  let ctx = current_returning(Some(comments_fixtures.comment(author: "user-2")))

  assert handlers.update(ctx, fakes.scope(), "c-base-1", Some("new"))
    == Error(forbidden)
}

pub fn update_missing_body_fails_validation_test() {
  let ctx = current_returning(Some(comments_fixtures.comment(author: "user-1")))

  assert handlers.update(ctx, fakes.scope(), "c-base-1", None)
    == Error(validation_failed)
}

pub fn update_edits_and_logs_the_new_version_test() {
  let new_version =
    Comment(
      ..comments_fixtures.comment(author: "user-1"),
      id: "c-row-2",
      version_number: 2,
      body: "Updated text",
    )

  let ctx =
    Ctx(
      ..fakes.ctx(),
      comments: CommentsCaps(
        ..logging_caps("comment_edited"),
        get_current_by_base: fn(_) {
          Some(comments_fixtures.comment(author: "user-1"))
        },
        edit_body: fn(row_id, body) {
          assert row_id == "c-row-1"
          assert body == "Updated text"
          Ok(new_version)
        },
      ),
    )

  assert handlers.update(ctx, fakes.scope(), "c-base-1", Some("Updated text"))
    == Ok(Nil)
}

pub fn update_edit_rejection_fails_validation_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      comments: CommentsCaps(
        ..comments_caps.stub(),
        get_current_by_base: fn(_) {
          Some(comments_fixtures.comment(author: "user-1"))
        },
        edit_body: fn(_, _) { Error(Nil) },
      ),
    )

  assert handlers.update(ctx, fakes.scope(), "c-base-1", Some("new"))
    == Error(validation_failed)
}

// ===== delete =====

pub fn delete_missing_comment_is_not_found_test() {
  let ctx = current_returning(None)

  assert handlers.delete(ctx, fakes.scope(), "c-base-1") == Error(NotFound)
}

pub fn delete_non_author_is_forbidden_test() {
  let ctx = current_returning(Some(comments_fixtures.comment(author: "user-2")))

  assert handlers.delete(ctx, fakes.scope(), "c-base-1") == Error(forbidden)
}

pub fn delete_soft_deletes_and_logs_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      comments: CommentsCaps(
        ..logging_caps("comment_deleted"),
        get_current_by_base: fn(_) {
          Some(comments_fixtures.comment(author: "user-1"))
        },
        soft_delete: fn(row_id, deleted_by) {
          assert row_id == "c-row-1"
          assert deleted_by == "user-1"
          Comment(
            ..comments_fixtures.comment(author: "user-1"),
            deleted_at: Some("2026-01-02T00:00:00Z"),
            deleted_by_id: Some("user-1"),
          )
        },
      ),
    )

  assert handlers.delete(ctx, fakes.scope(), "c-base-1") == Ok(Nil)
}

// ===== undelete =====

pub fn undelete_missing_comment_is_not_found_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      comments: CommentsCaps(..comments_caps.stub(), get_latest_by_base: fn(_) {
        None
      }),
    )

  assert handlers.undelete(ctx, fakes.scope(), "c-base-1") == Error(NotFound)
}

pub fn undelete_non_author_is_forbidden_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      comments: CommentsCaps(..comments_caps.stub(), get_latest_by_base: fn(_) {
        Some(comments_fixtures.comment(author: "user-2"))
      }),
    )

  assert handlers.undelete(ctx, fakes.scope(), "c-base-1") == Error(forbidden)
}

pub fn undelete_restores_and_logs_test() {
  let deleted =
    Comment(
      ..comments_fixtures.comment(author: "user-1"),
      deleted_at: Some("2026-01-02T00:00:00Z"),
      deleted_by_id: Some("user-1"),
    )

  // Legacy quirk preserved: undeleting an unresolved v1 comment records
  // a "comment_unresolved" event (the Updated funnel).
  let ctx =
    Ctx(
      ..fakes.ctx(),
      comments: CommentsCaps(
        ..logging_caps("comment_unresolved"),
        get_latest_by_base: fn(_) { Some(deleted) },
        undelete: fn(row_id) {
          assert row_id == "c-row-1"
          comments_fixtures.comment(author: "user-1")
        },
      ),
    )

  assert handlers.undelete(ctx, fakes.scope(), "c-base-1") == Ok(Nil)
}

// ===== resolve / unresolve =====

pub fn resolve_missing_comment_is_not_found_test() {
  let ctx = current_returning(None)

  assert handlers.resolve(ctx, fakes.scope(), "c-base-1") == Error(NotFound)
}

pub fn resolve_is_not_author_gated_and_logs_test() {
  // Authored by user-2; scope actor user-1 resolves it anyway.
  let ctx =
    Ctx(
      ..fakes.ctx(),
      comments: CommentsCaps(
        ..logging_caps("comment_resolved"),
        get_current_by_base: fn(_) {
          Some(comments_fixtures.comment(author: "user-2"))
        },
        resolve: fn(row_id, resolver) {
          assert row_id == "c-row-1"
          assert resolver == "user-1"
          Comment(
            ..comments_fixtures.comment(author: "user-2"),
            resolved_at: Some("2026-01-02T00:00:00Z"),
            resolved_by_id: Some("user-1"),
          )
        },
      ),
    )

  assert handlers.resolve(ctx, fakes.scope(), "c-base-1") == Ok(Nil)
}

pub fn unresolve_missing_comment_is_not_found_test() {
  let ctx = current_returning(None)

  assert handlers.unresolve(ctx, fakes.scope(), "c-base-1") == Error(NotFound)
}

pub fn unresolve_clears_and_logs_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      comments: CommentsCaps(
        ..logging_caps("comment_unresolved"),
        get_current_by_base: fn(_) {
          Some(
            Comment(
              ..comments_fixtures.comment(author: "user-2"),
              resolved_at: Some("2026-01-02T00:00:00Z"),
              resolved_by_id: Some("user-1"),
            ),
          )
        },
        unresolve: fn(row_id) {
          assert row_id == "c-row-1"
          comments_fixtures.comment(author: "user-2")
        },
      ),
    )

  assert handlers.unresolve(ctx, fakes.scope(), "c-base-1") == Ok(Nil)
}

// ===== helpers =====

fn current_returning(current) -> ctx.Ctx {
  Ctx(
    ..fakes.ctx(),
    comments: CommentsCaps(..comments_caps.stub(), get_current_by_base: fn(_) {
      current
    }),
  )
}
