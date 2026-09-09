import aveline/caps/milestones.{MilestonesCaps} as milestones_caps
import aveline/core/ctx.{Ctx}
import aveline/core/error.{Invalid, NotFound}
import aveline/fakes
import aveline/handlers/milestones.{CreateRequest}
import aveline/milestones/milestone.{Milestone}
import aveline/milestones_fixtures
import gleam/option.{None, Some}
import gleam/string

fn validation_failed() {
  Error(Invalid("validation_failed", "Validation failed."))
}

// ===== index =====

pub fn index_lists_active_milestones_for_the_workspace_test() {
  let listed = [
    milestones_fixtures.milestone(id: "ms-1", name: "v1.4 shipped"),
    milestones_fixtures.milestone(id: "ms-2", name: "pricing change"),
  ]
  let ctx =
    Ctx(
      ..fakes.ctx(),
      milestones: MilestonesCaps(..milestones_caps.stub(), list_active: fn(ws) {
        assert ws == "ws-1"
        listed
      }),
    )

  assert milestones.index(ctx, fakes.scope()) == listed
}

// ===== create =====

fn inserting_ctx() {
  Ctx(
    ..fakes.ctx(),
    milestones: MilestonesCaps(
      ..milestones_caps.stub(),
      insert: fn(new: milestone.NewMilestone) {
        assert new.workspace_id == "ws-1"
        assert new.created_by == "user-1"
        milestones_fixtures.stored(new)
      },
    ),
  )
}

pub fn create_trims_name_and_description_test() {
  let request =
    CreateRequest(
      name: "  v1.4 shipped  ",
      date: Some("2026-07-06"),
      description: Some("  the big one  "),
    )

  assert milestones.create(inserting_ctx(), fakes.scope(), request)
    == Ok(Milestone(
      id: "ms-1",
      name: "v1.4 shipped",
      date: "2026-07-06",
      description: Some("the big one"),
      created_at: "2026-07-06T12:00:00.000000Z",
    ))
}

pub fn create_blank_description_becomes_none_test() {
  let request =
    CreateRequest(
      name: "marker",
      date: Some("2026-07-06"),
      description: Some("   "),
    )

  let assert Ok(created) =
    milestones.create(inserting_ctx(), fakes.scope(), request)
  assert created.description == None
}

pub fn create_missing_description_stays_none_test() {
  let request =
    CreateRequest(name: "marker", date: Some("2026-07-06"), description: None)

  let assert Ok(created) =
    milestones.create(inserting_ctx(), fakes.scope(), request)
  assert created.description == None
}

pub fn create_name_at_length_limit_is_ok_test() {
  let request =
    CreateRequest(
      name: string.repeat("x", 80),
      date: Some("2026-07-06"),
      description: None,
    )

  let assert Ok(_) = milestones.create(inserting_ctx(), fakes.scope(), request)
}

pub fn create_blank_name_is_validation_failed_test() {
  let request =
    CreateRequest(name: "   ", date: Some("2026-07-06"), description: None)

  assert milestones.create(fakes.ctx(), fakes.scope(), request)
    == validation_failed()
}

pub fn create_empty_name_is_validation_failed_test() {
  let request =
    CreateRequest(name: "", date: Some("2026-07-06"), description: None)

  assert milestones.create(fakes.ctx(), fakes.scope(), request)
    == validation_failed()
}

pub fn create_overlong_name_is_validation_failed_test() {
  let request =
    CreateRequest(
      name: string.repeat("x", 81),
      date: Some("2026-07-06"),
      description: None,
    )

  assert milestones.create(fakes.ctx(), fakes.scope(), request)
    == validation_failed()
}

pub fn create_missing_date_is_validation_failed_test() {
  let request = CreateRequest(name: "no date", date: None, description: None)

  assert milestones.create(fakes.ctx(), fakes.scope(), request)
    == validation_failed()
}

pub fn create_non_iso_date_is_validation_failed_test() {
  let request =
    CreateRequest(name: "bad date", date: Some("yesterday"), description: None)

  assert milestones.create(fakes.ctx(), fakes.scope(), request)
    == validation_failed()
}

pub fn create_unpadded_date_is_validation_failed_test() {
  let request =
    CreateRequest(name: "bad date", date: Some("2026-7-6"), description: None)

  assert milestones.create(fakes.ctx(), fakes.scope(), request)
    == validation_failed()
}

pub fn create_calendar_invalid_day_is_validation_failed_test() {
  let request =
    CreateRequest(name: "bad date", date: Some("2026-02-30"), description: None)

  assert milestones.create(fakes.ctx(), fakes.scope(), request)
    == validation_failed()
}

pub fn create_month_thirteen_is_validation_failed_test() {
  let request =
    CreateRequest(name: "bad date", date: Some("2026-13-01"), description: None)

  assert milestones.create(fakes.ctx(), fakes.scope(), request)
    == validation_failed()
}

pub fn create_leap_day_on_leap_year_is_ok_test() {
  let request =
    CreateRequest(name: "leap", date: Some("2024-02-29"), description: None)

  let assert Ok(created) =
    milestones.create(inserting_ctx(), fakes.scope(), request)
  assert created.date == "2024-02-29"
}

pub fn create_leap_day_on_common_year_is_validation_failed_test() {
  let request =
    CreateRequest(name: "leap", date: Some("2025-02-29"), description: None)

  assert milestones.create(fakes.ctx(), fakes.scope(), request)
    == validation_failed()
}

// ===== delete =====

pub fn delete_soft_deletes_the_active_milestone_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      milestones: MilestonesCaps(
        ..milestones_caps.stub(),
        find_active: fn(ws, id) {
          assert ws == "ws-1"
          assert id == "ms-1"
          Some("ms-1")
        },
        soft_delete: fn(id, user_id) {
          assert id == "ms-1"
          assert user_id == "user-1"
          Nil
        },
      ),
    )

  assert milestones.delete(ctx, fakes.scope(), "ms-1") == Ok("ms-1")
}

pub fn delete_unknown_or_deleted_milestone_is_not_found_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      milestones: MilestonesCaps(
        ..milestones_caps.stub(),
        find_active: fn(_, _) { None },
        soft_delete: fn(_, _) {
          panic as "soft_delete must not run when nothing was found"
        },
      ),
    )

  assert milestones.delete(ctx, fakes.scope(), "ms-gone") == Error(NotFound)
}
