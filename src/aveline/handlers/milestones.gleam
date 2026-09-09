//// Timeline milestone endpoints — GET/POST /milestones and DELETE
//// /milestones/:id. Ports MilestoneController index/create/delete plus
//// the decision logic in Aveline.Milestones (validation, active-row
//// lookup before soft-delete). No activity events: the pre-port
//// endpoints recorded none.

import aveline/core/ctx.{type Ctx}
import aveline/core/error.{type ApiError, NotFound}
import aveline/core/scope.{type Scope}
import aveline/milestones/milestone.{type Milestone, NewMilestone}
import aveline/milestones/validate
import gleam/option.{type Option, None, Some}
import gleam/result

/// Raw create body — the controller passes strings through untouched
/// (absent or non-string fields arrive as None / ""); validation
/// happens here.
pub type CreateRequest {
  CreateRequest(name: String, date: Option(String), description: Option(String))
}

pub fn index(ctx: Ctx, scope: Scope) -> List(Milestone) {
  ctx.milestones.list_active(scope.workspace.id)
}

pub fn create(
  ctx: Ctx,
  scope: Scope,
  request: CreateRequest,
) -> Result(Milestone, ApiError) {
  use name <- result.try(validate.name(request.name))
  use date <- result.try(validate.date(request.date))

  Ok(
    ctx.milestones.insert(NewMilestone(
      workspace_id: scope.workspace.id,
      name: name,
      date: date,
      description: validate.description(request.description),
      created_by: scope.actor.id,
    )),
  )
}

pub fn delete(ctx: Ctx, scope: Scope, id: String) -> Result(String, ApiError) {
  case ctx.milestones.find_active(scope.workspace.id, id) {
    None -> Error(NotFound)
    Some(milestone_id) -> {
      ctx.milestones.soft_delete(milestone_id, scope.actor.id)
      Ok(milestone_id)
    }
  }
}
