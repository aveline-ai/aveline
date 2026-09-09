//// /tags endpoints — the workspace tag taxonomy. Ports TagController
//// (index/show/create/update/delete/restore) plus the decision logic of
//// Aveline.Tags (create/edit/delete/restore + slug rules).
////
//// Legacy envelope parity notes:
////   * "slug_taken" errors are re-mapped by the controller onto the
////     legacy `{:error, :slug_taken}` fallback tuple so the response
////     keeps its `field: "slug"` detail.
////   * Malformed slugs -> Invalid("tag_invalid", ...); all other field
////     failures -> Invalid("validation_failed", "Validation failed.") —
////     exactly the codes the changeset summary produced.

import aveline/caps/tags.{
  type TagEvent, TagCreated, TagDeleted, TagRenamed, TagRestored, TagUpdated,
}
import aveline/core/ctx.{type Ctx}
import aveline/core/error.{type ApiError, Invalid, NotFound}
import aveline/core/scope.{type Scope}
import aveline/tags/rules
import aveline/tags/tag.{type Tag, type TagStats}
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// A field that may be kept as-is, cleared to its default, or replaced —
/// PATCH /tags/:slug's `""` = clear, absent = keep semantics.
pub type Patch {
  Keep
  Clear
  Set(String)
}

pub type CreateRequest {
  CreateRequest(
    /// Raw slug (or `name` alias) — normalized + validated here.
    slug: String,
    description: String,
    color: Option(String),
    sort_key: Option(String),
  )
}

pub type UpdateRequest {
  UpdateRequest(
    /// Raw replacement slug (`new_slug`, or `name` alias).
    new_slug: Option(String),
    description: Option(String),
    color: Patch,
    sort_key: Patch,
  )
}

// ===== Reads =====

/// GET /tags — every live tag + usage stats, in the one workspace tag
/// order (sort_key override, alphabetical otherwise). Infallible.
pub fn index(ctx: Ctx, scope: Scope) -> List(TagStats) {
  ctx.tags.list_with_stats(scope.workspace.id)
}

/// GET /tags/:slug
pub fn show(ctx: Ctx, scope: Scope, slug: String) -> Result(Tag, ApiError) {
  fetch_live(ctx, scope, slug)
}

// ===== Writes =====

/// POST /tags — create a v1 tag row.
pub fn create(
  ctx: Ctx,
  scope: Scope,
  request: CreateRequest,
) -> Result(Tag, ApiError) {
  let slug = rules.normalize_slug(request.slug)
  use fields <- result.try(rules.validate_fields(
    slug,
    request.description,
    request.color,
    request.sort_key,
  ))

  case ctx.tags.insert(scope.workspace.id, fields, scope.actor.id) {
    // Legacy quirk kept for parity: the composite unique index reports
    // on :workspace_id, so a duplicate create fell through the fallback
    // summary as plain validation_failed — only update/restore say
    // slug_taken.
    Error(Nil) -> Error(Invalid("validation_failed", "Validation failed."))
    Ok(tag) -> {
      record(
        ctx,
        scope,
        TagCreated(slug: tag.slug, description: tag.description),
      )
      Ok(tag)
    }
  }
}

/// PATCH/PUT /tags/:slug — rename, redescribe, recolor, and/or re-sort.
/// Any real change inserts a NEW VERSION row sharing base_tag_id; a
/// rename additionally cascades the slug across every doc carrying it.
/// A no-op edit returns the current row untouched (no version, no event).
pub fn update(
  ctx: Ctx,
  scope: Scope,
  slug: String,
  request: UpdateRequest,
) -> Result(Tag, ApiError) {
  use tag <- result.try(fetch_live(ctx, scope, slug))

  let new_slug = rules.normalize_slug(option.unwrap(request.new_slug, tag.slug))
  // Compare the raw (pre-normalization) color/sort_key like the legacy
  // edit did — a case-only color change still versions the tag.
  let new_description = case request.description {
    Some(d) -> string.trim(d)
    None -> tag.description
  }
  let new_color = apply_patch(request.color, tag.color)
  let new_sort_key = apply_patch(request.sort_key, tag.sort_key)

  let unchanged =
    new_slug == tag.slug
    && new_description == tag.description
    && new_color == tag.color
    && new_sort_key == tag.sort_key
  let renamed = new_slug != tag.slug

  case unchanged {
    True -> Ok(tag)
    False ->
      case renamed && taken(ctx, scope, new_slug) {
        True -> Error(slug_taken())
        False -> {
          use fields <- result.try(rules.validate_fields(
            new_slug,
            new_description,
            new_color,
            new_sort_key,
          ))

          case ctx.tags.insert_version(tag, fields, scope.actor.id) {
            // Lost race on the unique index — legacy surfaced the raw
            // changeset as validation_failed (see create).
            Error(Nil) ->
              Error(Invalid("validation_failed", "Validation failed."))
            Ok(#(updated, affected)) -> {
              record(ctx, scope, case renamed {
                True ->
                  TagRenamed(
                    from: tag.slug,
                    to: updated.slug,
                    version: updated.version_number,
                    affected: affected,
                  )
                False ->
                  TagUpdated(
                    slug: updated.slug,
                    version: updated.version_number,
                  )
              })
              Ok(updated)
            }
          }
        }
      }
  }
}

/// DELETE /tags/:slug — soft-delete. Docs KEEP the slug in their tags
/// arrays; the tag just turns invisible to every current read until
/// restored, making delete and restore perfect inverses.
pub fn delete(ctx: Ctx, scope: Scope, slug: String) -> Result(Nil, ApiError) {
  use tag <- result.try(fetch_live(ctx, scope, slug))

  ctx.tags.soft_delete(tag.id, scope.actor.id)
  record(ctx, scope, TagDeleted(slug: tag.slug))
  Ok(Nil)
}

/// POST /tags/:slug/restore — undo a soft delete. Every doc that carried
/// the tag shows it again instantly. Errors with slug_taken if a live
/// tag reclaimed the slug in the meantime.
pub fn restore(ctx: Ctx, scope: Scope, slug: String) -> Result(Tag, ApiError) {
  case ctx.tags.get_deleted(scope.workspace.id, slug) {
    None -> Error(NotFound)
    Some(tag) ->
      case tag.superseded {
        True ->
          Error(Invalid(
            "validation_failed",
            "tag row was superseded by a newer version, not user-deleted",
          ))
        False ->
          case taken(ctx, scope, tag.slug) {
            True -> Error(slug_taken())
            False -> {
              ctx.tags.undelete(tag.id)
              record(ctx, scope, TagRestored(slug: tag.slug))
              Ok(tag)
            }
          }
      }
  }
}

// ===== Helpers =====

fn fetch_live(ctx: Ctx, scope: Scope, slug: String) -> Result(Tag, ApiError) {
  case ctx.tags.get(scope.workspace.id, slug) {
    None -> Error(NotFound)
    Some(tag) -> Ok(tag)
  }
}

fn taken(ctx: Ctx, scope: Scope, slug: String) -> Bool {
  option.is_some(ctx.tags.get(scope.workspace.id, slug))
}

fn apply_patch(patch: Patch, current: Option(String)) -> Option(String) {
  case patch {
    Keep -> current
    Clear -> None
    Set(value) -> Some(value)
  }
}

fn record(ctx: Ctx, scope: Scope, event: TagEvent) -> Nil {
  ctx.tags.record_event(scope.workspace.id, scope.actor.id, event)
}

fn slug_taken() -> ApiError {
  Invalid("slug_taken", "Slug already in use.")
}
