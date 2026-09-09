//// /views endpoints: index / create / update / delete / restore /
//// pin / unpin / move. Ports AvelineWeb.Api.ViewController plus the
//// decision logic of Aveline.Views; SQL stays behind ctx.views caps.
////
//// Views never record activity events or broadcast — parity with the
//// pre-port endpoints.

import aveline/core/ctx.{type Ctx}
import aveline/core/error.{type ApiError, Invalid}
import aveline/core/scope.{type Scope}
import aveline/views/access
import aveline/views/model.{type Bucket, type View, ViewWrite}
import aveline/views/rules
import aveline/views/view_config.{type ConfigParam}
import gleam/bool
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// Where a view should live. Low-spam default: no bucket means YOUR
/// bucket, not the team's — publishing to everyone is explicit.
pub type BucketChoice {
  DefaultBucket
  YoursBucket
  TeamBucket
  NamedBucket(String)
}

pub type CreateViewRequest {
  CreateViewRequest(
    name: String,
    description: Option(String),
    config: ConfigParam,
    bucket: BucketChoice,
  )
}

pub type UpdateViewRequest {
  UpdateViewRequest(
    name: String,
    new_name: Option(String),
    description: Option(String),
    config: ConfigParam,
  )
}

/// Views the actor may use, pinned first then by name.
pub fn index(ctx: Ctx, scope: Scope) -> List(View) {
  let member_ids = ctx.views.member_bucket_ids(scope.actor.id)
  ctx.views.list_views(scope.workspace.id)
  |> list.filter(fn(view) {
    case view.bucket {
      Some(bucket) -> rules.in_audience(bucket, scope.actor.id, member_ids)
      None -> False
    }
  })
}

/// Resolve a bucket choice, lazily creating "yours"/"team" — a side
/// effect the old controller performed eagerly, before any other check.
pub fn resolve_bucket(
  ctx: Ctx,
  scope: Scope,
  choice: BucketChoice,
) -> Result(Bucket, ApiError) {
  case choice {
    DefaultBucket | YoursBucket ->
      Ok(ctx.views.ensure_personal_bucket(scope.workspace.id, scope.actor.id))
    TeamBucket -> Ok(ctx.views.ensure_team_bucket(scope.workspace.id))
    NamedBucket(name) -> access.fetch_bucket(ctx, scope, name)
  }
}

pub fn create(
  ctx: Ctx,
  scope: Scope,
  request: CreateViewRequest,
) -> Result(View, ApiError) {
  use bucket <- result.try(resolve_bucket(ctx, scope, request.bucket))
  use config <- result.try(
    view_config.apply_and_validate(
      model.empty_config(),
      request.config,
      fn(tags) { ctx.views.unknown_tags(scope.workspace.id, tags) },
      fn(s) { ctx.views.scope_has_tags(scope.workspace.id, s) },
    ),
  )
  use name <- result.try(
    rules.validate_slug_name(rules.normalize_name(request.name)),
  )
  use description <- result.try(rules.validate_description(request.description))
  ctx.views.insert_view(ViewWrite(
    workspace_id: scope.workspace.id,
    base_view_id: None,
    version_number: 1,
    name:,
    description:,
    config:,
    pinned: False,
    bucket_id: bucket.id,
    // The creator owns the view; ownership never moves with edits.
    owner_id: scope.actor.id,
    created_by_id: scope.actor.id,
  ))
  |> result.replace_error(name_conflict())
}

/// Versioned edit: mints v+1 on the same base id (supersede-then-insert
/// happens in one transactional cap). Config edits MERGE onto the
/// current config; pinned, bucket and owner carry over.
pub fn update(
  ctx: Ctx,
  scope: Scope,
  request: UpdateViewRequest,
) -> Result(View, ApiError) {
  use view <- result.try(access.fetch_usable(ctx, scope, request.name))
  use config <- result.try(
    view_config.apply_and_validate(
      view.config,
      request.config,
      fn(tags) { ctx.views.unknown_tags(scope.workspace.id, tags) },
      fn(s) { ctx.views.scope_has_tags(scope.workspace.id, s) },
    ),
  )
  use name <- result.try(case request.new_name {
    None -> Ok(view.name)
    Some(n) -> rules.validate_slug_name(rules.normalize_name(n))
  })
  use description <- result.try(case request.description {
    None -> Ok(view.description)
    Some(_) -> rules.validate_description(request.description)
  })
  // fetch_usable guarantees the bucket is present.
  let assert Some(bucket) = view.bucket
  ctx.views.replace_version(
    view.id,
    ViewWrite(
      workspace_id: view.workspace_id,
      base_view_id: Some(view.base_view_id),
      version_number: view.version_number + 1,
      name:,
      description:,
      config:,
      pinned: view.pinned,
      bucket_id: bucket.id,
      owner_id: view.owner_id,
      created_by_id: scope.actor.id,
    ),
  )
  |> result.replace_error(name_conflict())
}

fn name_conflict() -> ApiError {
  Invalid("validation_failed", "already exists")
}

pub fn delete(ctx: Ctx, scope: Scope, name: String) -> Result(Nil, ApiError) {
  use view <- result.try(access.fetch_usable(ctx, scope, name))
  Ok(ctx.views.soft_delete_view(view.id, scope.actor.id))
}

/// Restore a user-deleted view by name. No audience check — parity with
/// the old endpoint, which restored by name for any workspace member.
pub fn restore(ctx: Ctx, scope: Scope, name: String) -> Result(View, ApiError) {
  case ctx.views.find_restorable(scope.workspace.id, name) {
    None ->
      Error(Invalid(
        "not_user_deleted",
        "Doc was not user-deleted (it's the current live version or was superseded by a new version).",
      ))
    Some(view) -> Ok(ctx.views.restore_view(view.id))
  }
}

/// Placement, not meaning: in-place update, no version minted.
pub fn set_pinned(
  ctx: Ctx,
  scope: Scope,
  name: String,
  pinned: Bool,
) -> Result(View, ApiError) {
  use view <- result.try(access.fetch_usable(ctx, scope, name))
  Ok(ctx.views.set_view_pinned(view.id, pinned))
}

/// Move a view to another bucket, in place. The view's owner only, and
/// only into a bucket they can use.
pub fn move(
  ctx: Ctx,
  scope: Scope,
  name: String,
  choice: BucketChoice,
) -> Result(View, ApiError) {
  // Bucket resolution happens before the view fetch, matching the old
  // controller: "yours"/"team" lazily create their bucket even when the
  // view lookup goes on to fail.
  let bucket_result = resolve_bucket(ctx, scope, choice)
  use view <- result.try(access.fetch_usable(ctx, scope, name))
  use bucket <- result.try(bucket_result)
  use <- bool.guard(
    view.owner_id != scope.actor.id,
    Error(Invalid("validation_failed", "only the view's owner can move it")),
  )
  use <- bool.guard(
    bucket.workspace_id != view.workspace_id,
    Error(Invalid(
      "validation_failed",
      "that bucket belongs to another workspace",
    )),
  )
  use <- bool.guard(
    !access.in_audience(ctx, bucket, scope.actor.id),
    Error(Invalid("validation_failed", "you aren't in that bucket")),
  )
  Ok(ctx.views.move_view(view.id, bucket.id))
}
