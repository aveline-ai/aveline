//// Comments IO capabilities. Built for real in
//// lib/aveline/gleam/caps/comments.ex; keep the two in lockstep
//// (tag + field order). Mutation caps broadcast the same PubSub
//// message the legacy context did; activity events are the HANDLER's
//// job (decision logic) via record_event.

import aveline/comments/comment.{
  type Comment, type CommentView, type DocRef, type NewComment,
}
import aveline/comments/events.{type CommentEventAttrs}
import gleam/option.{type Option}

pub type CommentsCaps {
  CommentsCaps(
    /// Live (non-superseded, non-deleted) row for a base_comment_id.
    get_current_by_base: fn(String) -> Option(Comment),
    /// Latest non-superseded row, even if deleted (undelete path).
    get_latest_by_base: fn(String) -> Option(Comment),
    /// Rendered comment snapshot pinned to a doc-VERSION row id.
    /// Coarse by design: heavy DISTINCT-ON read + preloads.
    list_for_doc_version: fn(String) -> List(CommentView),
    /// Insert v1 + broadcast comment_created. Error(Nil) = changeset
    /// validation failed (product behavior: 422 validation_failed).
    insert: fn(NewComment) -> Result(Comment, Nil),
    /// New version row for (row_id, new_body): supersede + insert in one
    /// transaction, broadcast comment_updated, return the new version.
    edit_body: fn(String, String) -> Result(Comment, Nil),
    /// Set resolved flags on (row_id, resolver_id); broadcast + return.
    resolve: fn(String, String) -> Comment,
    /// Clear resolved flags on row_id; broadcast + return.
    unresolve: fn(String) -> Comment,
    /// Set deleted flags on (row_id, deleted_by_id); broadcast + return.
    soft_delete: fn(String, String) -> Comment,
    /// Clear deleted flags on row_id; broadcast + return.
    undelete: fn(String) -> Comment,
    /// Doc fields for event logging, by doc-version row id.
    doc_ref: fn(String) -> Option(DocRef),
    /// Record one comment activity event (has a data payload the shared
    /// events cap can't carry yet).
    record_event: fn(CommentEventAttrs) -> Nil,
  )
}

pub fn stub() -> CommentsCaps {
  CommentsCaps(
    get_current_by_base: fn(_) { panic as "stub comments.get_current_by_base" },
    get_latest_by_base: fn(_) { panic as "stub comments.get_latest_by_base" },
    list_for_doc_version: fn(_) { panic as "stub comments.list_for_doc_version" },
    insert: fn(_) { panic as "stub comments.insert" },
    edit_body: fn(_, _) { panic as "stub comments.edit_body" },
    resolve: fn(_, _) { panic as "stub comments.resolve" },
    unresolve: fn(_) { panic as "stub comments.unresolve" },
    soft_delete: fn(_, _) { panic as "stub comments.soft_delete" },
    undelete: fn(_) { panic as "stub comments.undelete" },
    doc_ref: fn(_) { panic as "stub comments.doc_ref" },
    record_event: fn(_) { panic as "stub comments.record_event" },
  )
}
