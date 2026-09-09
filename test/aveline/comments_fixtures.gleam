//// Comments-domain test fixtures.

import aveline/comments/comment.{
  type Comment, type CommentView, type DocRef, Comment, CommentView, DocRef,
  UserRef,
}
import aveline/core/events.{Human}
import gleam/option.{None, Some}

/// A live v1 top-level comment authored by `author`, pinned to doc
/// version "doc-v3" (the docs_fixtures doc).
pub fn comment(author author: String) -> Comment {
  Comment(
    id: "c-row-1",
    base_comment_id: "c-base-1",
    version_number: 1,
    doc_id: "doc-v3",
    block_id: None,
    parent_comment_id: None,
    body: "I have a question.",
    actor_user_id: author,
    actor_type: Human,
    resolved_at: None,
    resolved_by_id: None,
    resolved_by_doc_id: None,
    edited_at: None,
    deleted_at: None,
    deleted_by_id: None,
  )
}

pub fn doc_ref() -> DocRef {
  DocRef(
    base_doc_id: "base-1",
    workspace_id: "ws-1",
    slug: "notes",
    title: "Notes",
  )
}

pub fn view() -> CommentView {
  CommentView(
    id: "c-base-1",
    version_id: "c-row-1",
    version_number: 1,
    doc_id: "doc-v3",
    block_id: None,
    parent_comment_id: None,
    body: "I have a question.",
    actor_type: "human",
    actor_user: Some(UserRef(
      id: "user-1",
      username: "arie",
      display_name: None,
      email: None,
    )),
    resolved_at: None,
    resolved_by: None,
    resolved_in_version: None,
    edited_at: None,
    deleted_at: None,
    deleted_by: None,
    created_at: "2026-01-01T00:00:00Z",
  )
}
