//// GET /api/me — who am I + workspaces I belong to. Ports
//// MeController.show. Not workspace-scoped, so it takes the bare Actor.

import aveline/accounts/user_info.{type UserInfo}
import aveline/core/ctx.{type Ctx}
import aveline/core/scope.{type Actor}
import aveline/workspaces/workspace_info.{type WorkspaceInfo}

pub type MeResponse {
  MeResponse(user: UserInfo, workspaces: List(WorkspaceInfo))
}

pub fn show(ctx: Ctx, actor: Actor) -> MeResponse {
  MeResponse(
    user: ctx.keys.get_user(actor.id),
    workspaces: ctx.workspaces.list_for_user(actor.id),
  )
}
