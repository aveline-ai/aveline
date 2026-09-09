import aveline/caps/views.{ViewsCaps}
import aveline/core/ctx.{Ctx}
import aveline/core/error.{Invalid, NotFound}
import aveline/fakes
import aveline/handlers/view_buckets as handlers
import aveline/views/model.{
  Bucket, Personal, Private, Project, Team, WorkspaceVisible,
}
import aveline/views_fixtures as fx
import gleam/option.{None, Some}

fn with_caps(caps) {
  Ctx(..fakes.ctx(), views: caps)
}

// ===== index =====

pub fn index_filters_and_summarizes_test() {
  let team = fx.team_bucket()
  let mine = fx.personal_bucket(owner: "user-1")
  let theirs = fx.personal_bucket(owner: "user-2")
  let member_project = fx.project_bucket(owner: "user-2")
  let hidden_project =
    Bucket(..fx.project_bucket(owner: "user-3"), id: "b-hidden", name: "hidden")

  let caps =
    ViewsCaps(
      ..views.stub(),
      list_buckets: fn(_) {
        [mine, theirs, member_project, hidden_project, team]
      },
      member_bucket_ids: fn(_) { ["b-proj"] },
      list_bucket_member_usernames: fn(bucket_id) {
        assert bucket_id == "b-proj"
        [Some("arie"), None]
      },
      get_username: fn(user_id) {
        case user_id {
          "user-1" -> Some("arie")
          "user-2" -> Some("bea")
          _ -> None
        }
      },
    )

  assert handlers.index(with_caps(caps), fakes.scope())
    == [
      handlers.BucketSummary(
        name: "personal-user-1",
        kind: Personal,
        visibility: Private,
        owner: Some("arie"),
        members: [],
      ),
      handlers.BucketSummary(
        name: "proj",
        kind: Project,
        visibility: Private,
        owner: Some("bea"),
        members: [Some("arie"), None],
      ),
      handlers.BucketSummary(
        name: "team",
        kind: Team,
        visibility: WorkspaceVisible,
        owner: None,
        members: [],
      ),
    ]
}

// ===== create =====

pub fn create_rejects_reserved_names_test() {
  let expected =
    Error(Invalid("validation_failed", "that bucket name is reserved"))
  let ctx = with_caps(views.stub())

  assert handlers.create(ctx, fakes.scope(), " Team ", None) == expected
  assert handlers.create(ctx, fakes.scope(), "personal-arie", None) == expected
}

pub fn create_rejects_bad_visibility_test() {
  assert handlers.create(
      with_caps(views.stub()),
      fakes.scope(),
      "proj",
      Some("public"),
    )
    == Error(Invalid("validation_failed", "visibility is invalid"))
}

pub fn create_rejects_bad_name_test() {
  assert handlers.create(
      with_caps(views.stub()),
      fakes.scope(),
      "Bad Name",
      None,
    )
    == Error(Invalid(
      "validation_failed",
      "name must be a slug (lowercase letters, digits, dashes)",
    ))
  assert handlers.create(with_caps(views.stub()), fakes.scope(), "  ", None)
    == Error(Invalid("validation_failed", "name can't be blank"))
}

pub fn create_defaults_to_private_test() {
  let bucket =
    Bucket(..fx.project_bucket(owner: "user-1"), id: "b-new", name: "proj")
  let caps =
    ViewsCaps(
      ..views.stub(),
      insert_bucket: fn(ws, name, owner, visibility) {
        assert ws == "ws-1"
        assert name == "proj"
        assert owner == "user-1"
        assert visibility == Private
        Ok(bucket)
      },
      list_bucket_member_usernames: fn(_) { [] },
      get_username: fn(_) { Some("arie") },
    )

  assert handlers.create(with_caps(caps), fakes.scope(), " Proj ", None)
    == Ok(
      handlers.BucketSummary(
        name: "proj",
        kind: Project,
        visibility: Private,
        owner: Some("arie"),
        members: [],
      ),
    )
}

pub fn create_workspace_visibility_test() {
  let bucket =
    Bucket(
      ..fx.project_bucket(owner: "user-1"),
      id: "b-new",
      name: "open",
      visibility: WorkspaceVisible,
    )
  let caps =
    ViewsCaps(
      ..views.stub(),
      insert_bucket: fn(_, _, _, visibility) {
        assert visibility == WorkspaceVisible
        Ok(bucket)
      },
      list_bucket_member_usernames: fn(_) { [] },
      get_username: fn(_) { Some("arie") },
    )

  let assert Ok(summary) =
    handlers.create(with_caps(caps), fakes.scope(), "open", Some("workspace"))
  assert summary.visibility == WorkspaceVisible
}

pub fn create_name_conflict_test() {
  let caps =
    ViewsCaps(..views.stub(), insert_bucket: fn(_, _, _, _) { Error(Nil) })

  assert handlers.create(with_caps(caps), fakes.scope(), "proj", None)
    == Error(Invalid("validation_failed", "already exists"))
}

// ===== fetch/audience =====

pub fn hidden_bucket_is_not_found_test() {
  // Private project bucket owned by someone else, actor not a member.
  let caps = fx.caps_returning_bucket(Some(fx.project_bucket(owner: "user-2")))

  assert handlers.delete(with_caps(caps), fakes.scope(), "proj")
    == Error(NotFound)
  assert handlers.set_visibility(
      with_caps(caps),
      fakes.scope(),
      "proj",
      "private",
    )
    == Error(NotFound)
}

pub fn missing_bucket_is_not_found_test() {
  let caps = fx.caps_returning_bucket(None)

  assert handlers.delete(with_caps(caps), fakes.scope(), "nope")
    == Error(NotFound)
}

// ===== set_visibility =====

pub fn set_visibility_rejects_unknown_value_test() {
  let caps = fx.caps_returning_bucket(Some(fx.project_bucket(owner: "user-1")))

  assert handlers.set_visibility(with_caps(caps), fakes.scope(), "proj", "open")
    == Error(Invalid(
      "validation_failed",
      "visibility must be one of: private, workspace",
    ))
}

pub fn set_visibility_project_only_test() {
  let caps = fx.caps_returning_bucket(Some(fx.team_bucket()))

  assert handlers.set_visibility(
      with_caps(caps),
      fakes.scope(),
      "team",
      "private",
    )
    == Error(Invalid(
      "validation_failed",
      "team is always workspace-visible and personal is always private; only project buckets change",
    ))
}

pub fn set_visibility_owner_only_test() {
  let bucket =
    Bucket(..fx.project_bucket(owner: "user-2"), visibility: WorkspaceVisible)
  let caps = fx.caps_returning_bucket(Some(bucket))

  assert handlers.set_visibility(
      with_caps(caps),
      fakes.scope(),
      "proj",
      "private",
    )
    == Error(Invalid(
      "validation_failed",
      "only the bucket's owner can change its visibility",
    ))
}

pub fn set_visibility_noop_skips_write_test() {
  // No set_bucket_visibility override: the stub would panic on a write.
  let caps =
    ViewsCaps(
      ..fx.caps_returning_bucket(Some(fx.project_bucket(owner: "user-1"))),
      list_bucket_member_usernames: fn(_) { [] },
      get_username: fn(_) { Some("arie") },
    )

  let assert Ok(summary) =
    handlers.set_visibility(with_caps(caps), fakes.scope(), "proj", "private")
  assert summary.visibility == Private
}

pub fn set_visibility_updates_test() {
  let bucket = fx.project_bucket(owner: "user-1")
  let caps =
    ViewsCaps(
      ..fx.caps_returning_bucket(Some(bucket)),
      set_bucket_visibility: fn(id, visibility) {
        assert id == "b-proj"
        assert visibility == WorkspaceVisible
        Bucket(..bucket, visibility: WorkspaceVisible)
      },
      list_bucket_member_usernames: fn(_) { [] },
      get_username: fn(_) { Some("arie") },
    )

  let assert Ok(summary) =
    handlers.set_visibility(with_caps(caps), fakes.scope(), "proj", "workspace")
  assert summary.visibility == WorkspaceVisible
}

// ===== delete =====

pub fn delete_project_only_test() {
  let caps = fx.caps_returning_bucket(Some(fx.personal_bucket(owner: "user-1")))

  assert handlers.delete(with_caps(caps), fakes.scope(), "personal-user-1")
    == Error(Invalid("validation_failed", "only project buckets can be deleted"))
}

pub fn delete_owner_only_test() {
  let bucket =
    Bucket(..fx.project_bucket(owner: "user-2"), visibility: WorkspaceVisible)
  let caps = fx.caps_returning_bucket(Some(bucket))

  assert handlers.delete(with_caps(caps), fakes.scope(), "proj")
    == Error(Invalid(
      "validation_failed",
      "only the bucket's owner can delete it",
    ))
}

pub fn delete_requires_empty_bucket_test() {
  let caps =
    ViewsCaps(
      ..fx.caps_returning_bucket(Some(fx.project_bucket(owner: "user-1"))),
      bucket_has_live_views: fn(_) { True },
    )

  assert handlers.delete(with_caps(caps), fakes.scope(), "proj")
    == Error(Invalid(
      "validation_failed",
      "move or delete this bucket's views first",
    ))
}

pub fn delete_soft_deletes_test() {
  let caps =
    ViewsCaps(
      ..fx.caps_returning_bucket(Some(fx.project_bucket(owner: "user-1"))),
      bucket_has_live_views: fn(_) { False },
      soft_delete_bucket: fn(id) {
        assert id == "b-proj"
        Nil
      },
    )

  assert handlers.delete(with_caps(caps), fakes.scope(), "proj") == Ok(Nil)
}

// ===== add_member =====

fn member_caps(bucket) {
  ViewsCaps(
    ..fx.caps_returning_bucket(Some(bucket)),
    find_user_id_by_username: fn(username) {
      case username {
        "bea" -> Some("user-2")
        "cal" -> Some("user-3")
        _ -> None
      }
    },
  )
}

pub fn add_member_unknown_user_test() {
  let caps = member_caps(fx.project_bucket(owner: "user-1"))

  assert handlers.add_member(with_caps(caps), fakes.scope(), "proj", "ghost")
    == Error(Invalid("not_member", "User is not a member of this workspace."))
}

pub fn add_member_project_only_test() {
  let caps = member_caps(fx.team_bucket())

  assert handlers.add_member(with_caps(caps), fakes.scope(), "team", "bea")
    == Error(Invalid(
      "validation_failed",
      "only project buckets take members; team is everyone and personal is just you",
    ))
}

pub fn add_member_owner_only_test() {
  let bucket =
    Bucket(..fx.project_bucket(owner: "user-2"), visibility: WorkspaceVisible)

  assert handlers.add_member(
      with_caps(member_caps(bucket)),
      fakes.scope(),
      "proj",
      "cal",
    )
    == Error(Invalid(
      "validation_failed",
      "only the bucket's owner can add members",
    ))
}

pub fn add_member_owner_already_in_test() {
  let bucket =
    Bucket(..fx.project_bucket(owner: "user-1"), owner_id: Some("user-2"))
  let bucket = Bucket(..bucket, owner_id: Some("user-1"))
  let caps =
    ViewsCaps(..member_caps(bucket), find_user_id_by_username: fn(_) {
      Some("user-1")
    })

  assert handlers.add_member(with_caps(caps), fakes.scope(), "proj", "arie")
    == Error(Invalid("validation_failed", "the owner is already in the bucket"))
}

pub fn add_member_requires_workspace_membership_test() {
  let caps =
    ViewsCaps(
      ..member_caps(fx.project_bucket(owner: "user-1")),
      is_workspace_member: fn(_, _) { False },
    )

  assert handlers.add_member(with_caps(caps), fakes.scope(), "proj", "bea")
    == Error(Invalid(
      "validation_failed",
      "that user is not a member of this workspace",
    ))
}

pub fn add_member_already_in_test() {
  let caps =
    ViewsCaps(
      ..member_caps(fx.project_bucket(owner: "user-1")),
      is_workspace_member: fn(_, _) { True },
      find_live_membership: fn(_, _) { Some("m-1") },
    )

  assert handlers.add_member(with_caps(caps), fakes.scope(), "proj", "bea")
    == Error(Invalid("validation_failed", "that user is already in the bucket"))
}

pub fn add_member_inserts_test() {
  let caps =
    ViewsCaps(
      ..member_caps(fx.project_bucket(owner: "user-1")),
      is_workspace_member: fn(ws, user) {
        assert ws == "ws-1"
        assert user == "user-2"
        True
      },
      find_live_membership: fn(_, _) { None },
      insert_bucket_member: fn(bucket_id, user_id, added_by) {
        assert bucket_id == "b-proj"
        assert user_id == "user-2"
        assert added_by == "user-1"
        Nil
      },
    )

  assert handlers.add_member(with_caps(caps), fakes.scope(), "proj", "bea")
    == Ok(Nil)
}

// ===== remove_member =====

pub fn remove_member_owner_only_test() {
  let bucket =
    Bucket(..fx.project_bucket(owner: "user-2"), visibility: WorkspaceVisible)

  assert handlers.remove_member(
      with_caps(member_caps(bucket)),
      fakes.scope(),
      "proj",
      "cal",
    )
    == Error(Invalid(
      "validation_failed",
      "only the bucket's owner can remove members",
    ))
}

pub fn remove_member_not_in_bucket_test() {
  let caps =
    ViewsCaps(
      ..member_caps(fx.project_bucket(owner: "user-1")),
      find_live_membership: fn(_, _) { None },
    )

  assert handlers.remove_member(with_caps(caps), fakes.scope(), "proj", "bea")
    == Error(Invalid("validation_failed", "that user is not in the bucket"))
}

pub fn remove_member_soft_deletes_test() {
  let caps =
    ViewsCaps(
      ..member_caps(fx.project_bucket(owner: "user-1")),
      find_live_membership: fn(_, _) { Some("m-9") },
      soft_delete_membership: fn(id) {
        assert id == "m-9"
        Nil
      },
    )

  assert handlers.remove_member(with_caps(caps), fakes.scope(), "proj", "bea")
    == Ok(Nil)
}
