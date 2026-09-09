//// Version history: GET /docs/:slug/versions and
//// GET /docs/:slug/versions/:version_number. Ports VersionController.
//// Rendering (metadata list, full body with config-only chart
//// enrichment) stays behind opaque caps.

import aveline/core/ctx.{type Ctx}
import aveline/core/error.{type ApiError, NotFound}
import aveline/core/scope.{type Scope}
import aveline/docs/access
import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/option.{None, Some}
import gleam/result

pub type VersionList {
  VersionList(versions: Dynamic, current_version: Int)
}

/// List metadata for every version. Parity note: like the legacy
/// endpoint, this deliberately mirrors its behavior of not applying the
/// private-doc readability check — the doc only needs to exist.
pub fn index(
  ctx: Ctx,
  scope: Scope,
  slug: String,
) -> Result(VersionList, ApiError) {
  case ctx.docs.get_current_by_slug(scope.workspace.id, slug) {
    None -> Error(NotFound)
    Some(doc) ->
      Ok(VersionList(
        versions: ctx.docs.list_versions(doc.base_doc_id),
        current_version: doc.version_number,
      ))
  }
}

/// Full body of a specific version. Config only, no chart execution —
/// historical SQL is never fired at a customer database on read.
pub fn show(
  ctx: Ctx,
  scope: Scope,
  slug: String,
  raw_version: String,
) -> Result(Dynamic, ApiError) {
  use doc <- result.try(access.fetch_readable(ctx, scope, slug))
  case int.parse(raw_version) {
    Error(_) -> Error(NotFound)
    Ok(version_number) ->
      case
        ctx.docs.read_version_full(
          scope.workspace.id,
          doc.base_doc_id,
          version_number,
          scope.actor.id,
        )
      {
        None -> Error(NotFound)
        Some(payload) -> Ok(payload)
      }
  }
}
