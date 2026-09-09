//// Who is acting, and where. Built by the Elixir plugs (ApiAuth +
//// WorkspaceScope) and passed to every handler — Gleam never re-checks
//// authentication or workspace membership.

pub type Actor {
  Actor(id: String, username: String)
}

pub type Workspace {
  Workspace(id: String, slug: String)
}

pub type Scope {
  Scope(workspace: Workspace, actor: Actor)
}
