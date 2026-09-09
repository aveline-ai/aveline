import aveline/core/error.{Invalid}
import aveline/views/model.{ViewConfig}
import aveline/views/view_config.{
  Absent, BadField, ConfigObject, NoConfig, NotAnObject, Null, RawConfig,
  RawString, TagsAbsent, TagsInvalid, TagsList,
}
import gleam/option.{None, Some}

fn no_unknown(_tags: List(String)) -> List(String) {
  []
}

fn scope_ok(_scope: String) -> Bool {
  True
}

fn validate(param) {
  view_config.apply_and_validate(
    model.empty_config(),
    param,
    no_unknown,
    scope_ok,
  )
}

fn raw(f) {
  ConfigObject(f(view_config.empty_raw()))
}

pub fn not_an_object_test() {
  assert validate(NotAnObject)
    == Error(Invalid("view_invalid", "config must be an object"))
}

pub fn no_config_validates_base_test() {
  assert validate(NoConfig) == Ok(model.empty_config())
}

pub fn unknown_tags_test() {
  let param = raw(fn(r) { RawConfig(..r, tags: TagsList(["ghost"])) })

  assert view_config.apply_and_validate(
      model.empty_config(),
      param,
      fn(tags) { tags },
      scope_ok,
    )
    == Error(Invalid(
      "unknown_tags",
      "One or more tags aren't defined in this workspace yet. Create them first.",
    ))
}

pub fn unknown_tags_outrank_bad_shape_test() {
  // A mixed list still has its string entries existence-checked first.
  let param = raw(fn(r) { RawConfig(..r, tags: TagsInvalid(["ghost"])) })

  assert view_config.apply_and_validate(
      model.empty_config(),
      param,
      fn(tags) { tags },
      scope_ok,
    )
    == Error(Invalid(
      "unknown_tags",
      "One or more tags aren't defined in this workspace yet. Create them first.",
    ))
}

pub fn bad_tags_shape_test() {
  let param = raw(fn(r) { RawConfig(..r, tags: TagsInvalid([])) })

  assert validate(param)
    == Error(Invalid("validation_failed", "tags must be a list of tag slugs"))
}

pub fn group_by_bad_slug_test() {
  let expected =
    Error(Invalid(
      "view_invalid",
      "group_by must be a tag scope (a plain slug like \"status\")",
    ))

  assert validate(raw(fn(r) { RawConfig(..r, group_by: RawString("Bad Cap")) }))
    == expected
  assert validate(raw(fn(r) { RawConfig(..r, group_by: RawString("")) }))
    == expected
  assert validate(raw(fn(r) { RawConfig(..r, group_by: BadField) })) == expected
}

pub fn group_by_empty_scope_test() {
  let param = raw(fn(r) { RawConfig(..r, group_by: RawString("lane")) })

  assert view_config.apply_and_validate(
      model.empty_config(),
      param,
      no_unknown,
      fn(_) { False },
    )
    == Error(Invalid(
      "view_invalid",
      "group_by scope has no tags in this workspace: lane",
    ))
}

pub fn sub_group_by_rules_test() {
  assert validate(raw(fn(r) { RawConfig(..r, sub_group_by: BadField) }))
    == Error(Invalid(
      "validation_failed",
      "sub_group_by must be a tag scope or null",
    ))

  // sub_group_by without (or equal to) group_by is rejected.
  assert validate(
      raw(fn(r) { RawConfig(..r, sub_group_by: RawString("status")) }),
    )
    == Error(Invalid(
      "validation_failed",
      "sub_group_by needs a different group_by scope",
    ))
  assert validate(
      raw(fn(r) {
        RawConfig(
          ..r,
          group_by: RawString("status"),
          sub_group_by: RawString("status"),
        )
      }),
    )
    == Error(Invalid(
      "validation_failed",
      "sub_group_by needs a different group_by scope",
    ))

  let assert Ok(config) =
    validate(
      raw(fn(r) {
        RawConfig(
          ..r,
          group_by: RawString("status"),
          sub_group_by: RawString("lane"),
        )
      }),
    )
  assert config.group_by == Some("status")
  assert config.sub_group_by == Some("lane")
}

pub fn edited_window_test() {
  let expected =
    Error(Invalid(
      "validation_failed",
      "edited must be a window like \"7d\" or \"24h\" (max 365d)",
    ))

  assert validate(raw(fn(r) { RawConfig(..r, edited: RawString("3w")) }))
    == expected
  assert validate(raw(fn(r) { RawConfig(..r, edited: RawString("400d")) }))
    == expected
  assert validate(raw(fn(r) { RawConfig(..r, edited: RawString("0h")) }))
    == expected
  assert validate(raw(fn(r) { RawConfig(..r, edited: BadField) })) == expected

  // Normalized: trimmed, leading zeros dropped.
  let assert Ok(config) =
    validate(raw(fn(r) { RawConfig(..r, edited: RawString(" 07d ")) }))
  assert config.edited == Some("7d")
}

pub fn sort_and_icon_test() {
  assert validate(raw(fn(r) { RawConfig(..r, sort: RawString("kudos")) }))
    == Error(Invalid("validation_failed", "sort must be one of recent, title"))
  assert validate(raw(fn(r) { RawConfig(..r, icon: BadField) }))
    == Error(Invalid("validation_failed", "icon must be a string"))

  let assert Ok(config) =
    validate(
      raw(fn(r) {
        RawConfig(..r, sort: RawString("title"), icon: RawString("🚀"))
      }),
    )
  assert config.sort == Some("title")
  assert config.icon == Some("🚀")
}

pub fn merge_keeps_absent_and_clears_null_test() {
  let base =
    ViewConfig(
      tags: ["ticket"],
      group_by: Some("status"),
      sub_group_by: None,
      edited: Some("7d"),
      sort: Some("recent"),
      icon: None,
    )
  let param =
    ConfigObject(RawConfig(
      tags: TagsAbsent,
      group_by: Absent,
      sub_group_by: Absent,
      edited: Null,
      sort: RawString("title"),
      icon: Absent,
    ))

  assert view_config.apply_and_validate(base, param, no_unknown, scope_ok)
    == Ok(ViewConfig(
      tags: ["ticket"],
      group_by: Some("status"),
      sub_group_by: None,
      edited: None,
      sort: Some("title"),
      icon: None,
    ))
}

pub fn no_config_revalidates_current_test() {
  // An edit without config still re-validates the stored config: a tag
  // soft-deleted since the last edit now fails.
  let base = ViewConfig(..model.empty_config(), tags: ["gone"])

  assert view_config.apply_and_validate(
      base,
      NoConfig,
      fn(tags) { tags },
      scope_ok,
    )
    == Error(Invalid(
      "unknown_tags",
      "One or more tags aren't defined in this workspace yet. Create them first.",
    ))
}
