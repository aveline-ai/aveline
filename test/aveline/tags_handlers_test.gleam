import aveline/caps/tags.{
  TagCreated, TagDeleted, TagRenamed, TagRestored, TagUpdated, TagsCaps,
}
import aveline/core/ctx.{Ctx}
import aveline/core/error.{Invalid, NotFound}
import aveline/fakes
import aveline/handlers/tags.{Clear, CreateRequest, Keep, Set, UpdateRequest} as handlers
import aveline/tags/tag.{Tag, TagFields, TagStats}
import aveline/tags_fixtures
import gleam/option.{None, Some}

fn with_tags(caps: tags.TagsCaps) -> ctx.Ctx {
  Ctx(..fakes.ctx(), tags: caps)
}

fn create_request(slug slug: String) -> handlers.CreateRequest {
  CreateRequest(
    slug: slug,
    description: "Shipping things.",
    color: None,
    sort_key: None,
  )
}

fn keep_all() -> handlers.UpdateRequest {
  UpdateRequest(new_slug: None, description: None, color: Keep, sort_key: Keep)
}

// ===== index =====

pub fn index_returns_stats_rows_test() {
  let row =
    TagStats(
      tag: tags_fixtures.tag(slug: "deploys"),
      doc_count: 3,
      last_used_at: Some("2026-02-01T00:00:00.000000Z"),
    )
  let ctx =
    with_tags(
      TagsCaps(..tags_fixtures.caps(), list_with_stats: fn(ws_id) {
        assert ws_id == "ws-1"
        [row]
      }),
    )

  assert handlers.index(ctx, fakes.scope()) == [row]
}

// ===== show =====

pub fn show_found_test() {
  let tag = tags_fixtures.tag(slug: "deploys")
  let ctx =
    with_tags(
      TagsCaps(..tags_fixtures.caps(), get: fn(ws_id, slug) {
        assert ws_id == "ws-1"
        assert slug == "deploys"
        Some(tag)
      }),
    )

  assert handlers.show(ctx, fakes.scope(), "deploys") == Ok(tag)
}

pub fn show_missing_is_not_found_test() {
  let ctx = with_tags(TagsCaps(..tags_fixtures.caps(), get: fn(_, _) { None }))

  assert handlers.show(ctx, fakes.scope(), "nope") == Error(NotFound)
}

// ===== create =====

pub fn create_normalizes_inserts_and_records_test() {
  let inserted =
    Tag(..tags_fixtures.tag(slug: "deploys"), color: Some("#123abc"))
  let ctx =
    with_tags(
      TagsCaps(
        ..tags_fixtures.caps(),
        insert: fn(ws_id, fields, actor) {
          assert ws_id == "ws-1"
          assert actor == "user-1"
          assert fields
            == TagFields(
              slug: "deploys",
              description: "Shipping things.",
              color: Some("#123abc"),
              sort_key: None,
            )
          Ok(inserted)
        },
        record_event: fn(ws_id, actor, event) {
          assert ws_id == "ws-1"
          assert actor == "user-1"
          assert event
            == TagCreated(slug: "deploys", description: "Shipping things.")
          Nil
        },
      ),
    )
  let request =
    CreateRequest(
      slug: "  Deploys ",
      description: " Shipping things. ",
      color: Some("#123ABC"),
      sort_key: None,
    )

  assert handlers.create(ctx, fakes.scope(), request) == Ok(inserted)
}

pub fn create_malformed_slug_is_tag_invalid_test() {
  let ctx = with_tags(tags_fixtures.caps())

  assert handlers.create(ctx, fakes.scope(), create_request(slug: "bad slug"))
    == Error(Invalid(
      "tag_invalid",
      "Tag slug must be lowercase letters, digits, hyphens.",
    ))
}

pub fn create_scoped_slug_allowed_test() {
  let inserted = tags_fixtures.tag(slug: "status:todo")
  let ctx =
    with_tags(
      TagsCaps(
        ..tags_fixtures.caps(),
        insert: fn(_, fields: tag.TagFields, _) {
          assert fields.slug == "status:todo"
          Ok(inserted)
        },
        record_event: fn(_, _, _) { Nil },
      ),
    )

  assert handlers.create(
      ctx,
      fakes.scope(),
      create_request(slug: "status:todo"),
    )
    == Ok(inserted)
}

pub fn create_blank_slug_is_validation_failed_test() {
  let ctx = with_tags(tags_fixtures.caps())

  assert handlers.create(ctx, fakes.scope(), create_request(slug: "   "))
    == Error(Invalid("validation_failed", "Validation failed."))
}

pub fn create_short_description_is_validation_failed_test() {
  let ctx = with_tags(tags_fixtures.caps())
  let request =
    CreateRequest(..create_request(slug: "deploys"), description: "meh")

  assert handlers.create(ctx, fakes.scope(), request)
    == Error(Invalid("validation_failed", "Validation failed."))
}

pub fn create_bad_color_is_validation_failed_test() {
  let ctx = with_tags(tags_fixtures.caps())
  let request =
    CreateRequest(..create_request(slug: "deploys"), color: Some("green"))

  assert handlers.create(ctx, fakes.scope(), request)
    == Error(Invalid("validation_failed", "Validation failed."))
}

pub fn create_duplicate_slug_is_validation_failed_test() {
  // Legacy quirk: the composite unique index reported on :workspace_id,
  // so a duplicate create surfaced as plain validation_failed — only
  // update's destination check and restore say slug_taken.
  let ctx =
    with_tags(
      TagsCaps(..tags_fixtures.caps(), insert: fn(_, _, _) { Error(Nil) }),
    )

  assert handlers.create(ctx, fakes.scope(), create_request(slug: "deploys"))
    == Error(Invalid("validation_failed", "Validation failed."))
}

// ===== update =====

pub fn update_missing_tag_is_not_found_test() {
  let ctx = with_tags(TagsCaps(..tags_fixtures.caps(), get: fn(_, _) { None }))

  assert handlers.update(ctx, fakes.scope(), "nope", keep_all())
    == Error(NotFound)
}

pub fn update_noop_returns_current_row_untouched_test() {
  // insert_version and record_event stay stubs — they'd panic if a
  // no-op edit tried to version or log anything.
  let tag = tags_fixtures.tag(slug: "deploys")
  let ctx =
    with_tags(TagsCaps(..tags_fixtures.caps(), get: fn(_, _) { Some(tag) }))
  let request =
    UpdateRequest(
      new_slug: Some(" Deploys "),
      description: Some("  Shipping things.  "),
      color: Keep,
      sort_key: Keep,
    )

  assert handlers.update(ctx, fakes.scope(), "deploys", request) == Ok(tag)
}

pub fn update_rename_to_taken_slug_is_slug_taken_test() {
  let tag = tags_fixtures.tag(slug: "deploys")
  let other = tags_fixtures.tag(slug: "shipping")
  let ctx =
    with_tags(
      TagsCaps(..tags_fixtures.caps(), get: fn(_, slug) {
        case slug {
          "deploys" -> Some(tag)
          "shipping" -> Some(other)
          _ -> None
        }
      }),
    )
  let request = UpdateRequest(..keep_all(), new_slug: Some("shipping"))

  assert handlers.update(ctx, fakes.scope(), "deploys", request)
    == Error(Invalid("slug_taken", "Slug already in use."))
}

pub fn update_rename_versions_cascades_and_records_test() {
  let tag = tags_fixtures.tag(slug: "deploys")
  let v2 = Tag(..tag, id: "tag-v2", version_number: 2, slug: "shipping")
  let ctx =
    with_tags(
      TagsCaps(
        ..tags_fixtures.caps(),
        get: fn(_, slug) {
          case slug {
            "deploys" -> Some(tag)
            _ -> None
          }
        },
        insert_version: fn(current, fields, actor) {
          assert current == tag
          assert actor == "user-1"
          assert fields
            == TagFields(
              slug: "shipping",
              description: "Shipping things.",
              color: None,
              sort_key: None,
            )
          Ok(#(v2, 4))
        },
        record_event: fn(_, _, event) {
          assert event
            == TagRenamed(
              from: "deploys",
              to: "shipping",
              version: 2,
              affected: 4,
            )
          Nil
        },
      ),
    )
  let request = UpdateRequest(..keep_all(), new_slug: Some(" Shipping "))

  assert handlers.update(ctx, fakes.scope(), "deploys", request) == Ok(v2)
}

pub fn update_description_only_records_tag_updated_test() {
  let tag = tags_fixtures.tag(slug: "deploys")
  let v2 =
    Tag(..tag, id: "tag-v2", version_number: 2, description: "Now clearer.")
  let ctx =
    with_tags(
      TagsCaps(
        ..tags_fixtures.caps(),
        get: fn(_, _) { Some(tag) },
        insert_version: fn(_, fields: tag.TagFields, _) {
          assert fields.description == "Now clearer."
          Ok(#(v2, 0))
        },
        record_event: fn(_, _, event) {
          assert event == TagUpdated(slug: "deploys", version: 2)
          Nil
        },
      ),
    )
  let request = UpdateRequest(..keep_all(), description: Some("Now clearer."))

  assert handlers.update(ctx, fakes.scope(), "deploys", request) == Ok(v2)
}

pub fn update_clear_color_and_sort_key_test() {
  let tag =
    Tag(
      ..tags_fixtures.tag(slug: "deploys"),
      color: Some("#123abc"),
      sort_key: Some("00"),
    )
  let v2 =
    Tag(..tag, id: "tag-v2", version_number: 2, color: None, sort_key: None)
  let ctx =
    with_tags(
      TagsCaps(
        ..tags_fixtures.caps(),
        get: fn(_, _) { Some(tag) },
        insert_version: fn(_, fields: tag.TagFields, _) {
          assert fields.color == None
          assert fields.sort_key == None
          Ok(#(v2, 0))
        },
        record_event: fn(_, _, _) { Nil },
      ),
    )
  let request = UpdateRequest(..keep_all(), color: Clear, sort_key: Clear)

  assert handlers.update(ctx, fakes.scope(), "deploys", request) == Ok(v2)
}

pub fn update_color_case_change_still_versions_test() {
  // Legacy compared the RAW patch value, so "#123ABC" over "#123abc" is
  // not a no-op — it versions the tag (and normalizes on the way in).
  let tag = Tag(..tags_fixtures.tag(slug: "deploys"), color: Some("#123abc"))
  let v2 = Tag(..tag, id: "tag-v2", version_number: 2)
  let ctx =
    with_tags(
      TagsCaps(
        ..tags_fixtures.caps(),
        get: fn(_, _) { Some(tag) },
        insert_version: fn(_, fields: tag.TagFields, _) {
          assert fields.color == Some("#123abc")
          Ok(#(v2, 0))
        },
        record_event: fn(_, _, event) {
          assert event == TagUpdated(slug: "deploys", version: 2)
          Nil
        },
      ),
    )
  let request = UpdateRequest(..keep_all(), color: Set("#123ABC"))

  assert handlers.update(ctx, fakes.scope(), "deploys", request) == Ok(v2)
}

pub fn update_malformed_new_slug_is_tag_invalid_test() {
  let tag = tags_fixtures.tag(slug: "deploys")
  let ctx =
    with_tags(
      TagsCaps(..tags_fixtures.caps(), get: fn(_, slug) {
        case slug {
          "deploys" -> Some(tag)
          _ -> None
        }
      }),
    )
  let request = UpdateRequest(..keep_all(), new_slug: Some("a:b:c"))

  assert handlers.update(ctx, fakes.scope(), "deploys", request)
    == Error(Invalid(
      "tag_invalid",
      "Tag slug must be lowercase letters, digits, hyphens.",
    ))
}

pub fn update_bad_description_is_validation_failed_test() {
  let tag = tags_fixtures.tag(slug: "deploys")
  let ctx =
    with_tags(TagsCaps(..tags_fixtures.caps(), get: fn(_, _) { Some(tag) }))
  let request = UpdateRequest(..keep_all(), description: Some("meh"))

  assert handlers.update(ctx, fakes.scope(), "deploys", request)
    == Error(Invalid("validation_failed", "Validation failed."))
}

pub fn update_insert_race_is_validation_failed_test() {
  let tag = tags_fixtures.tag(slug: "deploys")
  let ctx =
    with_tags(
      TagsCaps(
        ..tags_fixtures.caps(),
        get: fn(_, slug) {
          case slug {
            "deploys" -> Some(tag)
            _ -> None
          }
        },
        insert_version: fn(_, _, _) { Error(Nil) },
      ),
    )
  let request = UpdateRequest(..keep_all(), new_slug: Some("shipping"))

  assert handlers.update(ctx, fakes.scope(), "deploys", request)
    == Error(Invalid("validation_failed", "Validation failed."))
}

// ===== delete =====

pub fn delete_soft_deletes_and_records_test() {
  let tag = tags_fixtures.tag(slug: "deploys")
  let ctx =
    with_tags(
      TagsCaps(
        ..tags_fixtures.caps(),
        get: fn(_, _) { Some(tag) },
        soft_delete: fn(tag_id, actor) {
          assert tag_id == "tag-v1"
          assert actor == "user-1"
          Nil
        },
        record_event: fn(_, _, event) {
          assert event == TagDeleted(slug: "deploys")
          Nil
        },
      ),
    )

  assert handlers.delete(ctx, fakes.scope(), "deploys") == Ok(Nil)
}

pub fn delete_missing_tag_is_not_found_test() {
  let ctx = with_tags(TagsCaps(..tags_fixtures.caps(), get: fn(_, _) { None }))

  assert handlers.delete(ctx, fakes.scope(), "nope") == Error(NotFound)
}

// ===== restore =====

pub fn restore_missing_deleted_row_is_not_found_test() {
  let ctx =
    with_tags(TagsCaps(..tags_fixtures.caps(), get_deleted: fn(_, _) { None }))

  assert handlers.restore(ctx, fakes.scope(), "nope") == Error(NotFound)
}

pub fn restore_superseded_row_is_rejected_test() {
  let dead = Tag(..tags_fixtures.tag(slug: "deploys"), superseded: True)
  let ctx =
    with_tags(
      TagsCaps(..tags_fixtures.caps(), get_deleted: fn(_, _) { Some(dead) }),
    )

  assert handlers.restore(ctx, fakes.scope(), "deploys")
    == Error(Invalid(
      "validation_failed",
      "tag row was superseded by a newer version, not user-deleted",
    ))
}

pub fn restore_when_live_slug_reclaimed_is_slug_taken_test() {
  let dead = tags_fixtures.tag(slug: "deploys")
  let live = Tag(..tags_fixtures.tag(slug: "deploys"), id: "tag-v9")
  let ctx =
    with_tags(
      TagsCaps(
        ..tags_fixtures.caps(),
        get_deleted: fn(_, _) { Some(dead) },
        get: fn(_, _) { Some(live) },
      ),
    )

  assert handlers.restore(ctx, fakes.scope(), "deploys")
    == Error(Invalid("slug_taken", "Slug already in use."))
}

pub fn restore_undeletes_and_records_test() {
  let dead = tags_fixtures.tag(slug: "deploys")
  let ctx =
    with_tags(
      TagsCaps(
        ..tags_fixtures.caps(),
        get_deleted: fn(ws_id, slug) {
          assert ws_id == "ws-1"
          assert slug == "deploys"
          Some(dead)
        },
        get: fn(_, _) { None },
        undelete: fn(tag_id) {
          assert tag_id == "tag-v1"
          Nil
        },
        record_event: fn(_, _, event) {
          assert event == TagRestored(slug: "deploys")
          Nil
        },
      ),
    )

  assert handlers.restore(ctx, fakes.scope(), "deploys") == Ok(dead)
}
