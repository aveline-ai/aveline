//// Pure tests for the comment activity-event decision logic — a
//// verbatim port of Aveline.Comments.record_comment_event/3, quirks
//// included.

import aveline/comments/comment.{Comment}
import aveline/comments/events.{
  CommentEventAttrs, Created, Deleted, EditVersion, NoData, ResolvedByDoc,
  Updated,
} as comment_events
import aveline/comments_fixtures
import aveline/core/events.{Agent, Human}
import gleam/option.{Some}

pub fn created_credits_the_author_test() {
  let c =
    Comment(..comments_fixtures.comment(author: "user-1"), actor_type: Agent)

  assert comment_events.attrs(Created, c, comments_fixtures.doc_ref())
    == CommentEventAttrs(
      workspace_id: "ws-1",
      actor: Some("user-1"),
      actor_type: Agent,
      action: "comment_created",
      target_id: "c-base-1",
      target_slug: "notes",
      target_label: "Notes",
      doc_base_id: "base-1",
      data: NoData,
    )
}

pub fn deleted_credits_deleted_by_as_human_test() {
  let c =
    Comment(
      ..comments_fixtures.comment(author: "user-1"),
      actor_type: Agent,
      deleted_at: Some("2026-01-02T00:00:00Z"),
      deleted_by_id: Some("user-9"),
    )

  let attrs = comment_events.attrs(Deleted, c, comments_fixtures.doc_ref())

  assert attrs.action == "comment_deleted"
  assert attrs.actor == Some("user-9")
  assert attrs.actor_type == Human
  assert attrs.data == NoData
}

pub fn resolved_v1_credits_resolver_with_doc_data_test() {
  let c =
    Comment(
      ..comments_fixtures.comment(author: "user-1"),
      actor_type: Agent,
      resolved_at: Some("2026-01-02T00:00:00Z"),
      resolved_by_id: Some("user-9"),
      resolved_by_doc_id: Some("doc-v4"),
    )

  let attrs = comment_events.attrs(Updated, c, comments_fixtures.doc_ref())

  assert attrs.action == "comment_resolved"
  assert attrs.actor == Some("user-9")
  assert attrs.actor_type == Human
  assert attrs.data == ResolvedByDoc(Some("doc-v4"))
}

pub fn updated_later_version_is_an_edit_even_when_resolved_test() {
  // Legacy quirk preserved: version > 1 always records comment_edited,
  // credited to the comment's author — even if the update was a
  // resolve.
  let c =
    Comment(
      ..comments_fixtures.comment(author: "user-1"),
      version_number: 2,
      actor_type: Agent,
      resolved_at: Some("2026-01-02T00:00:00Z"),
      resolved_by_id: Some("user-9"),
    )

  let attrs = comment_events.attrs(Updated, c, comments_fixtures.doc_ref())

  assert attrs.action == "comment_edited"
  assert attrs.actor == Some("user-1")
  assert attrs.actor_type == Agent
  assert attrs.data == EditVersion(2)
}

pub fn updated_unresolved_v1_is_an_unresolve_test() {
  let attrs =
    comment_events.attrs(
      Updated,
      comments_fixtures.comment(author: "user-1"),
      comments_fixtures.doc_ref(),
    )

  assert attrs.action == "comment_unresolved"
  assert attrs.actor == Some("user-1")
  assert attrs.actor_type == Human
  assert attrs.data == NoData
}
