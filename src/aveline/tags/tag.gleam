//// Tag domain types (mirrors Aveline.Tags.Tag rows at the boundary).
//// A tag is workspace-scoped, versioned like docs (edits insert a new
//// row sharing `base_tag_id`), and soft-deletable.

import gleam/option.{type Option}

pub type Tag {
  Tag(
    id: String,
    base_tag_id: String,
    version_number: Int,
    slug: String,
    description: String,
    color: Option(String),
    sort_key: Option(String),
    /// Mechanism, not intent: a newer version row replaced this one.
    /// Live reads never return superseded rows; only the restore path
    /// can ever see one (defensively — supersede and user-delete are
    /// mutually exclusive in practice).
    superseded: Bool,
    /// ISO8601 inserted_at, for display only.
    created_at: String,
  )
}

/// A tag row plus usage stats for the management surfaces.
pub type TagStats {
  TagStats(tag: Tag, doc_count: Int, last_used_at: Option(String))
}

/// A fully validated + normalized field set for a new tag row — v1 on
/// create, or the next version on edit. Only rules.validate_fields
/// should build one.
pub type TagFields {
  TagFields(
    slug: String,
    description: String,
    color: Option(String),
    sort_key: Option(String),
  )
}
