//// The view/bucket fields handlers make decisions on. Deliberately not
//// the whole rows — timestamps handlers don't branch on stay Elixir-side
//// (created_at crosses as a display ISO8601 string).

import gleam/option.{type Option, None}

pub type BucketKind {
  Team
  Personal
  Project
}

pub type BucketVisibility {
  Private
  WorkspaceVisible
}

/// A bucket: the space a view lives in and the unit views are shared at.
/// Audience by kind: team = every workspace member, personal = the
/// owner, project = owner + live binary members.
pub type Bucket {
  Bucket(
    id: String,
    workspace_id: String,
    name: String,
    kind: BucketKind,
    visibility: BucketVisibility,
    owner_id: Option(String),
  )
}

/// A view's config, normalized to the known knobs (the shape the View
/// changeset stores). Free-form/unknown keys are dropped, as before.
pub type ViewConfig {
  ViewConfig(
    tags: List(String),
    group_by: Option(String),
    sub_group_by: Option(String),
    edited: Option(String),
    sort: Option(String),
    icon: Option(String),
  )
}

pub fn empty_config() -> ViewConfig {
  ViewConfig(
    tags: [],
    group_by: None,
    sub_group_by: None,
    edited: None,
    sort: None,
    icon: None,
  )
}

/// The current row of a view. `bucket` is present when the Elixir side
/// had it preloaded — response shapes depend on this (edits and restores
/// answer with a nil bucket, exactly like the pre-port endpoints).
pub type View {
  View(
    id: String,
    workspace_id: String,
    base_view_id: String,
    version_number: Int,
    name: String,
    description: String,
    config: ViewConfig,
    pinned: Bool,
    owner_id: String,
    bucket: Option(Bucket),
    created_at: String,
  )
}

/// Everything needed to insert a view row. `base_view_id: None` means
/// mint a fresh base id (a create); edits pass the current base id.
pub type ViewWrite {
  ViewWrite(
    workspace_id: String,
    base_view_id: Option(String),
    version_number: Int,
    name: String,
    description: String,
    config: ViewConfig,
    pinned: Bool,
    bucket_id: String,
    owner_id: String,
    created_by_id: String,
  )
}
