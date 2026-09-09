//// Workspaces IO capabilities. Built for real in
//// lib/aveline/gleam/caps/workspaces.ex; keep the two in lockstep
//// (tag + field order).

import aveline/workspaces/workspace_info.{type WorkspaceInfo}
import gleam/option.{type Option}

pub type CreateWorkspaceError {
  /// Unique-constraint conflict on the slug.
  SlugTaken
}

pub type WorkspacesCaps {
  WorkspacesCaps(
    /// Non-deleted workspaces the user is a member of, by name.
    list_for_user: fn(String) -> List(WorkspaceInfo),
    /// Non-deleted workspace by slug.
    get_active_by_slug: fn(String) -> Option(WorkspaceInfo),
    /// (workspace_id, user_id) membership check.
    is_member: fn(String, String) -> Bool,
    /// Create a workspace: (name, slug, creator_id). Template seeding
    /// (tags, orientation doc, built-in source) stays Elixir-side.
    create: fn(String, String, String) ->
      Result(WorkspaceInfo, CreateWorkspaceError),
    /// Idempotently add the creator as a member: (workspace_id, user_id).
    ensure_member: fn(String, String) -> Nil,
  )
}

pub fn stub() -> WorkspacesCaps {
  WorkspacesCaps(
    list_for_user: fn(_) { panic as "stub workspaces.list_for_user" },
    get_active_by_slug: fn(_) { panic as "stub workspaces.get_active_by_slug" },
    is_member: fn(_, _) { panic as "stub workspaces.is_member" },
    create: fn(_, _, _) { panic as "stub workspaces.create" },
    ensure_member: fn(_, _) { panic as "stub workspaces.ensure_member" },
  )
}
