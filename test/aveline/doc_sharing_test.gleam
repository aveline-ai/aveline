import aveline/caps/docs.{DocsCaps}
import aveline/core/ctx.{Ctx}
import aveline/core/error.{Invalid, NotFound}
import aveline/docs/doc_error.{Api, NotMember}
import aveline/docs/doc_meta.{DocMeta, Private, ShareInfo, Viewer}
import aveline/docs_fixtures
import aveline/fakes
import aveline/handlers/doc_sharing.{
  ShareResponse, SharesResponse, UnshareResponse, VisibilityResponse,
}
import gleam/option.{None, Some}

// ===== set_visibility =====

pub fn visibility_invalid_value_test() {
  let doc = docs_fixtures.doc(owner: "user-1")
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(Some(doc)))

  assert doc_sharing.set_visibility(ctx, fakes.scope(), "notes", "public")
    == Error(
      Api(Invalid(
        "validation_failed",
        "visibility must be one of: private, workspace",
      )),
    )
}

pub fn visibility_orientation_doc_is_always_public_test() {
  let doc = DocMeta(..docs_fixtures.doc(owner: "user-1"), orientation: True)
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(Some(doc)))

  assert doc_sharing.set_visibility(ctx, fakes.scope(), "notes", "private")
    == Error(
      Api(Invalid(
        "validation_failed",
        "the orientation doc is always visible to the whole workspace",
      )),
    )
}

pub fn visibility_owner_only_test() {
  let doc = docs_fixtures.doc(owner: "user-2")
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(Some(doc)))

  assert doc_sharing.set_visibility(ctx, fakes.scope(), "notes", "private")
    == Error(
      Api(Invalid(
        "validation_failed",
        "only the doc's owner can change its visibility",
      )),
    )
}

pub fn visibility_pinned_doc_cannot_go_private_test() {
  let doc = DocMeta(..docs_fixtures.doc(owner: "user-1"), pin_slot: Some(2))
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(Some(doc)))

  assert doc_sharing.set_visibility(ctx, fakes.scope(), "notes", "private")
    == Error(
      Api(Invalid(
        "validation_failed",
        "unpin this doc first: pinned docs are a team surface and can't be private",
      )),
    )
}

pub fn visibility_same_value_is_a_quiet_noop_test() {
  // set_visibility cap stays a panicking stub — reaching Ok proves the
  // no-op path never mutates.
  let doc = docs_fixtures.doc(owner: "user-1")
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(Some(doc)))

  assert doc_sharing.set_visibility(ctx, fakes.scope(), "notes", "workspace")
    == Ok(VisibilityResponse(
      slug: "notes",
      doc_id: "base-1",
      visibility: "workspace",
    ))
}

pub fn visibility_change_mutates_test() {
  let doc = docs_fixtures.doc(owner: "user-1")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs.stub(),
        get_current_by_slug: fn(_, _) { Some(doc) },
        set_visibility: fn(workspace_id, slug, visibility, actor) {
          assert workspace_id == "ws-1"
          assert slug == "notes"
          assert visibility == Private
          assert actor == "user-1"
          Nil
        },
      ),
    )

  assert doc_sharing.set_visibility(ctx, fakes.scope(), "notes", "private")
    == Ok(VisibilityResponse(
      slug: "notes",
      doc_id: "base-1",
      visibility: "private",
    ))
}

// ===== shares =====

pub fn shares_readable_doc_lists_live_shares_test() {
  let doc = docs_fixtures.doc(owner: "user-2")
  let share =
    ShareInfo(
      username: Some("bo"),
      role: "viewer",
      granted_by: Some("arie"),
      granted_at: "2026-01-01T00:00:00Z",
    )
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs.stub(),
        get_current_by_slug: fn(_, _) { Some(doc) },
        list_shares: fn(base_doc_id) {
          assert base_doc_id == "base-1"
          [share]
        },
      ),
    )

  assert doc_sharing.shares(ctx, fakes.scope(), "notes")
    == Ok(
      SharesResponse(
        slug: "notes",
        doc_id: "base-1",
        visibility: "workspace",
        shares: [share],
      ),
    )
}

pub fn shares_private_doc_hidden_from_non_shared_member_test() {
  let doc = docs_fixtures.private_doc(owner: "user-2")
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(Some(doc)))

  assert doc_sharing.shares(ctx, fakes.scope(), "notes") == Error(NotFound)
}

// ===== share =====

fn owned_doc_ctx() -> ctx.Ctx {
  let doc = DocMeta(..docs_fixtures.doc(owner: "user-1"), visibility: Private)
  Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(Some(doc)))
}

pub fn share_unknown_username_is_not_member_test() {
  let ctx = owned_doc_ctx()
  let ctx =
    Ctx(..ctx, docs: DocsCaps(..ctx.docs, user_id_by_username: fn(_) { None }))

  assert doc_sharing.share(ctx, fakes.scope(), "notes", "ghost", None)
    == Error(NotMember)
}

pub fn share_invalid_role_test() {
  let ctx = owned_doc_ctx()
  let ctx =
    Ctx(
      ..ctx,
      docs: DocsCaps(..ctx.docs, user_id_by_username: fn(_) { Some("u2") }),
    )

  assert doc_sharing.share(ctx, fakes.scope(), "notes", "bo", Some("admin"))
    == Error(
      Api(Invalid("validation_failed", "role must be one of: viewer, editor")),
    )
}

pub fn share_owner_only_test() {
  let doc = docs_fixtures.doc(owner: "user-2")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs_fixtures.docs_returning(Some(doc)),
        user_id_by_username: fn(_) { Some("u3") },
      ),
    )

  assert doc_sharing.share(ctx, fakes.scope(), "notes", "bo", None)
    == Error(
      Api(Invalid("validation_failed", "only the doc's owner can share it")),
    )
}

pub fn share_with_owner_is_rejected_test() {
  let ctx = owned_doc_ctx()
  let ctx =
    Ctx(
      ..ctx,
      docs: DocsCaps(..ctx.docs, user_id_by_username: fn(_) { Some("user-1") }),
    )

  assert doc_sharing.share(ctx, fakes.scope(), "notes", "arie", None)
    == Error(
      Api(Invalid("validation_failed", "the owner already has full access")),
    )
}

pub fn share_with_non_member_is_rejected_test() {
  let ctx = owned_doc_ctx()
  let ctx =
    Ctx(
      ..ctx,
      docs: DocsCaps(
        ..ctx.docs,
        user_id_by_username: fn(_) { Some("u2") },
        is_member: fn(_, _) { False },
      ),
    )

  assert doc_sharing.share(ctx, fakes.scope(), "notes", "bo", None)
    == Error(
      Api(Invalid(
        "validation_failed",
        "that user is not a member of this workspace",
      )),
    )
}

pub fn share_defaults_to_viewer_and_upserts_test() {
  let ctx = owned_doc_ctx()
  let ctx =
    Ctx(
      ..ctx,
      docs: DocsCaps(
        ..ctx.docs,
        user_id_by_username: fn(username) {
          assert username == "bo"
          Some("u2")
        },
        is_member: fn(workspace_id, user_id) {
          assert workspace_id == "ws-1"
          assert user_id == "u2"
          True
        },
        share_doc: fn(_, slug, target, role, actor) {
          assert slug == "notes"
          assert target == "u2"
          assert role == "viewer"
          assert actor == "user-1"
          Nil
        },
      ),
    )

  assert doc_sharing.share(ctx, fakes.scope(), "notes", "bo", None)
    == Ok(ShareResponse(
      slug: "notes",
      doc_id: "base-1",
      username: "bo",
      role: "viewer",
    ))
}

// ===== unshare =====

pub fn unshare_unknown_username_is_not_member_test() {
  let ctx = owned_doc_ctx()
  let ctx =
    Ctx(..ctx, docs: DocsCaps(..ctx.docs, user_id_by_username: fn(_) { None }))

  assert doc_sharing.unshare(ctx, fakes.scope(), "notes", "ghost")
    == Error(NotMember)
}

pub fn unshare_owner_only_test() {
  let doc = docs_fixtures.doc(owner: "user-2")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs_fixtures.docs_returning(Some(doc)),
        user_id_by_username: fn(_) { Some("u3") },
      ),
    )

  assert doc_sharing.unshare(ctx, fakes.scope(), "notes", "bo")
    == Error(
      Api(Invalid("validation_failed", "only the doc's owner can revoke shares")),
    )
}

pub fn unshare_without_live_share_is_rejected_test() {
  let ctx = owned_doc_ctx()
  let ctx =
    Ctx(
      ..ctx,
      docs: DocsCaps(
        ..ctx.docs,
        user_id_by_username: fn(_) { Some("u2") },
        share_role: fn(_, _) { None },
      ),
    )

  assert doc_sharing.unshare(ctx, fakes.scope(), "notes", "bo")
    == Error(
      Api(Invalid(
        "validation_failed",
        "no live share for that user on this doc",
      )),
    )
}

pub fn unshare_revokes_live_share_test() {
  let ctx = owned_doc_ctx()
  let ctx =
    Ctx(
      ..ctx,
      docs: DocsCaps(
        ..ctx.docs,
        user_id_by_username: fn(_) { Some("u2") },
        share_role: fn(base_doc_id, user_id) {
          assert base_doc_id == "base-1"
          assert user_id == "u2"
          Some(Viewer)
        },
        revoke_share: fn(_, slug, target, actor) {
          assert slug == "notes"
          assert target == "u2"
          assert actor == "user-1"
          Nil
        },
      ),
    )

  assert doc_sharing.unshare(ctx, fakes.scope(), "notes", "bo")
    == Ok(UnshareResponse(slug: "notes", doc_id: "base-1", username: "bo"))
}
