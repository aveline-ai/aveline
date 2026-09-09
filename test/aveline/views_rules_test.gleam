import aveline/core/error.{Invalid}
import aveline/views/model.{Bucket, Team, WorkspaceVisible}
import aveline/views/rules
import aveline/views_fixtures as fx
import gleam/option.{None, Some}

pub fn workspace_visible_bucket_admits_everyone_test() {
  assert rules.in_audience(fx.team_bucket(), "anyone", [])
  assert rules.in_audience(
    Bucket(..fx.project_bucket(owner: "user-2"), visibility: WorkspaceVisible),
    "user-1",
    [],
  )
}

pub fn personal_bucket_admits_owner_only_test() {
  let bucket = fx.personal_bucket(owner: "user-1")
  assert rules.in_audience(bucket, "user-1", [])
  assert !rules.in_audience(bucket, "user-2", [])
  // Membership rows never apply to personal buckets.
  assert !rules.in_audience(bucket, "user-2", [bucket.id])
}

pub fn project_bucket_admits_owner_and_members_test() {
  let bucket = fx.project_bucket(owner: "user-2")
  assert rules.in_audience(bucket, "user-2", [])
  assert rules.in_audience(bucket, "user-1", ["b-proj"])
  assert !rules.in_audience(bucket, "user-1", ["b-other"])
}

pub fn private_team_bucket_fails_closed_test() {
  let weird = Bucket(..fx.team_bucket(), visibility: model.Private, kind: Team)
  assert !rules.in_audience(weird, "user-1", ["b-team"])
}

pub fn reserved_bucket_names_test() {
  assert rules.reserved_bucket_name("team")
  assert rules.reserved_bucket_name("personal-arie")
  assert !rules.reserved_bucket_name("teamwork")
  assert !rules.reserved_bucket_name("proj")
}

pub fn normalize_name_test() {
  assert rules.normalize_name("  Tickets ") == "tickets"
}

pub fn validate_slug_name_test() {
  assert rules.validate_slug_name("tickets-2") == Ok("tickets-2")
  assert rules.validate_slug_name("")
    == Error(Invalid("validation_failed", "name can't be blank"))
  assert rules.validate_slug_name("-lead")
    == Error(Invalid(
      "validation_failed",
      "name must be a slug (lowercase letters, digits, dashes)",
    ))
  assert rules.validate_slug_name("has space")
    == Error(Invalid(
      "validation_failed",
      "name must be a slug (lowercase letters, digits, dashes)",
    ))
}

pub fn validate_description_test() {
  assert rules.validate_description(Some("  A fine view.  "))
    == Ok("A fine view.")
  assert rules.validate_description(None)
    == Error(Invalid("validation_failed", "description can't be blank"))
  assert rules.validate_description(Some("   "))
    == Error(Invalid("validation_failed", "description can't be blank"))
  assert rules.validate_description(Some("tiny"))
    == Error(Invalid(
      "validation_failed",
      "description should be at least 6 characters",
    ))
}
