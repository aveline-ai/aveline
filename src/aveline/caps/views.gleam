//// Views IO capabilities. Built for real in lib/aveline/gleam/caps/views.ex;
//// keep the two in lockstep (tag + field order).

import aveline/views/model.{
  type Bucket, type BucketVisibility, type View, type ViewWrite,
}
import gleam/option.{type Option}

pub type ViewsCaps {
  ViewsCaps(
    /// Live (not superseded, not deleted) views of a workspace, ordered
    /// pinned-first then name. Bucket attached only when itself live.
    list_views: fn(String) -> List(View),
    /// Current live view by (workspace_id, name), bucket attached (raw
    /// preload — a soft-deleted bucket still rides along, as before).
    get_current_by_name: fn(String, String) -> Option(View),
    /// Current-but-user-deleted view by (workspace_id, name); no bucket.
    find_restorable: fn(String, String) -> Option(View),
    /// Insert a view row; Error(Nil) = live-name uniqueness conflict.
    /// Returns the row with its bucket attached.
    insert_view: fn(ViewWrite) -> Result(View, Nil),
    /// Transactionally supersede view `id` and insert the next version.
    /// Error(Nil) = uniqueness conflict (rolled back). No bucket on the
    /// returned row (the old endpoint answered with a nil bucket).
    replace_version: fn(String, ViewWrite) -> Result(View, Nil),
    /// Clear deleted_at/deleted_by on a view row; returns it, no bucket.
    restore_view: fn(String) -> View,
    /// Soft-delete a view: (view_id, deleted_by_user_id).
    soft_delete_view: fn(String, String) -> Nil,
    /// In-place pin flag update; returns the row with bucket attached.
    set_view_pinned: fn(String, Bool) -> View,
    /// In-place bucket move: (view_id, bucket_id); returns the row with
    /// the new bucket attached.
    move_view: fn(String, String) -> View,
    /// Live buckets of a workspace, ordered kind then name.
    list_buckets: fn(String) -> List(Bucket),
    /// Live bucket by (workspace_id, name).
    get_bucket: fn(String, String) -> Option(Bucket),
    /// Get-or-create the workspace's team bucket.
    ensure_team_bucket: fn(String) -> Bucket,
    /// Get-or-create (workspace_id, user_id)'s personal bucket.
    ensure_personal_bucket: fn(String, String) -> Bucket,
    /// Insert a project bucket: (workspace_id, name, owner_id,
    /// visibility). Error(Nil) = live-name uniqueness conflict.
    insert_bucket: fn(String, String, String, BucketVisibility) ->
      Result(Bucket, Nil),
    /// In-place visibility update by bucket id; returns the row.
    set_bucket_visibility: fn(String, BucketVisibility) -> Bucket,
    soft_delete_bucket: fn(String) -> Nil,
    /// Does the bucket hold any live views?
    bucket_has_live_views: fn(String) -> Bool,
    /// Live member usernames of a bucket, oldest first (None for a
    /// member row whose user is gone).
    list_bucket_member_usernames: fn(String) -> List(Option(String)),
    /// Insert a membership row: (bucket_id, user_id, added_by_id).
    insert_bucket_member: fn(String, String, String) -> Nil,
    /// Live membership row id for (bucket_id, user_id), if any.
    find_live_membership: fn(String, String) -> Option(String),
    /// Soft-delete a membership row by id.
    soft_delete_membership: fn(String) -> Nil,
    /// Ids of buckets `user_id` holds a live membership in.
    member_bucket_ids: fn(String) -> List(String),
    /// Username for a user id, if the user exists.
    get_username: fn(String) -> Option(String),
    find_user_id_by_username: fn(String) -> Option(String),
    /// Is (workspace_id, user_id) a workspace member?
    is_workspace_member: fn(String, String) -> Bool,
    /// Subset of (workspace_id, slugs) not defined as live tags.
    unknown_tags: fn(String, List(String)) -> List(String),
    /// Does tag scope (workspace_id, scope) have any members?
    scope_has_tags: fn(String, String) -> Bool,
  )
}

pub fn stub() -> ViewsCaps {
  ViewsCaps(
    list_views: fn(_) { panic as "stub views.list_views" },
    get_current_by_name: fn(_, _) { panic as "stub views.get_current_by_name" },
    find_restorable: fn(_, _) { panic as "stub views.find_restorable" },
    insert_view: fn(_) { panic as "stub views.insert_view" },
    replace_version: fn(_, _) { panic as "stub views.replace_version" },
    restore_view: fn(_) { panic as "stub views.restore_view" },
    soft_delete_view: fn(_, _) { panic as "stub views.soft_delete_view" },
    set_view_pinned: fn(_, _) { panic as "stub views.set_view_pinned" },
    move_view: fn(_, _) { panic as "stub views.move_view" },
    list_buckets: fn(_) { panic as "stub views.list_buckets" },
    get_bucket: fn(_, _) { panic as "stub views.get_bucket" },
    ensure_team_bucket: fn(_) { panic as "stub views.ensure_team_bucket" },
    ensure_personal_bucket: fn(_, _) {
      panic as "stub views.ensure_personal_bucket"
    },
    insert_bucket: fn(_, _, _, _) { panic as "stub views.insert_bucket" },
    set_bucket_visibility: fn(_, _) {
      panic as "stub views.set_bucket_visibility"
    },
    soft_delete_bucket: fn(_) { panic as "stub views.soft_delete_bucket" },
    bucket_has_live_views: fn(_) { panic as "stub views.bucket_has_live_views" },
    list_bucket_member_usernames: fn(_) {
      panic as "stub views.list_bucket_member_usernames"
    },
    insert_bucket_member: fn(_, _, _) {
      panic as "stub views.insert_bucket_member"
    },
    find_live_membership: fn(_, _) { panic as "stub views.find_live_membership" },
    soft_delete_membership: fn(_) {
      panic as "stub views.soft_delete_membership"
    },
    member_bucket_ids: fn(_) { panic as "stub views.member_bucket_ids" },
    get_username: fn(_) { panic as "stub views.get_username" },
    find_user_id_by_username: fn(_) {
      panic as "stub views.find_user_id_by_username"
    },
    is_workspace_member: fn(_, _) { panic as "stub views.is_workspace_member" },
    unknown_tags: fn(_, _) { panic as "stub views.unknown_tags" },
    scope_has_tags: fn(_, _) { panic as "stub views.scope_has_tags" },
  )
}
