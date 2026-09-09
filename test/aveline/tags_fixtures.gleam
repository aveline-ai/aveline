//// Tags-domain test fixtures.

import aveline/caps/tags.{type TagsCaps}
import aveline/tags/tag.{type Tag, Tag}
import gleam/option.{type Option, None}

pub fn tag(slug slug: String) -> Tag {
  Tag(
    id: "tag-v1",
    base_tag_id: "base-tag-1",
    version_number: 1,
    slug: slug,
    description: "Shipping things.",
    color: None,
    sort_key: None,
    superseded: False,
    created_at: "2026-01-01T00:00:00.000000Z",
  )
}

/// Every cap panics (same as the stub) — tests override the caps in
/// play via record-update syntax:
///   TagsCaps(..tags_fixtures.caps(), get: fn(_, _) { ... })
pub fn caps() -> TagsCaps {
  tags.stub()
}

/// Caps whose live `get` always answers `found` and whose event
/// recording is a no-op — the base for most write-path tests.
pub fn caps_with_get(found: Option(Tag)) -> TagsCaps {
  tags.TagsCaps(..caps(), get: fn(_, _) { found }, record_event: fn(_, _, _) {
    Nil
  })
}
