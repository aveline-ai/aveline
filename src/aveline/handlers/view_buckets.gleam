//// /view-buckets endpoints: list / create / delete / visibility /
//// members. Ports AvelineWeb.Api.ViewController's bucket actions plus
//// the bucket decision logic of Aveline.Views.

import aveline/core/ctx.{type Ctx}
import aveline/core/error.{type ApiError, Invalid}
import aveline/core/scope.{type Scope}
import aveline/views/access
import aveline/views/model.{
  type Bucket, type BucketKind, type BucketVisibility, Private, Project,
  WorkspaceVisible,
}
import aveline/views/rules
import gleam/bool
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// What the buckets endpoints answer with: the bucket plus its resolved
/// owner username and (for project buckets) live member usernames.
pub type BucketSummary {
  BucketSummary(
    name: String,
    kind: BucketKind,
    visibility: BucketVisibility,
    owner: Option(String),
    members: List(Option(String)),
  )
}

/// Buckets the actor can use, each with its member list. Ordered kind
/// then name.
pub fn index(ctx: Ctx, scope: Scope) -> List(BucketSummary) {
  let member_ids = ctx.views.member_bucket_ids(scope.actor.id)
  ctx.views.list_buckets(scope.workspace.id)
  |> list.filter(rules.in_audience(_, scope.actor.id, member_ids))
  |> list.map(summarize(ctx, _))
}

fn summarize(ctx: Ctx, bucket: Bucket) -> BucketSummary {
  let members = case bucket.kind {
    Project -> ctx.views.list_bucket_member_usernames(bucket.id)
    _ -> []
  }
  let owner = case bucket.owner_id {
    None -> None
    Some(user_id) -> ctx.views.get_username(user_id)
  }
  BucketSummary(
    name: bucket.name,
    kind: bucket.kind,
    visibility: bucket.visibility,
    owner:,
    members:,
  )
}

/// Create a project bucket. Reserved names (team, personal-*) rejected;
/// visibility private (owner + members, the default) | workspace.
pub fn create(
  ctx: Ctx,
  scope: Scope,
  raw_name: String,
  raw_visibility: Option(String),
) -> Result(BucketSummary, ApiError) {
  let name = rules.normalize_name(raw_name)
  use <- bool.guard(
    rules.reserved_bucket_name(name),
    Error(Invalid("validation_failed", "that bucket name is reserved")),
  )
  use visibility <- result.try(case raw_visibility {
    None -> Ok(Private)
    Some("private") -> Ok(Private)
    Some("workspace") -> Ok(WorkspaceVisible)
    Some(_) -> Error(Invalid("validation_failed", "visibility is invalid"))
  })
  use name <- result.try(rules.validate_slug_name(name))
  case
    ctx.views.insert_bucket(
      scope.workspace.id,
      name,
      scope.actor.id,
      visibility,
    )
  {
    Ok(bucket) -> Ok(summarize(ctx, bucket))
    Error(Nil) -> Error(Invalid("validation_failed", "already exists"))
  }
}

/// Change a project bucket's visibility in place. Owner only; team and
/// personal buckets are fixed by definition.
pub fn set_visibility(
  ctx: Ctx,
  scope: Scope,
  bucket_name: String,
  raw_visibility: String,
) -> Result(BucketSummary, ApiError) {
  use bucket <- result.try(access.fetch_bucket(ctx, scope, bucket_name))
  use visibility <- result.try(case raw_visibility {
    "private" -> Ok(Private)
    "workspace" -> Ok(WorkspaceVisible)
    _ ->
      Error(Invalid(
        "validation_failed",
        "visibility must be one of: private, workspace",
      ))
  })
  use <- bool.guard(
    bucket.kind != Project,
    Error(Invalid(
      "validation_failed",
      "team is always workspace-visible and personal is always private; only project buckets change",
    )),
  )
  use <- bool.guard(
    bucket.owner_id != Some(scope.actor.id),
    Error(Invalid(
      "validation_failed",
      "only the bucket's owner can change its visibility",
    )),
  )
  case bucket.visibility == visibility {
    True -> Ok(summarize(ctx, bucket))
    False ->
      Ok(summarize(ctx, ctx.views.set_bucket_visibility(bucket.id, visibility)))
  }
}

/// Delete a project bucket. Owner only; must hold no live views.
pub fn delete(
  ctx: Ctx,
  scope: Scope,
  bucket_name: String,
) -> Result(Nil, ApiError) {
  use bucket <- result.try(access.fetch_bucket(ctx, scope, bucket_name))
  use <- bool.guard(
    bucket.kind != Project,
    Error(Invalid("validation_failed", "only project buckets can be deleted")),
  )
  use <- bool.guard(
    bucket.owner_id != Some(scope.actor.id),
    Error(Invalid("validation_failed", "only the bucket's owner can delete it")),
  )
  use <- bool.guard(
    ctx.views.bucket_has_live_views(bucket.id),
    Error(Invalid(
      "validation_failed",
      "move or delete this bucket's views first",
    )),
  )
  Ok(ctx.views.soft_delete_bucket(bucket.id))
}

/// Add a workspace member to a project bucket. Owner only; binary
/// membership.
pub fn add_member(
  ctx: Ctx,
  scope: Scope,
  bucket_name: String,
  username: String,
) -> Result(Nil, ApiError) {
  use bucket <- result.try(access.fetch_bucket(ctx, scope, bucket_name))
  use target_id <- result.try(fetch_target(ctx, username))
  use <- bool.guard(
    bucket.kind != Project,
    Error(Invalid(
      "validation_failed",
      "only project buckets take members; team is everyone and personal is just you",
    )),
  )
  use <- bool.guard(
    bucket.owner_id != Some(scope.actor.id),
    Error(Invalid(
      "validation_failed",
      "only the bucket's owner can add members",
    )),
  )
  use <- bool.guard(
    Some(target_id) == bucket.owner_id,
    Error(Invalid("validation_failed", "the owner is already in the bucket")),
  )
  use <- bool.guard(
    !ctx.views.is_workspace_member(bucket.workspace_id, target_id),
    Error(Invalid(
      "validation_failed",
      "that user is not a member of this workspace",
    )),
  )
  case ctx.views.find_live_membership(bucket.id, target_id) {
    Some(_) ->
      Error(Invalid("validation_failed", "that user is already in the bucket"))
    None ->
      Ok(ctx.views.insert_bucket_member(bucket.id, target_id, scope.actor.id))
  }
}

/// Remove a member from a project bucket. Owner only; soft delete.
pub fn remove_member(
  ctx: Ctx,
  scope: Scope,
  bucket_name: String,
  username: String,
) -> Result(Nil, ApiError) {
  use bucket <- result.try(access.fetch_bucket(ctx, scope, bucket_name))
  use target_id <- result.try(fetch_target(ctx, username))
  use <- bool.guard(
    bucket.owner_id != Some(scope.actor.id),
    Error(Invalid(
      "validation_failed",
      "only the bucket's owner can remove members",
    )),
  )
  case ctx.views.find_live_membership(bucket.id, target_id) {
    None ->
      Error(Invalid("validation_failed", "that user is not in the bucket"))
    Some(row_id) -> Ok(ctx.views.soft_delete_membership(row_id))
  }
}

// A username that resolves to no account maps to the workspace-level
// not_member error, exactly like the old `|| {:error, :not_member}`.
fn fetch_target(ctx: Ctx, username: String) -> Result(String, ApiError) {
  case ctx.views.find_user_id_by_username(username) {
    None ->
      Error(Invalid("not_member", "User is not a member of this workspace."))
    Some(id) -> Ok(id)
  }
}
