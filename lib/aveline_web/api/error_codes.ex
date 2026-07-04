defmodule AvelineWeb.Api.ErrorCodes do
  @moduledoc """
  Catalog of every machine-readable error code the API emits.

  The agent uses `error.code` to branch its retry logic; the human
  message in `error.message` is for its working memory. Keep the codes
  short, snake_case, and stable. Adding a code? Add it here so the
  CLI README + Claude usage guide stay in sync.

  ## Codes

  | code                       | HTTP | when                                                                                |
  | -------------------------- | ---- | ----------------------------------------------------------------------------------- |
  | unauthorized               | 401  | missing / invalid `Authorization: Bearer ...` header                                 |
  | forbidden                  | 403  | authed but not allowed (e.g. delete someone else's comment, kudos own doc)          |
  | workspace_not_found        | 404  | workspace slug doesn't resolve                                                       |
  | not_found                  | 404  | resource not found (doc, comment, tag, version)                                      |
  | validation_failed          | 422  | request body shape / field validation failed                                         |
  | slug_taken                 | 422  | slug already in use (doc, workspace, tag)                                            |
  | tag_invalid                | 422  | one or more tag slugs are malformed                                                  |
  | unknown_tags               | 422  | one or more tag slugs aren't defined in this workspace                              |
  | disposition_missing        | 422  | open comments anchored to touched blocks weren't dispositioned                       |
  | duplicate_dispositions     | 422  | the same comment_id appears twice in `comment_dispositions`                          |
  | leave_on_deleted_block     | 422  | `leave` disposition used on a comment whose block was deleted                        |
  | reanchor_target_missing    | 422  | reanchor target block_id doesn't exist in the new blocks                             |
  | invalid_disposition_action | 422  | action wasn't one of resolve / reanchor / leave                                      |
  | comment_not_found          | 422  | dispositioned comment doesn't exist (mid-transaction)                                |
  | self_kudos                 | 422  | tried to give kudos to your own doc                                                  |
  | self_remove                | 422  | tried to remove yourself from a workspace                                            |
  | already_member             | 422  | user is already a member                                                             |
  | not_member                 | 422  | user is not a member of the workspace                                                |
  | not_user_deleted           | 422  | tried to restore a doc that wasn't user-deleted (e.g. it was superseded)            |
  | stale_version              | 422  | tried to edit/delete a comment row that's already superseded or deleted              |
  | doc_link_target_not_found  | 422  | doc_link block references a doc that doesn't exist in this workspace                 |
  | orientation_undeletable    | 422  | tried to delete the workspace orientation doc                                        |
  | pin_limit_reached          | 422  | all 6 home-page pin slots are taken — unpin one first                                |
  | pin_slot_taken             | 422  | that home-page pin slot is occupied by another doc                                   |
  | tag_scope_conflict         | 422  | tag set carries two tags from the same scope (e.g. status:todo + status:done)        |
  | internal_error             | 500  | something unexpected blew up                                                          |
  """

  # Returning the catalog as a list lets tests assert no code escapes
  # without being registered here.
  def all do
    ~w(
      unauthorized
      forbidden
      workspace_not_found
      not_found
      validation_failed
      slug_taken
      tag_invalid
      unknown_tags
      disposition_missing
      duplicate_dispositions
      leave_on_deleted_block
      reanchor_target_missing
      invalid_disposition_action
      comment_not_found
      self_kudos
      self_remove
      already_member
      not_member
      not_user_deleted
      stale_version
      doc_link_target_not_found
      orientation_undeletable
      pin_limit_reached
      pin_slot_taken
      tag_scope_conflict
      internal_error
    )
  end
end
