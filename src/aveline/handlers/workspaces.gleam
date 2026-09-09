//// /api/workspaces — list mine, show one, create one. Ports
//// WorkspaceController (membership management lives in TeamController,
//// not here). Not workspace-scoped: these endpoints take the bare Actor.
////
//// Errors ride the fallback's generic coded path: `workspace_not_found`
//// maps to 404 and `forbidden` to 403 there, exactly as before.

import aveline/caps/workspaces.{SlugTaken}
import aveline/core/ctx.{type Ctx}
import aveline/core/error.{type ApiError, Forbidden, Invalid}
import aveline/core/scope.{type Actor}
import aveline/slug
import aveline/workspaces/workspace_info.{type WorkspaceInfo}
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type CreateRequest {
  CreateRequest(name: Option(String), slug: Option(String))
}

pub fn index(ctx: Ctx, actor: Actor) -> List(WorkspaceInfo) {
  ctx.workspaces.list_for_user(actor.id)
}

pub fn show(
  ctx: Ctx,
  actor: Actor,
  slug: String,
) -> Result(WorkspaceInfo, ApiError) {
  case ctx.workspaces.get_active_by_slug(slug) {
    None -> Error(Invalid("workspace_not_found", "Workspace not found."))
    Some(ws) ->
      case ctx.workspaces.is_member(ws.id, actor.id) {
        False -> Error(Forbidden("You don't have access to this resource."))
        True -> Ok(ws)
      }
  }
}

pub fn create(
  ctx: Ctx,
  actor: Actor,
  req: CreateRequest,
) -> Result(WorkspaceInfo, ApiError) {
  use name <- result.try(validate_name(req.name))
  use slug_value <- result.try(resolve_slug(req.slug, name))

  case ctx.workspaces.create(name, slug_value, actor.id) {
    Error(SlugTaken) -> Error(Invalid("slug_taken", "Slug already in use."))
    Ok(ws) -> {
      ctx.workspaces.ensure_member(ws.id, actor.id)
      Ok(ws)
    }
  }
}

/// Name is required, 1–200 chars (mirrors Workspace.changeset).
fn validate_name(name: Option(String)) -> Result(String, ApiError) {
  case name {
    Some(n) ->
      case string.length(n) {
        0 -> Error(validation_failed())
        l if l <= 200 -> Ok(n)
        _ -> Error(validation_failed())
      }
    None -> Error(validation_failed())
  }
}

/// A given slug is downcased and format-checked; an omitted one derives
/// from the name so the CLI's `--name`-only flow works.
fn resolve_slug(
  given: Option(String),
  name: String,
) -> Result(String, ApiError) {
  case given {
    Some(s) -> {
      let s = string.lowercase(s)
      case slug.validate(s) {
        True -> Ok(s)
        False -> Error(validation_failed())
      }
    }
    None ->
      case slug.derive_from(name) {
        Some(s) -> Ok(s)
        None -> Error(validation_failed())
      }
  }
}

fn validation_failed() -> ApiError {
  Invalid("validation_failed", "Validation failed.")
}
