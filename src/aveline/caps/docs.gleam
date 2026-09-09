//// Docs IO capabilities. Built for real in lib/aveline/gleam/caps/docs.ex.
//// stub() panics on use — tests override just the caps in play.
////
//// Fine-grained caps carry typed domain values. The coarse caps
//// (list_docs, read_full, create_doc, replace_blocks, apply_ops, …)
//// return rendered payloads or take block payloads as opaque `Dynamic`
//// values — the search SQL and the block engine stay on the Elixir side.

import aveline/docs/doc_listing.{type DocQuery}
import aveline/docs/doc_meta.{
  type DocMeta, type ShareInfo, type ShareRole, type Visibility,
}
import aveline/docs/doc_writes.{
  type CreateAttrs, type DocPointer, type RestoreFailure, type RestoredDoc,
  type UpdateAttrs, type WriteFailure,
}
import gleam/dynamic.{type Dynamic}
import gleam/option.{type Option, None}

pub type DocsCaps {
  DocsCaps(
    /// Latest live (non-superseded, non-deleted) version by slug.
    get_current_by_slug: fn(String, String) -> Option(DocMeta),
    /// Live share role for (base_doc_id, user_id).
    share_role: fn(String, String) -> Option(ShareRole),
    /// (username, user_id) for every member of the workspace.
    member_usernames: fn(String) -> List(#(String, String)),
    /// Heavy list/search SQL; returns rendered doc summaries (opaque).
    list_docs: fn(DocQuery) -> Dynamic,
    /// DocViews.record: (workspace_id, base_doc_id, user_id, source).
    record_view: fn(String, String, String, String) -> Nil,
    /// Rendered full doc by slug — blocks enriched, charts config-only.
    read_full: fn(String, String, String) -> Option(Dynamic),
    /// The workspace's orientation doc.
    get_orientation: fn(String) -> Option(DocMeta),
    /// The raw chart block with this id on the doc's current version:
    /// (workspace_id, slug, block_id).
    find_chart_block: fn(String, String, String) -> Option(Dynamic),
    /// Run a chart block; Error carries the engine's message.
    run_chart: fn(String, Dynamic) -> Result(Dynamic, String),
    /// Create a doc: (attrs, tags payload, blocks payload).
    create_doc: fn(CreateAttrs, Dynamic, Dynamic) ->
      Result(DocPointer, WriteFailure),
    /// Full-replace edit: (workspace_id, slug, blocks payload, attrs).
    replace_blocks: fn(String, String, Dynamic, UpdateAttrs) ->
      Result(DocPointer, WriteFailure),
    /// Surgical edit: (workspace_id, slug, ops payload, attrs).
    apply_ops: fn(String, String, Dynamic, UpdateAttrs) ->
      Result(DocPointer, WriteFailure),
    /// Soft-delete the current version + broadcast (event is the
    /// handler's job): (workspace_id, slug, deleted_by).
    soft_delete: fn(String, String, String) -> Nil,
    /// Highest-numbered version row for a slug, live or deleted.
    latest_version_by_slug: fn(String, String) -> Option(DocMeta),
    /// Restore a user-deleted doc (broadcast + event inside, matching
    /// the legacy path, which records the event with a nil actor).
    restore: fn(String) -> Result(RestoredDoc, RestoreFailure),
    /// Taken home-page slots as (slot, occupant slug), excluding this
    /// base doc: (workspace_id, base_doc_id).
    pinned_slots: fn(String, String) -> List(#(Int, String)),
    /// Pin/unpin mutation + broadcast + event:
    /// (workspace_id, slug, slot or None to unpin, actor).
    set_pin_slot: fn(String, String, Option(Int), String) -> Nil,
    /// Visibility mutation + broadcast + event:
    /// (workspace_id, slug, visibility, actor).
    set_visibility: fn(String, String, Visibility, String) -> Nil,
    /// Live shares on a base doc, oldest first.
    list_shares: fn(String) -> List(ShareInfo),
    /// Global username -> user id lookup.
    user_id_by_username: fn(String) -> Option(String),
    /// Workspace membership check: (workspace_id, user_id).
    is_member: fn(String, String) -> Bool,
    /// Upsert a share + event: (workspace_id, slug, target, role, actor).
    share_doc: fn(String, String, String, String, String) -> Nil,
    /// Soft-delete a share: (workspace_id, slug, target, actor).
    revoke_share: fn(String, String, String, String) -> Nil,
    /// Rendered version metadata list, newest first (opaque).
    list_versions: fn(String) -> Dynamic,
    /// Rendered full body of one version:
    /// (workspace_id, base_doc_id, version_number, viewer).
    read_version_full: fn(String, String, Int, String) -> Option(Dynamic),
  )
}

pub fn stub() -> DocsCaps {
  DocsCaps(
    get_current_by_slug: fn(_, _) { panic as "stub docs.get_current_by_slug" },
    share_role: fn(_, _) { None },
    member_usernames: fn(_) { panic as "stub docs.member_usernames" },
    list_docs: fn(_) { panic as "stub docs.list_docs" },
    record_view: fn(_, _, _, _) { Nil },
    read_full: fn(_, _, _) { panic as "stub docs.read_full" },
    get_orientation: fn(_) { panic as "stub docs.get_orientation" },
    find_chart_block: fn(_, _, _) { panic as "stub docs.find_chart_block" },
    run_chart: fn(_, _) { panic as "stub docs.run_chart" },
    create_doc: fn(_, _, _) { panic as "stub docs.create_doc" },
    replace_blocks: fn(_, _, _, _) { panic as "stub docs.replace_blocks" },
    apply_ops: fn(_, _, _, _) { panic as "stub docs.apply_ops" },
    soft_delete: fn(_, _, _) { panic as "stub docs.soft_delete" },
    latest_version_by_slug: fn(_, _) {
      panic as "stub docs.latest_version_by_slug"
    },
    restore: fn(_) { panic as "stub docs.restore" },
    pinned_slots: fn(_, _) { panic as "stub docs.pinned_slots" },
    set_pin_slot: fn(_, _, _, _) { panic as "stub docs.set_pin_slot" },
    set_visibility: fn(_, _, _, _) { panic as "stub docs.set_visibility" },
    list_shares: fn(_) { panic as "stub docs.list_shares" },
    user_id_by_username: fn(_) { panic as "stub docs.user_id_by_username" },
    is_member: fn(_, _) { panic as "stub docs.is_member" },
    share_doc: fn(_, _, _, _, _) { panic as "stub docs.share_doc" },
    revoke_share: fn(_, _, _, _) { panic as "stub docs.revoke_share" },
    list_versions: fn(_) { panic as "stub docs.list_versions" },
    read_version_full: fn(_, _, _, _) { panic as "stub docs.read_version_full" },
  )
}
