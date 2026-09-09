//// Doc write endpoints: create, update, delete, restore. Ports
//// DocController.create/update/delete/restore plus the decision logic
//// of Docs.soft_delete (orientation rule) and the restore access rules.
//// The block engine and version machinery stay behind coarse caps whose
//// payloads pass through opaquely; bare-message block failures get the
//// `aveline contract` hint appended here.

import aveline/core/ctx.{type Ctx}
import aveline/core/error.{Invalid, NotFound}
import aveline/core/events.{EventAttrs, Human}
import aveline/core/scope.{type Scope}
import aveline/docs/access
import aveline/docs/doc_error.{
  type DocError, Api, NotUserDeleted, OrientationUndeletable, Passthrough,
}
import aveline/docs/doc_meta.{Private}
import aveline/docs/doc_writes.{
  type DocPointer, type RestoredDoc, type WriteFailure, BlockInvalid,
  CreateAttrs, OtherFailure, RestoreNotFound, RestoreNotUserDeleted, UpdateAttrs,
}
import gleam/dynamic.{type Dynamic}
import gleam/option.{type Option, None, Some}
import gleam/result

// Block/op validation failures are where cold agents flail: meet them
// at the failure point with the pointer to the write contract.
pub const contract_hint = " Run `aveline contract` for every block type and op with a valid example."

pub type CreateRequest {
  CreateRequest(
    title: Option(String),
    slug: Option(String),
    summary: Option(String),
    tags: Dynamic,
    blocks: Dynamic,
    intent: Option(String),
    actor: Option(String),
    visibility: Option(String),
  )
}

pub fn create(
  ctx: Ctx,
  scope: Scope,
  req: CreateRequest,
) -> Result(DocPointer, DocError) {
  let attrs =
    CreateAttrs(
      workspace_id: scope.workspace.id,
      owner_id: scope.actor.id,
      actor_user_id: scope.actor.id,
      actor_type: option.unwrap(req.actor, "agent"),
      title: req.title,
      slug: req.slug,
      summary: req.summary,
      intent: req.intent,
      // Low-spam default: docs are born private; publishing to the
      // workspace is an explicit act.
      visibility: option.unwrap(req.visibility, "private"),
    )

  ctx.docs.create_doc(attrs, req.tags, req.blocks)
  |> map_write
}

pub type UpdateRequest {
  UpdateRequest(
    /// Present only when the request body carried a blocks LIST.
    blocks: Option(Dynamic),
    /// Whether the operations param was a list (drives the edit-mode rule).
    ops_is_list: Bool,
    /// The operations payload (already defaulted to an empty list).
    ops: Dynamic,
    title: Option(String),
    summary: Option(String),
    tags: Option(Dynamic),
    intent: Option(String),
    actor: Option(String),
    resolves: Dynamic,
    dispositions: Dynamic,
  )
}

pub fn update(
  ctx: Ctx,
  scope: Scope,
  slug: String,
  req: UpdateRequest,
) -> Result(DocPointer, DocError) {
  use doc <- result.try(doc_error.api(access.fetch_readable(ctx, scope, slug)))
  use _ <- result.try(doc_error.api(access.ensure_editable(ctx, scope, doc)))
  use _ <- result.try(validate_edit_mode(req))

  let attrs =
    UpdateAttrs(
      actor_user_id: scope.actor.id,
      actor_type: option.unwrap(req.actor, "agent"),
      title: req.title,
      summary: req.summary,
      tags: req.tags,
      intent: req.intent,
      resolves: req.resolves,
      dispositions: req.dispositions,
    )

  case req.blocks {
    Some(blocks) ->
      ctx.docs.replace_blocks(scope.workspace.id, slug, blocks, attrs)
    None -> ctx.docs.apply_ops(scope.workspace.id, slug, req.ops, attrs)
  }
  |> map_write
}

// Exactly one of blocks / operations. Both is ambiguous (which wins?);
// neither is a no-op edit — reject both so the agent gets a clear error.
fn validate_edit_mode(req: UpdateRequest) -> Result(Nil, DocError) {
  case req.blocks, req.ops_is_list {
    Some(_), True ->
      Error(
        Api(Invalid(
          "bad_request",
          "send either blocks (full replace) or operations (surgical), not both",
        )),
      )
    _, _ -> Ok(Nil)
  }
}

fn map_write(
  outcome: Result(DocPointer, WriteFailure),
) -> Result(DocPointer, DocError) {
  case outcome {
    Ok(pointer) -> Ok(pointer)
    Error(BlockInvalid(message)) ->
      Error(Api(Invalid("validation_failed", message <> contract_hint)))
    Error(OtherFailure(reason)) -> Error(Passthrough(reason))
  }
}

pub fn delete(ctx: Ctx, scope: Scope, slug: String) -> Result(Nil, DocError) {
  use doc <- result.try(doc_error.api(access.fetch_readable(ctx, scope, slug)))
  use _ <- result.try(doc_error.api(access.ensure_editable(ctx, scope, doc)))

  case doc.orientation {
    True -> Error(OrientationUndeletable)
    False -> {
      ctx.docs.soft_delete(scope.workspace.id, slug, scope.actor.id)
      ctx.events.record(EventAttrs(
        workspace_id: scope.workspace.id,
        actor: scope.actor.id,
        actor_type: Human,
        action: "doc_deleted",
        target_kind: "doc",
        target_id: doc.base_doc_id,
        target_slug: Some(doc.slug),
        target_label: Some(doc.title),
      ))
      Ok(Nil)
    }
  }
}

pub fn restore(
  ctx: Ctx,
  scope: Scope,
  slug: String,
) -> Result(RestoredDoc, DocError) {
  case ctx.docs.latest_version_by_slug(scope.workspace.id, slug) {
    None -> Error(Api(NotFound))
    // A deleted private doc stays private: only its owner can restore
    // it, and to anyone else it does not exist.
    Some(doc) ->
      case doc.visibility == Private && doc.owner_id != scope.actor.id {
        True -> Error(Api(NotFound))
        False ->
          case ctx.docs.restore(doc.base_doc_id) {
            Ok(restored) -> Ok(restored)
            Error(RestoreNotFound) -> Error(Api(NotFound))
            Error(RestoreNotUserDeleted) -> Error(NotUserDeleted)
          }
      }
  }
}
