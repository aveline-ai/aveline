//// The one access rule for every by-name view/bucket endpoint:
//// inaccessible and nonexistent are indistinguishable on purpose.

import aveline/core/ctx.{type Ctx}
import aveline/core/error.{type ApiError, NotFound}
import aveline/core/scope.{type Scope}
import aveline/views/model.{type Bucket, type View, Project, WorkspaceVisible}
import gleam/list
import gleam/option.{None, Some}

/// Is `user_id` in the bucket's audience, paying the membership query
/// only when visibility actually requires it?
pub fn in_audience(ctx: Ctx, bucket: Bucket, user_id: String) -> Bool {
  case
    bucket.visibility == WorkspaceVisible || bucket.owner_id == Some(user_id)
  {
    True -> True
    False ->
      case bucket.kind {
        Project ->
          list.contains(ctx.views.member_bucket_ids(user_id), bucket.id)
        _ -> False
      }
  }
}

pub fn fetch_bucket(
  ctx: Ctx,
  scope: Scope,
  name: String,
) -> Result(Bucket, ApiError) {
  case ctx.views.get_bucket(scope.workspace.id, name) {
    None -> Error(NotFound)
    Some(bucket) ->
      case in_audience(ctx, bucket, scope.actor.id) {
        True -> Ok(bucket)
        False -> Error(NotFound)
      }
  }
}

/// May this workspace member use (and, binary membership, edit) the
/// view? Its bucket's audience decides.
pub fn fetch_usable(
  ctx: Ctx,
  scope: Scope,
  name: String,
) -> Result(View, ApiError) {
  case ctx.views.get_current_by_name(scope.workspace.id, name) {
    None -> Error(NotFound)
    Some(view) ->
      case view.bucket {
        None -> Error(NotFound)
        Some(bucket) ->
          case in_audience(ctx, bucket, scope.actor.id) {
            True -> Ok(view)
            False -> Error(NotFound)
          }
      }
  }
}
