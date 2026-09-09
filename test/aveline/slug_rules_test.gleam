import aveline/slug
import gleam/option.{None, Some}
import gleam/string

pub fn derive_lowercases_and_dashes_test() {
  assert slug.derive_from("My Team!") == Some("my-team")
}

pub fn derive_collapses_runs_and_trims_test() {
  assert slug.derive_from("  --Weird__  Name--  ") == Some("weird-name")
}

pub fn derive_passes_clean_slugs_through_test() {
  assert slug.derive_from("acme-2") == Some("acme-2")
}

pub fn derive_nothing_left_is_none_test() {
  assert slug.derive_from("!!!") == None
  assert slug.derive_from("") == None
}

pub fn derive_caps_at_sixty_and_retrims_test() {
  // 59 a's + "!b" -> "aaa…a-b" (61 chars) -> sliced to 60 -> trailing
  // dash trimmed again.
  let name = string.repeat("a", 59) <> "!b"
  assert slug.derive_from(name) == Some(string.repeat("a", 59))
}

pub fn validate_format_test() {
  assert slug.validate("abc-123")
  assert slug.validate("a")
  assert !slug.validate("")
  assert !slug.validate("-abc")
  assert !slug.validate("UPPER")
  assert !slug.validate("has space")
  assert !slug.validate(string.repeat("a", 61))
  assert slug.validate(string.repeat("a", 60))
}
