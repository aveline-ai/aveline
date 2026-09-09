//// POST /docs/:doc_slug/kudos — toggle a kudos marker. Returns the new
//// state (given_by_me + count) so the agent doesn't need a follow-up
//// read. Ports DocController.kudos + Kudos.toggle.

import aveline/core/ctx.{type Ctx}
import aveline/core/error.{type ApiError, Invalid}
import aveline/core/events.{EventAttrs, Human}
import aveline/core/scope.{type Scope}
import aveline/docs/access
import gleam/option.{None, Some}
import gleam/result

pub type KudosResponse {
  KudosResponse(given_by_me: Bool, count: Int)
}

pub fn toggle(
  ctx: Ctx,
  scope: Scope,
  slug: String,
) -> Result(KudosResponse, ApiError) {
  use doc <- result.try(access.fetch_readable(ctx, scope, slug))

  case doc.owner_id == scope.actor.id {
    True ->
      Error(Invalid("self_kudos", "You can't give kudos to your own doc."))
    False -> {
      let given = case ctx.kudos.find(doc.base_doc_id, scope.actor.id) {
        Some(mark_id) -> {
          ctx.kudos.revoke(mark_id)
          False
        }
        None -> {
          ctx.kudos.give(scope.workspace.id, doc.base_doc_id, scope.actor.id)
          True
        }
      }

      ctx.events.record(EventAttrs(
        workspace_id: scope.workspace.id,
        actor: scope.actor.id,
        actor_type: Human,
        action: case given {
          True -> "kudos_given"
          False -> "kudos_revoked"
        },
        target_kind: "doc",
        target_id: doc.base_doc_id,
        target_slug: Some(doc.slug),
        target_label: Some(doc.title),
      ))

      Ok(KudosResponse(
        given_by_me: given,
        count: ctx.kudos.count_for_base(doc.base_doc_id),
      ))
    }
  }
}
