import aveline/caps/views.{ViewsCaps}
import aveline/core/ctx.{Ctx}
import aveline/core/error.{Invalid, NotFound}
import aveline/fakes
import aveline/handlers/views as handlers
import aveline/views/model.{Bucket, View, ViewWrite}
import aveline/views/view_config.{ConfigObject, NoConfig, RawString}
import aveline/views_fixtures as fx
import gleam/option.{None, Some}

fn with_caps(caps) {
  Ctx(..fakes.ctx(), views: caps)
}

// ===== index =====

pub fn index_filters_to_audience_test() {
  let mine = fx.view_in(fx.personal_bucket(owner: "user-1"), owner: "user-1")
  let theirs =
    View(
      ..fx.view_in(fx.personal_bucket(owner: "user-2"), owner: "user-2"),
      id: "v-2",
      name: "theirs",
    )
  let team =
    View(..fx.view_in(fx.team_bucket(), owner: "user-2"), id: "v-3", name: "z")
  let member_project =
    View(
      ..fx.view_in(fx.project_bucket(owner: "user-2"), owner: "user-2"),
      id: "v-4",
      name: "proj-view",
    )
  let orphan = View(..mine, id: "v-5", name: "orphan", bucket: None)

  let caps =
    ViewsCaps(
      ..views.stub(),
      list_views: fn(_) { [mine, theirs, team, member_project, orphan] },
      member_bucket_ids: fn(_) { ["b-proj"] },
    )

  assert handlers.index(with_caps(caps), fakes.scope())
    == [mine, team, member_project]
}

// ===== create =====

pub fn create_defaults_to_personal_bucket_test() {
  let bucket = fx.personal_bucket(owner: "user-1")
  let out = fx.view_in(bucket, owner: "user-1")
  let caps =
    ViewsCaps(
      ..fx.caps_returning_view(None),
      ensure_personal_bucket: fn(ws, user) {
        assert ws == "ws-1"
        assert user == "user-1"
        bucket
      },
      insert_view: fn(write) {
        assert write
          == ViewWrite(
            workspace_id: "ws-1",
            base_view_id: None,
            version_number: 1,
            name: "tickets",
            description: "All the tickets.",
            config: model.empty_config(),
            pinned: False,
            bucket_id: bucket.id,
            owner_id: "user-1",
            created_by_id: "user-1",
          )
        Ok(out)
      },
    )

  let request =
    handlers.CreateViewRequest(
      name: "  Tickets ",
      description: Some("All the tickets."),
      config: NoConfig,
      bucket: handlers.DefaultBucket,
    )

  assert handlers.create(with_caps(caps), fakes.scope(), request) == Ok(out)
}

pub fn create_into_team_bucket_test() {
  let bucket = fx.team_bucket()
  let out = fx.view_in(bucket, owner: "user-1")
  let caps =
    ViewsCaps(
      ..fx.caps_returning_view(None),
      ensure_team_bucket: fn(_) { bucket },
      insert_view: fn(write: model.ViewWrite) {
        assert write.bucket_id == "b-team"
        Ok(out)
      },
    )

  let request =
    handlers.CreateViewRequest(
      name: "tickets",
      description: Some("All the tickets."),
      config: NoConfig,
      bucket: handlers.TeamBucket,
    )

  assert handlers.create(with_caps(caps), fakes.scope(), request) == Ok(out)
}

pub fn create_into_unusable_named_bucket_is_not_found_test() {
  let caps = fx.caps_returning_bucket(Some(fx.project_bucket(owner: "user-2")))

  let request =
    handlers.CreateViewRequest(
      name: "tickets",
      description: Some("All the tickets."),
      config: NoConfig,
      bucket: handlers.NamedBucket("proj"),
    )

  assert handlers.create(with_caps(caps), fakes.scope(), request)
    == Error(NotFound)
}

pub fn create_invalid_name_test() {
  let caps =
    ViewsCaps(..fx.caps_returning_view(None), ensure_personal_bucket: fn(_, _) {
      fx.personal_bucket(owner: "user-1")
    })

  let request =
    handlers.CreateViewRequest(
      name: "Bad Name!",
      description: Some("All the tickets."),
      config: NoConfig,
      bucket: handlers.DefaultBucket,
    )

  assert handlers.create(with_caps(caps), fakes.scope(), request)
    == Error(Invalid(
      "validation_failed",
      "name must be a slug (lowercase letters, digits, dashes)",
    ))
}

pub fn create_missing_description_test() {
  let caps =
    ViewsCaps(..fx.caps_returning_view(None), ensure_personal_bucket: fn(_, _) {
      fx.personal_bucket(owner: "user-1")
    })

  let request =
    handlers.CreateViewRequest(
      name: "tickets",
      description: None,
      config: NoConfig,
      bucket: handlers.DefaultBucket,
    )

  assert handlers.create(with_caps(caps), fakes.scope(), request)
    == Error(Invalid("validation_failed", "description can't be blank"))
}

pub fn create_name_conflict_test() {
  let caps =
    ViewsCaps(
      ..fx.caps_returning_view(None),
      ensure_personal_bucket: fn(_, _) { fx.personal_bucket(owner: "user-1") },
      insert_view: fn(_) { Error(Nil) },
    )

  let request =
    handlers.CreateViewRequest(
      name: "tickets",
      description: Some("All the tickets."),
      config: NoConfig,
      bucket: handlers.DefaultBucket,
    )

  assert handlers.create(with_caps(caps), fakes.scope(), request)
    == Error(Invalid("validation_failed", "already exists"))
}

pub fn create_config_validated_against_workspace_test() {
  let caps =
    ViewsCaps(
      ..fx.caps_returning_view(None),
      ensure_personal_bucket: fn(_, _) { fx.personal_bucket(owner: "user-1") },
      unknown_tags: fn(_, tags) { tags },
    )

  let request =
    handlers.CreateViewRequest(
      name: "tickets",
      description: Some("All the tickets."),
      config: ConfigObject(
        view_config.RawConfig(
          ..view_config.empty_raw(),
          tags: view_config.TagsList(["ghost"]),
        ),
      ),
      bucket: handlers.DefaultBucket,
    )

  assert handlers.create(with_caps(caps), fakes.scope(), request)
    == Error(Invalid(
      "unknown_tags",
      "One or more tags aren't defined in this workspace yet. Create them first.",
    ))
}

// ===== update =====

pub fn update_missing_view_is_not_found_test() {
  let request =
    handlers.UpdateViewRequest(
      name: "nope",
      new_name: None,
      description: None,
      config: NoConfig,
    )

  assert handlers.update(
      with_caps(fx.caps_returning_view(None)),
      fakes.scope(),
      request,
    )
    == Error(NotFound)
}

pub fn update_foreign_personal_view_is_not_found_test() {
  let view = fx.view_in(fx.personal_bucket(owner: "user-2"), owner: "user-2")
  let request =
    handlers.UpdateViewRequest(
      name: "tickets",
      new_name: None,
      description: None,
      config: NoConfig,
    )

  assert handlers.update(
      with_caps(fx.caps_returning_view(Some(view))),
      fakes.scope(),
      request,
    )
    == Error(NotFound)
}

pub fn update_mints_next_version_test() {
  let view =
    View(
      ..fx.view_in(fx.team_bucket(), owner: "user-2"),
      version_number: 3,
      pinned: True,
      config: model.ViewConfig(..model.empty_config(), group_by: Some("status")),
    )
  let out = View(..view, id: "v-next", version_number: 4, bucket: None)
  let caps =
    ViewsCaps(
      ..fx.caps_returning_view(Some(view)),
      replace_version: fn(id, write) {
        assert id == "v-1"
        assert write
          == ViewWrite(
            workspace_id: "ws-1",
            base_view_id: Some("base-v1"),
            version_number: 4,
            name: "renamed",
            description: "A better description.",
            config: model.ViewConfig(
              ..model.empty_config(),
              group_by: Some("status"),
              edited: Some("7d"),
            ),
            pinned: True,
            bucket_id: "b-team",
            // Ownership never moves with edits; the actor is created_by.
            owner_id: "user-2",
            created_by_id: "user-1",
          )
        Ok(out)
      },
    )

  let request =
    handlers.UpdateViewRequest(
      name: "tickets",
      new_name: Some(" Renamed "),
      description: Some("A better description."),
      config: ConfigObject(
        view_config.RawConfig(
          ..view_config.empty_raw(),
          edited: RawString("7d"),
        ),
      ),
    )

  assert handlers.update(with_caps(caps), fakes.scope(), request) == Ok(out)
}

pub fn update_name_conflict_test() {
  let view = fx.view_in(fx.team_bucket(), owner: "user-1")
  let caps =
    ViewsCaps(..fx.caps_returning_view(Some(view)), replace_version: fn(_, _) {
      Error(Nil)
    })

  let request =
    handlers.UpdateViewRequest(
      name: "tickets",
      new_name: Some("taken"),
      description: None,
      config: NoConfig,
    )

  assert handlers.update(with_caps(caps), fakes.scope(), request)
    == Error(Invalid("validation_failed", "already exists"))
}

// ===== delete / restore =====

pub fn delete_soft_deletes_with_actor_test() {
  let view = fx.view_in(fx.team_bucket(), owner: "user-2")
  let caps =
    ViewsCaps(
      ..fx.caps_returning_view(Some(view)),
      soft_delete_view: fn(id, user) {
        assert id == "v-1"
        assert user == "user-1"
        Nil
      },
    )

  assert handlers.delete(with_caps(caps), fakes.scope(), "tickets") == Ok(Nil)
}

pub fn delete_missing_is_not_found_test() {
  assert handlers.delete(
      with_caps(fx.caps_returning_view(None)),
      fakes.scope(),
      "tickets",
    )
    == Error(NotFound)
}

pub fn restore_missing_is_not_user_deleted_test() {
  let caps = ViewsCaps(..views.stub(), find_restorable: fn(_, _) { None })

  assert handlers.restore(with_caps(caps), fakes.scope(), "tickets")
    == Error(Invalid(
      "not_user_deleted",
      "Doc was not user-deleted (it's the current live version or was superseded by a new version).",
    ))
}

pub fn restore_clears_deletion_test() {
  let deleted =
    View(..fx.view_in(fx.team_bucket(), owner: "user-2"), bucket: None)
  let caps =
    ViewsCaps(
      ..views.stub(),
      find_restorable: fn(ws, name) {
        assert ws == "ws-1"
        assert name == "tickets"
        Some(deleted)
      },
      restore_view: fn(id) {
        assert id == "v-1"
        deleted
      },
    )

  assert handlers.restore(with_caps(caps), fakes.scope(), "tickets")
    == Ok(deleted)
}

// ===== pin =====

pub fn pin_and_unpin_update_in_place_test() {
  let view = fx.view_in(fx.team_bucket(), owner: "user-2")
  let caps = fn(expected: Bool) {
    ViewsCaps(
      ..fx.caps_returning_view(Some(view)),
      set_view_pinned: fn(id, pinned) {
        assert id == "v-1"
        assert pinned == expected
        View(..view, pinned: pinned)
      },
    )
  }

  assert handlers.set_pinned(
      with_caps(caps(True)),
      fakes.scope(),
      "tickets",
      True,
    )
    == Ok(View(..view, pinned: True))
  assert handlers.set_pinned(
      with_caps(caps(False)),
      fakes.scope(),
      "tickets",
      False,
    )
    == Ok(view)
}

pub fn pin_hidden_view_is_not_found_test() {
  let view = fx.view_in(fx.personal_bucket(owner: "user-2"), owner: "user-2")

  assert handlers.set_pinned(
      with_caps(fx.caps_returning_view(Some(view))),
      fakes.scope(),
      "tickets",
      True,
    )
    == Error(NotFound)
}

// ===== move =====

pub fn move_requires_view_ownership_test() {
  let view = fx.view_in(fx.team_bucket(), owner: "user-2")
  let caps =
    ViewsCaps(..fx.caps_returning_view(Some(view)), ensure_team_bucket: fn(_) {
      fx.team_bucket()
    })

  assert handlers.move(
      with_caps(caps),
      fakes.scope(),
      "tickets",
      handlers.TeamBucket,
    )
    == Error(Invalid("validation_failed", "only the view's owner can move it"))
}

pub fn move_rejects_cross_workspace_bucket_test() {
  let view = fx.view_in(fx.team_bucket(), owner: "user-1")
  let foreign = Bucket(..fx.team_bucket(), workspace_id: "ws-2")
  let caps =
    ViewsCaps(..fx.caps_returning_view(Some(view)), ensure_team_bucket: fn(_) {
      foreign
    })

  assert handlers.move(
      with_caps(caps),
      fakes.scope(),
      "tickets",
      handlers.TeamBucket,
    )
    == Error(Invalid(
      "validation_failed",
      "that bucket belongs to another workspace",
    ))
}

pub fn move_into_bucket_outside_audience_test() {
  // A workspace-visible project bucket is fetchable by name, but the
  // mover still must be in its audience once it flips private... here we
  // reach the audience branch via a private bucket owned by another user
  // that the fetch let through as workspace-visible-then-changed is not
  // reproducible; instead exercise the guard directly with "yours"-style
  // resolution returning a foreign personal bucket.
  let view = fx.view_in(fx.team_bucket(), owner: "user-1")
  let foreign_personal = fx.personal_bucket(owner: "user-2")
  let caps =
    ViewsCaps(
      ..fx.caps_returning_view(Some(view)),
      ensure_personal_bucket: fn(_, _) { foreign_personal },
    )

  assert handlers.move(
      with_caps(caps),
      fakes.scope(),
      "tickets",
      handlers.YoursBucket,
    )
    == Error(Invalid("validation_failed", "you aren't in that bucket"))
}

pub fn move_updates_bucket_in_place_test() {
  let view = fx.view_in(fx.personal_bucket(owner: "user-1"), owner: "user-1")
  let team = fx.team_bucket()
  let moved = View(..view, bucket: Some(team))
  let caps =
    ViewsCaps(
      ..fx.caps_returning_view(Some(view)),
      ensure_team_bucket: fn(_) { team },
      move_view: fn(id, bucket_id) {
        assert id == "v-1"
        assert bucket_id == "b-team"
        moved
      },
    )

  assert handlers.move(
      with_caps(caps),
      fakes.scope(),
      "tickets",
      handlers.TeamBucket,
    )
    == Ok(moved)
}

pub fn move_resolves_bucket_before_view_lookup_test() {
  // Parity quirk: "yours" lazily creates the personal bucket even when
  // the view lookup then fails — the stub would panic if the handler
  // skipped straight to the (missing) view.
  let caps =
    ViewsCaps(..fx.caps_returning_view(None), ensure_personal_bucket: fn(_, _) {
      fx.personal_bucket(owner: "user-1")
    })

  assert handlers.move(
      with_caps(caps),
      fakes.scope(),
      "nope",
      handlers.YoursBucket,
    )
    == Error(NotFound)
}
