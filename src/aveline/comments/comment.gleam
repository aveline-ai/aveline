//// The comment fields handlers make decisions on. Comments mirror the
//// docs versioning model: `base_comment_id` is the stable logical id of
//// a thread node, `id` the per-version row id. The CURRENT row of a
//// base is the one that is neither superseded nor deleted.

import aveline/core/events.{type ActorType}
import gleam/option.{type Option}

pub type Comment {
  Comment(
    /// Row id of THIS version.
    id: String,
    /// Stable logical id — what the API exposes and references.
    base_comment_id: String,
    version_number: Int,
    /// Doc-VERSION row id the comment is pinned to.
    doc_id: String,
    block_id: Option(String),
    /// The parent's base_comment_id (no FK; nil for top-level).
    parent_comment_id: Option(String),
    body: String,
    actor_user_id: String,
    actor_type: ActorType,
    /// Timestamps are ISO8601 display strings at this boundary.
    resolved_at: Option(String),
    resolved_by_id: Option(String),
    resolved_by_doc_id: Option(String),
    edited_at: Option(String),
    deleted_at: Option(String),
    deleted_by_id: Option(String),
  )
}

/// Attributes for inserting a v1 comment row. The cap generates the id
/// and sets base_comment_id == id, version_number == 1.
pub type NewComment {
  NewComment(
    doc_id: String,
    block_id: Option(String),
    parent_comment_id: Option(String),
    body: String,
    actor_user_id: String,
    actor_type: ActorType,
  )
}

/// The doc fields comment event logging needs, looked up from the
/// doc-version row a comment is pinned to.
pub type DocRef {
  DocRef(base_doc_id: String, workspace_id: String, slug: String, title: String)
}

/// Inlined user reference, as the API renders it.
pub type UserRef {
  UserRef(
    id: String,
    username: String,
    display_name: Option(String),
    email: Option(String),
  )
}

/// One rendered comment for GET /docs/:slug/comments — the exact field
/// set of the legacy Views.comment/1 JSON shape. Built by the coarse
/// list cap (heavy read: DISTINCT-ON snapshot query + preloads).
pub type CommentView {
  CommentView(
    /// base_comment_id — the id agents reference.
    id: String,
    /// Row id of this version. Mostly internal.
    version_id: String,
    version_number: Int,
    doc_id: String,
    block_id: Option(String),
    parent_comment_id: Option(String),
    body: String,
    /// Raw "human" | "agent" string, echoed as-is.
    actor_type: String,
    actor_user: Option(UserRef),
    resolved_at: Option(String),
    resolved_by: Option(UserRef),
    resolved_in_version: Option(Int),
    edited_at: Option(String),
    deleted_at: Option(String),
    deleted_by: Option(UserRef),
    created_at: String,
  )
}
