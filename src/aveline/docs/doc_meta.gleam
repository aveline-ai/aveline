//// The doc fields handlers make decisions on. This is deliberately not
//// the whole Doc row — blocks stay on the Elixir side until block logic
//// is ported.

import gleam/option.{type Option}

pub type Visibility {
  Private
  WorkspaceVisible
}

pub type ShareRole {
  Viewer
  Editor
}

pub type DocMeta {
  DocMeta(
    id: String,
    base_doc_id: String,
    slug: String,
    title: String,
    visibility: Visibility,
    owner_id: String,
    orientation: Bool,
    version_number: Int,
    pin_slot: Option(Int),
  )
}

/// The wire string for a visibility ("private" | "workspace").
pub fn visibility_string(visibility: Visibility) -> String {
  case visibility {
    Private -> "private"
    WorkspaceVisible -> "workspace"
  }
}

/// One live share row as the shares endpoint reports it. `granted_at`
/// is an ISO8601 string (display value, per the boundary conventions).
pub type ShareInfo {
  ShareInfo(
    username: Option(String),
    role: String,
    granted_by: Option(String),
    granted_at: String,
  )
}
