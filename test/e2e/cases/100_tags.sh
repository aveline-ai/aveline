# shellcheck shell=bash
# Tags — CRUD, validation, would_orphan_docs.

test_list_tags_empty() {
  local ws; ws="$(mk_workspace ws-t-empty)"
  run_cli -w "$ws" list-tags
  expect_ok "list-tags ok"
  expect_count ".tags" "0" "fresh workspace has no tags"
}

test_create_tag_appears_in_list() {
  local ws; ws="$(mk_workspace ws-t-list)"
  run_cli -w "$ws" create-tag --name "ops" --description "operations runbooks"
  expect_ok "create-tag ok"
  run_cli -w "$ws" list-tags
  if jq -e '.tags | map(.slug // .name) | index("ops")' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "tag appears in list"
  else
    fail "tag not in list"
  fi
}

test_get_tag_returns_metadata() {
  local ws; ws="$(mk_workspace ws-t-get)"
  run_cli -w "$ws" create-tag --name "runbook" --description "operations runbooks for oncall use"
  expect_ok "tag created"
  run_cli -w "$ws" get-tag "runbook"
  expect_ok "get-tag ok"
  expect_present ".tag" "tag object present"
  expect_eq ".tag.slug" "runbook" "slug round-trips"
  expect_eq ".tag.description" "operations runbooks for oncall use" "description round-trips"
}

test_get_tag_not_found() {
  local ws; ws="$(mk_workspace ws-t-nf)"
  run_cli -w "$ws" get-tag "ghost-$(us)"
  expect_err "not_found" 4 "missing tag → not_found"
}

test_create_tag_duplicate_slug() {
  local ws; ws="$(mk_workspace ws-t-dup)"
  run_cli -w "$ws" create-tag --name "dup" --description "duplicate test description"
  expect_ok "first create ok"
  run_cli -w "$ws" create-tag --name "dup" --description "duplicate test description"
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "duplicate tag name errors"
  else
    fail "duplicate tag accepted"
  fi
}

test_create_tag_invalid_slug() {
  local ws; ws="$(mk_workspace ws-t-bad)"
  run_cli -w "$ws" create-tag --name "Has Spaces" --description "would be invalid anyway"
  expect_err "tag_invalid" 2 "spaces in tag → tag_invalid"
}

test_edit_tag_rename() {
  local ws; ws="$(mk_workspace ws-t-ren)"
  run_cli -w "$ws" create-tag --name "old" --description "old tag description"
  expect_ok "create ok"
  run_cli -w "$ws" edit-tag "old" --name "new"
  expect_ok "rename ok"
  run_cli -w "$ws" get-tag "new"
  expect_ok "get under new name ok"
}

test_edit_tag_description() {
  local ws; ws="$(mk_workspace ws-t-desc)"
  run_cli -w "$ws" create-tag --name "describe" --description "old description text"
  expect_ok "create ok"
  run_cli -w "$ws" edit-tag "describe" --description "now described differently"
  expect_ok "describe edit ok"
}

test_edit_tag_requires_a_field() {
  local ws; ws="$(mk_workspace ws-t-noop)"
  run_cli -w "$ws" create-tag --name "x" --description "x has a description too"
  run_cli -w "$ws" edit-tag "x"
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "edit-tag with no changes fails"
  else
    fail "edit-tag with no changes accepted"
  fi
}

test_delete_tag_unattached_ok() {
  local ws; ws="$(mk_workspace ws-t-delok)"
  run_cli -w "$ws" create-tag --name "lonely" --description "lonely tag for deletion"
  run_cli -w "$ws" delete-tag "lonely"
  expect_ok "delete unattached tag ok"
}

test_delete_tag_would_orphan_docs() {
  local ws; ws="$(mk_workspace ws-t-orph)"
  # Create tag, then a doc with ONLY that tag — deleting the tag would
  # leave the doc with zero tags, which the API rejects.
  run_cli -w "$ws" create-tag --name "lone" --description "lone tag with one doc"
  expect_ok "tag created"
  local blocks; blocks="[$(block_paragraph 'hi')]"
  run_cli -w "$ws" create-doc --title "OneTag" --tag lone --blocks "$blocks"
  expect_ok "doc created with only one tag"
  run_cli -w "$ws" delete-tag "lone"
  expect_err "would_orphan_docs" 2 "deleting only tag → would_orphan_docs"
}
