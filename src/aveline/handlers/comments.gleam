//// Comment lifecycle endpoints. Ports AvelineWeb.Api.CommentController
//// (index/create/update/delete/undelete/resolve/unresolve) plus the
//// decision logic of the Aveline.Comments context functions it called.
////
//// IDs in requests are always the LOGICAL base_comment_id. Reads and
//// creates ride doc READ access (viewer shares can comment; unreadable
//// doc = NotFound). Edit/delete/undelete are author-only. Resolve and
//// unresolve are open to any authenticated workspace actor — exactly
//// as before the port.

import aveline/comments/comment.{type Comment, type CommentView, NewComment}
import aveline/comments/events as comment_events
import aveline/core/ctx.{type Ctx}
import aveline/core/error.{type ApiError, Forbidden, Invalid, NotFound}
import aveline/core/events.{type ActorType, Agent, Human}
import aveline/core/scope.{type Scope}
import aveline/docs/access
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// Body params for POST /docs/:doc_slug/comments. All fields optional
/// at the boundary — required-ness is validated here so missing/invalid
/// input surfaces as the same 422 validation_failed it always did.
pub type CreateRequest {
  CreateRequest(
    body: Option(String),
    block_id: Option(String),
    parent_comment_id: Option(String),
    /// "human" | "agent"; defaults to "agent" for API callers.
    actor: Option(String),
  )
}

// ===== Reads =====

pub fn index(
  ctx: Ctx,
  scope: Scope,
  doc_slug: String,
) -> Result(List(CommentView), ApiError) {
  use doc <- result.try(access.fetch_readable(ctx, scope, doc_slug))
  Ok(ctx.comments.list_for_doc_version(doc.id))
}

// ===== Writes =====

/// Post a new comment; echoes the new base_comment_id. A reply inherits
/// the parent's block anchor when block_id isn't passed, so threads
/// stay attached to their source block.
pub fn create(
  ctx: Ctx,
  scope: Scope,
  doc_slug: String,
  request: CreateRequest,
) -> Result(String, ApiError) {
  use doc <- result.try(access.fetch_readable(ctx, scope, doc_slug))

  let block_id = case request.block_id {
    Some(block_id) -> Some(block_id)
    None -> inherit_block_id(ctx, request.parent_comment_id)
  }

  use body <- result.try(validate_body(request.body))
  use actor_type <- result.try(parse_actor(request.actor))

  case
    ctx.comments.insert(NewComment(
      doc_id: doc.id,
      block_id: block_id,
      parent_comment_id: request.parent_comment_id,
      body: body,
      actor_user_id: scope.actor.id,
      actor_type: actor_type,
    ))
  {
    Error(Nil) -> Error(validation_failed())
    Ok(created) -> {
      log_event(ctx, comment_events.Created, created)
      Ok(created.base_comment_id)
    }
  }
}

/// Edit a comment body — author-only. Inserts a new version row
/// carrying state forward (a resolved comment stays resolved).
pub fn update(
  ctx: Ctx,
  scope: Scope,
  base_id: String,
  body: Option(String),
) -> Result(Nil, ApiError) {
  use current <- result.try(fetch_current(ctx, base_id))
  use Nil <- result.try(ensure_author(current, scope))
  use body <- result.try(validate_body(body))

  case ctx.comments.edit_body(current.id, body) {
    Error(Nil) -> Error(validation_failed())
    Ok(new_version) -> {
      log_event(ctx, comment_events.Updated, new_version)
      Ok(Nil)
    }
  }
}

/// Soft-delete — author-only. State-flag mutation, in-place.
pub fn delete(
  ctx: Ctx,
  scope: Scope,
  base_id: String,
) -> Result(Nil, ApiError) {
  use current <- result.try(fetch_current(ctx, base_id))
  use Nil <- result.try(ensure_author(current, scope))

  let deleted = ctx.comments.soft_delete(current.id, scope.actor.id)
  log_event(ctx, comment_events.Deleted, deleted)
  Ok(Nil)
}

/// Reverse a soft-delete — author-only. Operates on the LATEST version
/// row (the current-row lookup excludes deleted rows by definition).
pub fn undelete(
  ctx: Ctx,
  scope: Scope,
  base_id: String,
) -> Result(Nil, ApiError) {
  case ctx.comments.get_latest_by_base(base_id) {
    None -> Error(NotFound)
    Some(latest) -> {
      use Nil <- result.try(ensure_author(latest, scope))

      let restored = ctx.comments.undelete(latest.id)
      log_event(ctx, comment_events.Updated, restored)
      Ok(Nil)
    }
  }
}

/// Mark a thread resolved. Not author-gated: anyone in the workspace
/// can resolve, same as the human flow in the web UI.
pub fn resolve(
  ctx: Ctx,
  scope: Scope,
  base_id: String,
) -> Result(Nil, ApiError) {
  use current <- result.try(fetch_current(ctx, base_id))

  let resolved = ctx.comments.resolve(current.id, scope.actor.id)
  log_event(ctx, comment_events.Updated, resolved)
  Ok(Nil)
}

pub fn unresolve(
  ctx: Ctx,
  _scope: Scope,
  base_id: String,
) -> Result(Nil, ApiError) {
  use current <- result.try(fetch_current(ctx, base_id))

  let unresolved = ctx.comments.unresolve(current.id)
  log_event(ctx, comment_events.Updated, unresolved)
  Ok(Nil)
}

// ===== Rules =====

fn fetch_current(ctx: Ctx, base_id: String) -> Result(Comment, ApiError) {
  case ctx.comments.get_current_by_base(base_id) {
    None -> Error(NotFound)
    Some(current) -> Ok(current)
  }
}

fn ensure_author(current: Comment, scope: Scope) -> Result(Nil, ApiError) {
  case current.actor_user_id == scope.actor.id {
    True -> Ok(Nil)
    False -> Error(Forbidden("You don't have access to this resource."))
  }
}

fn inherit_block_id(
  ctx: Ctx,
  parent_comment_id: Option(String),
) -> Option(String) {
  case parent_comment_id {
    None -> None
    Some(parent_base_id) ->
      case ctx.comments.get_current_by_base(parent_base_id) {
        None -> None
        Some(parent) -> parent.block_id
      }
  }
}

/// Same rule as the legacy changeset: required, 1..10_000 graphemes.
fn validate_body(body: Option(String)) -> Result(String, ApiError) {
  case body {
    None -> Error(validation_failed())
    Some(body) -> {
      let length = string.length(body)
      case length >= 1 && length <= 10_000 {
        True -> Ok(body)
        False -> Error(validation_failed())
      }
    }
  }
}

fn parse_actor(actor: Option(String)) -> Result(ActorType, ApiError) {
  case option.unwrap(actor, "agent") {
    "human" -> Ok(Human)
    "agent" -> Ok(Agent)
    _ -> Error(validation_failed())
  }
}

/// The exact code + message the changeset path produced.
fn validation_failed() -> ApiError {
  Invalid("validation_failed", "Validation failed.")
}

/// Broadcast happened inside the mutation cap; the activity event is
/// ours. Same gate as before: no doc row for the pin, no event.
fn log_event(
  ctx: Ctx,
  kind: comment_events.CommentEventKind,
  after: Comment,
) -> Nil {
  case ctx.comments.doc_ref(after.doc_id) {
    None -> Nil
    Some(ref) ->
      ctx.comments.record_event(comment_events.attrs(kind, after, ref))
  }
}
