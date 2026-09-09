//// Activity-event decision logic for comment mutations — a pure port of
//// Aveline.Comments.record_comment_event/3. Comment events carry a data
//// payload (doc_base_id + action-specific keys) that the shared
//// core EventAttrs can't express yet, so they go through the comments
//// caps' own record_event.

import aveline/comments/comment.{type Comment, type DocRef}
import aveline/core/events.{type ActorType, Human}
import gleam/option.{type Option, None, Some}

/// Mirrors the legacy broadcast tags: :comment_created /
/// :comment_updated / :comment_deleted. Which ACTION an Updated event
/// records depends on the resulting row (see attrs) — resolve,
/// unresolve, edit and undelete all funnel through Updated, exactly as
/// before the port.
pub type CommentEventKind {
  Created
  Updated
  Deleted
}

/// Action-specific event data. The cap merges in "doc_base_id".
pub type CommentEventData {
  NoData
  /// Resolve of a v1 comment: {"resolved_by_doc_id" => ...}.
  ResolvedByDoc(resolved_by_doc_id: Option(String))
  /// Edit (version > 1): {"version_number" => n}.
  EditVersion(version_number: Int)
}

pub type CommentEventAttrs {
  CommentEventAttrs(
    workspace_id: String,
    actor: Option(String),
    actor_type: ActorType,
    action: String,
    /// base_comment_id.
    target_id: String,
    target_slug: String,
    target_label: String,
    doc_base_id: String,
    data: CommentEventData,
  )
}

/// Build the event for a mutation's RESULTING row. Ports the two legacy
/// cond blocks verbatim, quirks included: an Updated event on a
/// resolved v1 row is credited to the resolver as "human"; version > 1
/// always records "comment_edited" (even when the update was a
/// resolve/unresolve/undelete); deletes are credited to deleted_by as
/// "human".
pub fn attrs(
  kind: CommentEventKind,
  c: Comment,
  ref: DocRef,
) -> CommentEventAttrs {
  let #(actor, actor_type, data) = case kind {
    Created -> #(Some(c.actor_user_id), c.actor_type, NoData)
    Deleted -> #(c.deleted_by_id, Human, NoData)
    Updated ->
      case c.resolved_at, c.version_number {
        Some(_), 1 -> #(
          c.resolved_by_id,
          Human,
          ResolvedByDoc(c.resolved_by_doc_id),
        )
        _, v if v > 1 -> #(Some(c.actor_user_id), c.actor_type, EditVersion(v))
        _, _ -> #(Some(c.actor_user_id), c.actor_type, NoData)
      }
  }

  let action = case kind {
    Created -> "comment_created"
    Deleted -> "comment_deleted"
    Updated ->
      case c.version_number > 1, c.resolved_at {
        True, _ -> "comment_edited"
        False, Some(_) -> "comment_resolved"
        False, None -> "comment_unresolved"
      }
  }

  CommentEventAttrs(
    workspace_id: ref.workspace_id,
    actor: actor,
    actor_type: actor_type,
    action: action,
    target_id: c.base_comment_id,
    target_slug: ref.slug,
    target_label: ref.title,
    doc_base_id: ref.base_doc_id,
    data: data,
  )
}
