import aveline/core/error.{Invalid}
import aveline/tags/rules
import aveline/tags/tag.{TagFields}
import gleam/option.{None, Some}
import gleam/string

// ===== Slug format =====

pub fn plain_slug_valid_test() {
  assert rules.valid_tag_slug("runbook")
  assert rules.valid_tag_slug("a")
  assert rules.valid_tag_slug("2024-q3")
  assert rules.valid_tag_slug("a-b-c")
}

pub fn scoped_slug_valid_test() {
  assert rules.valid_tag_slug("status:todo")
  assert rules.valid_tag_slug("area:api-keys")
}

pub fn bad_slugs_rejected_test() {
  assert !rules.valid_tag_slug("")
  assert !rules.valid_tag_slug("-leading")
  assert !rules.valid_tag_slug("Upper")
  assert !rules.valid_tag_slug("has space")
  assert !rules.valid_tag_slug("a:b:c")
  assert !rules.valid_tag_slug("scope:")
  assert !rules.valid_tag_slug(":value")
  assert !rules.valid_tag_slug("émoji")
}

pub fn slug_part_length_capped_at_60_test() {
  assert rules.valid_slug_part(string.repeat("a", 60))
  assert !rules.valid_slug_part(string.repeat("a", 61))
}

pub fn normalize_slug_trims_and_downcases_test() {
  assert rules.normalize_slug("  Deploys ") == "deploys"
}

// ===== Colors =====

pub fn color_validation_test() {
  assert rules.valid_color("#e09150")
  assert !rules.valid_color("e09150")
  assert !rules.valid_color("#e0915")
  assert !rules.valid_color("#e091500")
  assert !rules.valid_color("#gggggg")
  assert !rules.valid_color("green")
}

// ===== validate_fields =====

pub fn valid_fields_pass_and_normalize_test() {
  assert rules.validate_fields(
      "deploys",
      "  Shipping things.  ",
      Some(" #123ABC "),
      Some("00-first"),
    )
    == Ok(TagFields(
      slug: "deploys",
      description: "Shipping things.",
      color: Some("#123abc"),
      sort_key: Some("00-first"),
    ))
}

pub fn malformed_slug_is_tag_invalid_test() {
  assert rules.validate_fields("Bad Slug", "Shipping things.", None, None)
    == Error(Invalid(
      "tag_invalid",
      "Tag slug must be lowercase letters, digits, hyphens.",
    ))
}

pub fn malformed_slug_wins_over_other_field_errors_test() {
  // Mirrors the changeset summary: a slug format error takes priority
  // over a bad description.
  assert rules.validate_fields("Bad Slug", "meh", None, None)
    == Error(Invalid(
      "tag_invalid",
      "Tag slug must be lowercase letters, digits, hyphens.",
    ))
}

pub fn blank_slug_is_validation_failed_test() {
  assert rules.validate_fields("", "Shipping things.", None, None)
    == Error(Invalid("validation_failed", "Validation failed."))
}

pub fn short_description_rejected_test() {
  assert rules.validate_fields("deploys", "meh", None, None)
    == Error(Invalid("validation_failed", "Validation failed."))
}

pub fn blank_description_rejected_test() {
  assert rules.validate_fields("deploys", "   ", None, None)
    == Error(Invalid("validation_failed", "Validation failed."))
}

pub fn long_description_rejected_test() {
  assert rules.validate_fields("deploys", string.repeat("x", 281), None, None)
    == Error(Invalid("validation_failed", "Validation failed."))
}

pub fn description_boundaries_accepted_test() {
  assert rules.validate_fields("deploys", string.repeat("x", 6), None, None)
    == Ok(TagFields(
      slug: "deploys",
      description: string.repeat("x", 6),
      color: None,
      sort_key: None,
    ))
  let assert Ok(_) =
    rules.validate_fields("deploys", string.repeat("x", 280), None, None)
}

pub fn bad_color_rejected_test() {
  assert rules.validate_fields(
      "deploys",
      "Shipping things.",
      Some("green"),
      None,
    )
    == Error(Invalid("validation_failed", "Validation failed."))
}

// ===== Scoped tags =====

pub fn scope_of_test() {
  assert rules.scope_of("status:todo") == Some("status")
  assert rules.scope_of("runbook") == None
  assert rules.scope_of("a:b:c") == Some("a")
}

pub fn value_of_test() {
  assert rules.value_of("status:todo") == "todo"
  assert rules.value_of("runbook") == "runbook"
  assert rules.value_of("a:b:c") == "b:c"
}

pub fn no_scope_conflict_when_scopes_distinct_test() {
  assert rules.ensure_no_scope_conflict([
      "runbook",
      "status:todo",
      "area:api",
    ])
    == Ok(Nil)
}

pub fn duplicate_same_tag_is_not_a_conflict_test() {
  assert rules.ensure_no_scope_conflict(["status:todo", "status:todo"])
    == Ok(Nil)
}

pub fn two_tags_in_one_scope_conflict_test() {
  assert rules.ensure_no_scope_conflict(["status:done", "status:todo", "x"])
    == Error(#("status", ["status:done", "status:todo"]))
}

pub fn empty_set_has_no_conflict_test() {
  assert rules.ensure_no_scope_conflict([]) == Ok(Nil)
}

// ===== unknown_tags =====

pub fn unknown_tags_test() {
  assert rules.unknown_tags([], ["a"]) == Ok(Nil)
  assert rules.unknown_tags(["a", "b"], ["a", "b", "c"]) == Ok(Nil)
  assert rules.unknown_tags(["a", "x", "x", "y"], ["a"]) == Error(["x", "y"])
}
