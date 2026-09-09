//// Views-domain test fixtures. The scope actor is fakes.scope()'s
//// "user-1" in workspace "ws-1".

import aveline/caps/views.{type ViewsCaps, ViewsCaps}
import aveline/views/model.{
  type Bucket, type View, Bucket, Personal, Private, Project, Team, View,
  WorkspaceVisible,
}
import gleam/option.{type Option, None, Some}

pub fn team_bucket() -> Bucket {
  Bucket(
    id: "b-team",
    workspace_id: "ws-1",
    name: "team",
    kind: Team,
    visibility: WorkspaceVisible,
    owner_id: None,
  )
}

pub fn personal_bucket(owner owner_id: String) -> Bucket {
  Bucket(
    id: "b-personal-" <> owner_id,
    workspace_id: "ws-1",
    name: "personal-" <> owner_id,
    kind: Personal,
    visibility: Private,
    owner_id: Some(owner_id),
  )
}

pub fn project_bucket(owner owner_id: String) -> Bucket {
  Bucket(
    id: "b-proj",
    workspace_id: "ws-1",
    name: "proj",
    kind: Project,
    visibility: Private,
    owner_id: Some(owner_id),
  )
}

pub fn view_in(bucket: Bucket, owner owner_id: String) -> View {
  View(
    id: "v-1",
    workspace_id: "ws-1",
    base_view_id: "base-v1",
    version_number: 1,
    name: "tickets",
    description: "All the tickets.",
    config: model.empty_config(),
    pinned: False,
    owner_id: owner_id,
    bucket: Some(bucket),
    created_at: "2026-01-01T00:00:00.000000Z",
  )
}

/// Stubbed caps with the lookups every by-name endpoint hits: the view,
/// the actor's project-bucket memberships (none), tag checks that pass.
pub fn caps_returning_view(view: Option(View)) -> ViewsCaps {
  ViewsCaps(
    ..views.stub(),
    get_current_by_name: fn(_, _) { view },
    member_bucket_ids: fn(_) { [] },
    unknown_tags: fn(_, _) { [] },
    scope_has_tags: fn(_, _) { True },
  )
}

pub fn caps_returning_bucket(bucket: Option(Bucket)) -> ViewsCaps {
  ViewsCaps(
    ..views.stub(),
    get_bucket: fn(_, _) { bucket },
    member_bucket_ids: fn(_) { [] },
  )
}
