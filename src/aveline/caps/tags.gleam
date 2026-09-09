//// Tags IO capabilities. Built for real in lib/aveline/gleam/caps/tags.ex;
//// keep the two in lockstep (tag + field order).

import aveline/tags/tag.{type Tag, type TagFields, type TagStats}
import gleam/option.{type Option}

/// Tag activity events. Which event fires (and with which numbers) is
/// handler decision logic; the free-form JSON `data` payload each one
/// becomes is assembled Elixir-side (events keep their legacy shape,
/// including payloads EventAttrs can't carry).
pub type TagEvent {
  TagCreated(slug: String, description: String)
  TagUpdated(slug: String, version: Int)
  TagRenamed(from: String, to: String, version: Int, affected: Int)
  TagDeleted(slug: String)
  TagRestored(slug: String)
}

pub type TagsCaps {
  TagsCaps(
    /// Live tag (not superseded, not deleted) by (workspace_id, slug).
    get: fn(String, String) -> Option(Tag),
    /// The user-deleted row for (workspace_id, slug) — the restore target.
    get_deleted: fn(String, String) -> Option(Tag),
    /// Coarse read: tag rows + per-doc usage stats in the workspace tag
    /// order (sort_key override, alphabetical otherwise).
    list_with_stats: fn(String) -> List(TagStats),
    /// Insert a v1 tag row: (workspace_id, fields, actor_user_id).
    /// Error(Nil) = slug uniqueness conflict.
    insert: fn(String, TagFields, String) -> Result(Tag, Nil),
    /// Atomically supersede `current`, insert the next version row, and
    /// (when fields.slug differs) cascade the rename across every doc
    /// carrying the old slug. Returns the new row + affected doc count.
    /// Error(Nil) = slug uniqueness conflict (lost race).
    insert_version: fn(Tag, TagFields, String) -> Result(#(Tag, Int), Nil),
    /// Soft-delete: (tag_id, actor_user_id) sets deleted_at/deleted_by.
    soft_delete: fn(String, String) -> Nil,
    /// Clear deleted_at/deleted_by on a tag row by id.
    undelete: fn(String) -> Nil,
    /// Record a tag activity event: (workspace_id, actor_user_id, event).
    record_event: fn(String, String, TagEvent) -> Nil,
  )
}

pub fn stub() -> TagsCaps {
  TagsCaps(
    get: fn(_, _) { panic as "stub tags.get" },
    get_deleted: fn(_, _) { panic as "stub tags.get_deleted" },
    list_with_stats: fn(_) { panic as "stub tags.list_with_stats" },
    insert: fn(_, _, _) { panic as "stub tags.insert" },
    insert_version: fn(_, _, _) { panic as "stub tags.insert_version" },
    soft_delete: fn(_, _) { panic as "stub tags.soft_delete" },
    undelete: fn(_) { panic as "stub tags.undelete" },
    record_event: fn(_, _, _) { panic as "stub tags.record_event" },
  )
}
