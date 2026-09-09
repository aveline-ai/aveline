//// Docs-domain test fixtures.

import aveline/caps/docs.{type DocsCaps, DocsCaps}
import aveline/docs/doc_meta.{type DocMeta, DocMeta, Private, WorkspaceVisible}
import gleam/option.{type Option, None}

pub fn doc(owner owner_id: String) -> DocMeta {
  DocMeta(
    id: "doc-v3",
    base_doc_id: "base-1",
    slug: "notes",
    title: "Notes",
    visibility: WorkspaceVisible,
    owner_id: owner_id,
    orientation: False,
    version_number: 3,
    pin_slot: None,
  )
}

pub fn private_doc(owner owner_id: String) -> DocMeta {
  DocMeta(..doc(owner: owner_id), visibility: Private)
}

pub fn docs_returning(doc: Option(DocMeta)) -> DocsCaps {
  DocsCaps(..docs.stub(), get_current_by_slug: fn(_, _) { doc })
}
