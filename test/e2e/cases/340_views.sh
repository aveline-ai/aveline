# shellcheck shell=bash
# Views — config-tier entities (like tags): named, versioned snapshots
# of the docs display knobs. Covers create/edit/rename/pin lifecycle,
# config validation, and soft delete + restore.

test_view_create_and_list() {
  local ws; ws="$(mk_workspace vw-create)"

  run_cli -w "$ws" create-view --name tickets \
    --description "All open work, grouped by status." \
    --tag ticket --group-by status
  expect_ok "create-view ok"
  expect_eq '.view.name' "tickets" "name echoed"
  expect_eq '.view.config.group_by' "status" "group_by saved"
  expect_eq '.view.config.tags[0]' "ticket" "filter tags saved"
  expect_eq '.view.pinned' "false" "not pinned by default"
  expect_eq '.view.version_number' "1" "v1"

  run_cli -w "$ws" list-views
  expect_ok "list ok"
  expect_eq '.views | length' "1" "one view"
}

test_view_config_validation() {
  local ws; ws="$(mk_workspace vw-valid)"

  run_cli -w "$ws" create-view --name bad --description "Unknown tag." --tag ghost
  expect_err "unknown_tags" 2 "unknown filter tag rejected"

  run_cli -w "$ws" create-view --name bad2 --description "Empty scope." --group-by lane
  expect_err "view_invalid" 2 "group_by scope without tags rejected"

  run_cli -w "$ws" create-view --name "Bad Name" --description "Slug rule."
  expect_err "validation_failed" 2 "non-slug name rejected"
}

test_view_edit_is_versioned_rename_included() {
  local ws; ws="$(mk_workspace vw-edit)"
  run_cli -w "$ws" create-view --name tickets --description "Open work." --tag ticket

  run_cli -w "$ws" edit-view tickets --group-by status
  expect_ok "edit ok"
  expect_eq '.view.version_number' "2" "edit minted a version"
  expect_eq '.view.config.group_by' "status" "group_by applied"

  run_cli -w "$ws" edit-view tickets --new-name work
  expect_ok "rename ok"
  expect_eq '.view.name' "work" "renamed"
  expect_eq '.view.version_number' "3" "rename versioned"

  run_cli -w "$ws" edit-view tickets --description "nope"
  expect_err "not_found" 4 "old name gone after rename"
}

test_view_pin_roundtrip() {
  local ws; ws="$(mk_workspace vw-pin)"
  run_cli -w "$ws" create-view --name tickets --description "Open work." --tag ticket

  run_cli -w "$ws" pin-view tickets
  expect_ok "pin ok"
  expect_eq '.view.pinned' "true" "pinned"
  expect_eq '.view.version_number' "1" "pinning is not a version"

  run_cli -w "$ws" unpin-view tickets
  expect_ok "unpin ok"
  expect_eq '.view.pinned' "false" "unpinned"
}

test_view_delete_restore() {
  local ws; ws="$(mk_workspace vw-del)"
  run_cli -w "$ws" create-view --name tickets --description "Open work." --tag ticket

  run_cli -w "$ws" delete-view tickets
  expect_ok "delete ok"

  run_cli -w "$ws" list-views
  expect_eq '.views | length' "0" "gone from the list"

  run_cli -w "$ws" restore-view tickets
  expect_ok "restore ok"
  expect_eq '.view.name' "tickets" "restored"

  run_cli -w "$ws" list-views
  expect_eq '.views | length' "1" "back in the list"
}
