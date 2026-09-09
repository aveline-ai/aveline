//// Doc access rules, pure. The share lookup is passed in as a thunk so
//// callers only pay the query when visibility actually requires it.

import aveline/docs/doc_meta.{type DocMeta, type ShareRole, Editor, Private}
import gleam/option.{type Option, Some}

/// May this workspace member read the doc? (Membership already checked.)
pub fn can_read(
  doc: DocMeta,
  user_id: String,
  share_role: fn() -> Option(ShareRole),
) -> Bool {
  case doc.visibility {
    Private -> doc.owner_id == user_id || share_role() != option.None
    _ -> True
  }
}

/// May this workspace member edit the doc? (Membership already checked.)
pub fn can_edit(
  doc: DocMeta,
  user_id: String,
  share_role: fn() -> Option(ShareRole),
) -> Bool {
  case doc.visibility {
    Private -> doc.owner_id == user_id || share_role() == Some(Editor)
    _ -> True
  }
}
