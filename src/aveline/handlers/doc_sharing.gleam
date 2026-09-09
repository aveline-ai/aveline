//// Visibility & share endpoints: PUT /docs/:slug/visibility and the
//// shares collection. Ports DocController.set_visibility/shares/share/
//// unshare plus the decision logic of Docs.set_visibility/share_doc/
//// unshare_doc. Mutations (+ their data-carrying activity events) stay
//// behind coarse caps.

import aveline/core/ctx.{type Ctx}
import aveline/core/error.{type ApiError}
import aveline/core/scope.{type Scope}
import aveline/docs/access
import aveline/docs/doc_error.{type DocError, NotMember, invalid}
import aveline/docs/doc_meta.{
  type DocMeta, type ShareInfo, type Visibility, Private, WorkspaceVisible,
}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

pub type VisibilityResponse {
  VisibilityResponse(slug: String, doc_id: String, visibility: String)
}

pub type SharesResponse {
  SharesResponse(
    slug: String,
    doc_id: String,
    visibility: String,
    shares: List(ShareInfo),
  )
}

pub type ShareResponse {
  ShareResponse(slug: String, doc_id: String, username: String, role: String)
}

pub type UnshareResponse {
  UnshareResponse(slug: String, doc_id: String, username: String)
}

/// Change a doc's visibility in place: "private" | "workspace". Owner
/// only. Does not create a version — visibility is placement-style
/// state, like pin slots.
pub fn set_visibility(
  ctx: Ctx,
  scope: Scope,
  slug: String,
  raw_visibility: String,
) -> Result(VisibilityResponse, DocError) {
  use doc <- result.try(doc_error.api(access.fetch_readable(ctx, scope, slug)))
  use visibility <- result.try(parse_visibility(raw_visibility))
  use _ <- result.try(check_visibility_change(doc, visibility, scope.actor.id))

  case doc.visibility == visibility {
    // Already there: a quiet no-op, no event, no broadcast.
    True -> Nil
    False ->
      ctx.docs.set_visibility(
        scope.workspace.id,
        slug,
        visibility,
        scope.actor.id,
      )
  }

  Ok(VisibilityResponse(
    slug: doc.slug,
    doc_id: doc.base_doc_id,
    visibility: doc_meta.visibility_string(visibility),
  ))
}

fn parse_visibility(raw: String) -> Result(Visibility, DocError) {
  case raw {
    "private" -> Ok(Private)
    "workspace" -> Ok(WorkspaceVisible)
    _ ->
      Error(invalid(
        "validation_failed",
        "visibility must be one of: private, workspace",
      ))
  }
}

// Rule order matches the legacy Docs.set_visibility cond: orientation,
// then ownership, then the pinned-can't-go-private rule.
fn check_visibility_change(
  doc: DocMeta,
  visibility: Visibility,
  actor_id: String,
) -> Result(Nil, DocError) {
  case doc.orientation {
    // The orientation doc is permanently public.
    True ->
      Error(invalid(
        "validation_failed",
        "the orientation doc is always visible to the whole workspace",
      ))
    False ->
      case doc.owner_id == actor_id {
        False ->
          Error(invalid(
            "validation_failed",
            "only the doc's owner can change its visibility",
          ))
        True ->
          case visibility, doc.pin_slot {
            // The home page is a team surface; a pinned private doc
            // would leak its title there.
            Private, Some(_) ->
              Error(invalid(
                "validation_failed",
                "unpin this doc first: pinned docs are a team surface and can't be private",
              ))
            _, _ -> Ok(Nil)
          }
      }
  }
}

/// Live shares on a doc, with usernames. Readable by anyone who can
/// read the doc.
pub fn shares(
  ctx: Ctx,
  scope: Scope,
  slug: String,
) -> Result(SharesResponse, ApiError) {
  use doc <- result.try(access.fetch_readable(ctx, scope, slug))
  Ok(SharesResponse(
    slug: doc.slug,
    doc_id: doc.base_doc_id,
    visibility: doc_meta.visibility_string(doc.visibility),
    shares: ctx.docs.list_shares(doc.base_doc_id),
  ))
}

pub const share_roles = ["viewer", "editor"]

/// Grant a workspace member access to a private doc. Owner only;
/// upserts the live share. Role defaults to viewer.
pub fn share(
  ctx: Ctx,
  scope: Scope,
  slug: String,
  username: String,
  role_param: Option(String),
) -> Result(ShareResponse, DocError) {
  use doc <- result.try(doc_error.api(access.fetch_readable(ctx, scope, slug)))
  case ctx.docs.user_id_by_username(username) {
    None -> Error(NotMember)
    Some(target_id) -> {
      let role = option.unwrap(role_param, "viewer")
      use _ <- result.try(check_share(ctx, scope, doc, target_id, role))
      ctx.docs.share_doc(
        scope.workspace.id,
        slug,
        target_id,
        role,
        scope.actor.id,
      )
      Ok(ShareResponse(
        slug: doc.slug,
        doc_id: doc.base_doc_id,
        username: username,
        role: role,
      ))
    }
  }
}

// Rule order matches the legacy Docs.share_doc cond.
fn check_share(
  ctx: Ctx,
  scope: Scope,
  doc: DocMeta,
  target_id: String,
  role: String,
) -> Result(Nil, DocError) {
  case list.contains(share_roles, role) {
    False ->
      Error(invalid("validation_failed", "role must be one of: viewer, editor"))
    True ->
      case doc.owner_id == scope.actor.id {
        False ->
          Error(invalid(
            "validation_failed",
            "only the doc's owner can share it",
          ))
        True ->
          case target_id == doc.owner_id {
            True ->
              Error(invalid(
                "validation_failed",
                "the owner already has full access",
              ))
            False ->
              case ctx.docs.is_member(scope.workspace.id, target_id) {
                False ->
                  Error(invalid(
                    "validation_failed",
                    "that user is not a member of this workspace",
                  ))
                True -> Ok(Nil)
              }
          }
      }
  }
}

/// Revoke a member's share. Owner only; soft delete.
pub fn unshare(
  ctx: Ctx,
  scope: Scope,
  slug: String,
  username: String,
) -> Result(UnshareResponse, DocError) {
  use doc <- result.try(doc_error.api(access.fetch_readable(ctx, scope, slug)))
  case ctx.docs.user_id_by_username(username) {
    None -> Error(NotMember)
    Some(target_id) ->
      case doc.owner_id == scope.actor.id {
        False ->
          Error(invalid(
            "validation_failed",
            "only the doc's owner can revoke shares",
          ))
        True ->
          case ctx.docs.share_role(doc.base_doc_id, target_id) {
            None ->
              Error(invalid(
                "validation_failed",
                "no live share for that user on this doc",
              ))
            Some(_) -> {
              ctx.docs.revoke_share(
                scope.workspace.id,
                slug,
                target_id,
                scope.actor.id,
              )
              Ok(UnshareResponse(
                slug: doc.slug,
                doc_id: doc.base_doc_id,
                username: username,
              ))
            }
          }
      }
  }
}
