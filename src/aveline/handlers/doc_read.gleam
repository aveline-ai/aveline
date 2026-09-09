//// Doc read endpoints: GET /docs/:slug (show), GET /orientation, and
//// POST /docs/:slug/blocks/:block_id/run. Ports DocController.show /
//// orientation / run_block: access rules and DocViews recording live
//// here; block enrichment/rendering and the chart engine stay behind
//// coarse caps returning opaque payloads.

import aveline/core/ctx.{type Ctx}
import aveline/core/error.{type ApiError, Invalid, NotFound}
import aveline/core/scope.{type Scope}
import aveline/docs/access
import gleam/dynamic.{type Dynamic}
import gleam/option.{None, Some}
import gleam/result

pub fn show(ctx: Ctx, scope: Scope, slug: String) -> Result(Dynamic, ApiError) {
  use doc <- result.try(access.fetch_readable(ctx, scope, slug))
  // Record an agent "read" event — same as the LV connects do.
  ctx.docs.record_view(
    scope.workspace.id,
    doc.base_doc_id,
    scope.actor.id,
    "agent",
  )
  // Reads return chart CONFIG, not data — a doc read never dials a
  // customer database. Agents fetch rows explicitly via run-block.
  case ctx.docs.read_full(scope.workspace.id, doc.slug, scope.actor.id) {
    Some(payload) -> Ok(payload)
    None -> Error(NotFound)
  }
}

/// The workspace orientation doc (well-known slug, seeded at workspace
/// creation, undeletable). Always workspace-visible, so no access check.
pub fn orientation(ctx: Ctx, scope: Scope) -> Result(Dynamic, ApiError) {
  case ctx.docs.get_orientation(scope.workspace.id) {
    None -> Error(NotFound)
    Some(doc) -> {
      ctx.docs.record_view(
        scope.workspace.id,
        doc.base_doc_id,
        scope.actor.id,
        "agent",
      )
      case ctx.docs.read_full(scope.workspace.id, doc.slug, scope.actor.id) {
        Some(payload) -> Ok(payload)
        None -> Error(NotFound)
      }
    }
  }
}

/// Run one chart block and return its rows — the explicit path to chart
/// data now that reads return config only. Result is returned, never
/// stored.
pub fn run_block(
  ctx: Ctx,
  scope: Scope,
  slug: String,
  block_id: String,
) -> Result(Dynamic, ApiError) {
  use _doc <- result.try(access.fetch_readable(ctx, scope, slug))
  case ctx.docs.find_chart_block(scope.workspace.id, slug, block_id) {
    None -> Error(NotFound)
    Some(block) ->
      case ctx.docs.run_chart(scope.workspace.id, block) {
        Ok(rows) -> Ok(rows)
        Error(message) -> Error(Invalid("query_failed", message))
      }
  }
}
