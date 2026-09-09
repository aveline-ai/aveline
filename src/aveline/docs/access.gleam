//// The one access rule for every by-slug endpoint.

import aveline/core/ctx.{type Ctx}
import aveline/core/error.{type ApiError, Forbidden, NotFound}
import aveline/core/scope.{type Scope}
import aveline/docs/doc_meta.{type DocMeta}
import aveline/docs/permissions
import gleam/option.{None, Some}

pub fn fetch_readable(
  ctx: Ctx,
  scope: Scope,
  slug: String,
) -> Result(DocMeta, ApiError) {
  case ctx.docs.get_current_by_slug(scope.workspace.id, slug) {
    None -> Error(NotFound)
    Some(doc) -> {
      let share = fn() { ctx.docs.share_role(doc.base_doc_id, scope.actor.id) }
      case permissions.can_read(doc, scope.actor.id, share) {
        True -> Ok(doc)
        False -> Error(NotFound)
      }
    }
  }
}

pub fn ensure_editable(
  ctx: Ctx,
  scope: Scope,
  doc: DocMeta,
) -> Result(Nil, ApiError) {
  let share = fn() { ctx.docs.share_role(doc.base_doc_id, scope.actor.id) }
  case permissions.can_edit(doc, scope.actor.id, share) {
    True -> Ok(Nil)
    False ->
      Error(Forbidden(
        "You have viewer access to this doc; editing needs an editor share or ownership.",
      ))
  }
}
