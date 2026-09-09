import aveline/caps/workspaces.{SlugTaken, WorkspacesCaps} as workspaces_caps
import aveline/core/ctx.{Ctx}
import aveline/core/error.{Forbidden, Invalid}
import aveline/fakes
import aveline/handlers/workspaces.{CreateRequest} as handler
import aveline/workspaces/workspace_info.{type WorkspaceInfo, WorkspaceInfo}
import gleam/option.{None, Some}
import gleam/string

fn actor() {
  fakes.scope().actor
}

fn ws(slug: String) -> WorkspaceInfo {
  WorkspaceInfo(
    id: "ws-9",
    slug: slug,
    name: "Acme",
    created_at: "2026-09-01T00:00:00Z",
  )
}

fn validation_failed() {
  Error(Invalid("validation_failed", "Validation failed."))
}

pub fn index_lists_memberships_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      workspaces: WorkspacesCaps(
        ..workspaces_caps.stub(),
        list_for_user: fn(user_id) {
          assert user_id == "user-1"
          [ws("acme")]
        },
      ),
    )

  assert handler.index(ctx, actor()) == [ws("acme")]
}

pub fn show_missing_workspace_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      workspaces: WorkspacesCaps(
        ..workspaces_caps.stub(),
        get_active_by_slug: fn(_) { None },
      ),
    )

  assert handler.show(ctx, actor(), "nope")
    == Error(Invalid("workspace_not_found", "Workspace not found."))
}

pub fn show_non_member_is_forbidden_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      workspaces: WorkspacesCaps(
        ..workspaces_caps.stub(),
        get_active_by_slug: fn(_) { Some(ws("acme")) },
        is_member: fn(_, _) { False },
      ),
    )

  assert handler.show(ctx, actor(), "acme")
    == Error(Forbidden("You don't have access to this resource."))
}

pub fn show_member_sees_workspace_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      workspaces: WorkspacesCaps(
        ..workspaces_caps.stub(),
        get_active_by_slug: fn(_) { Some(ws("acme")) },
        is_member: fn(ws_id, user_id) {
          assert ws_id == "ws-9"
          assert user_id == "user-1"
          True
        },
      ),
    )

  assert handler.show(ctx, actor(), "acme") == Ok(ws("acme"))
}

pub fn create_requires_a_name_test() {
  assert handler.create(fakes.ctx(), actor(), CreateRequest(None, None))
    == validation_failed()
  assert handler.create(fakes.ctx(), actor(), CreateRequest(Some(""), None))
    == validation_failed()
}

pub fn create_caps_name_length_test() {
  let long = string.repeat("a", 201)
  assert handler.create(
      fakes.ctx(),
      actor(),
      CreateRequest(Some(long), Some("ok")),
    )
    == validation_failed()
}

pub fn create_rejects_a_bad_slug_test() {
  assert handler.create(
      fakes.ctx(),
      actor(),
      CreateRequest(Some("Acme"), Some("bad slug")),
    )
    == validation_failed()
}

pub fn create_cannot_derive_a_slug_from_symbols_test() {
  assert handler.create(fakes.ctx(), actor(), CreateRequest(Some("!!!"), None))
    == validation_failed()
}

pub fn create_downcases_a_given_slug_test() {
  let ctx = creating_ctx(expected_slug: "acme-team")

  assert handler.create(
      ctx,
      actor(),
      CreateRequest(Some("Acme"), Some("ACME-Team")),
    )
    == Ok(ws("acme-team"))
}

pub fn create_derives_slug_from_name_when_omitted_test() {
  let ctx = creating_ctx(expected_slug: "my-team")

  assert handler.create(ctx, actor(), CreateRequest(Some("My Team!"), None))
    == Ok(ws("my-team"))
}

pub fn create_maps_slug_conflicts_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      workspaces: WorkspacesCaps(..workspaces_caps.stub(), create: fn(_, _, _) {
        Error(SlugTaken)
      }),
    )

  assert handler.create(ctx, actor(), CreateRequest(Some("Acme"), Some("acme")))
    == Error(Invalid("slug_taken", "Slug already in use."))
}

fn creating_ctx(expected_slug expected: String) -> ctx.Ctx {
  Ctx(
    ..fakes.ctx(),
    workspaces: WorkspacesCaps(
      ..workspaces_caps.stub(),
      create: fn(name, slug, creator) {
        assert name != ""
        assert slug == expected
        assert creator == "user-1"
        Ok(ws(slug))
      },
      ensure_member: fn(ws_id, user_id) {
        assert ws_id == "ws-9"
        assert user_id == "user-1"
        Nil
      },
    ),
  )
}
