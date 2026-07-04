# shellcheck shell=bash
# Tags — CRUD, validation, delete cascade.

test_list_tags_seeded_with_template() {
  local ws; ws="$(mk_workspace ws-t-fresh)"
  run_cli -w "$ws" list-tags
  expect_ok "list-tags ok"
  expect_count ".tags" "20" "fresh workspace has the recommended template tags"
  if jq -e '.tags | map(.slug) | index("status:done")' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "status scope seeded"
  else
    fail "status scope missing"
  fi
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
  run_cli -w "$ws" create-tag --name "playbook" --description "operations playbooks for oncall use"
  expect_ok "tag created"
  run_cli -w "$ws" get-tag "playbook"
  expect_ok "get-tag ok"
  expect_present ".tag" "tag object present"
  expect_eq ".tag.slug" "playbook" "slug round-trips"
  expect_eq ".tag.description" "operations playbooks for oncall use" "description round-trips"
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

test_delete_tag_leaves_docs_tagless() {
  local ws; ws="$(mk_workspace ws-t-orph)"
  # Tags are an optional lens: deleting a doc's only tag just leaves the
  # doc untagged.
  run_cli -w "$ws" create-tag --name "lone" --description "lone tag with one doc"
  expect_ok "tag created"
  local blocks; blocks="[$(block_paragraph 'hi')]"
  run_cli -w "$ws" create-doc --title "OneTag" --tag lone --blocks "$blocks"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" delete-tag "lone"
  expect_ok "deleting a doc's only tag succeeds"
  run_cli -w "$ws" get-doc "$slug"
  expect_count ".doc.tags" "0" "doc is now tagless, not deleted"
}

test_tag_color_and_versioned_edits() {
  local ws; ws="$(mk_workspace ws-t-color)"
  run_cli -w "$ws" create-tag --name "stage:done" --description "Stage: shipped." --color "#22c55e"
  expect_ok "create with color"
  expect_eq ".tag.color" "#22c55e" "color echoed"
  expect_eq ".tag.version_number" "1" "v1"

  run_cli -w "$ws" edit-tag "stage:done" --color "#16a34a"
  expect_ok "recolor"
  expect_eq ".tag.version_number" "2" "recolor made a new version"
  expect_eq ".tag.color" "#16a34a" "new color"

  run_cli -w "$ws" edit-tag "stage:done" --color ""
  expect_ok "clear color"
  expect_eq ".tag.color" "null" "color cleared to default"
  expect_eq ".tag.version_number" "3" "clearing versions too"

  run_cli -w "$ws" edit-tag "stage:done" --color "green"
  expect_err "validation_failed" 2 "non-hex color rejected"
}

test_tag_restore_brings_attachments_back() {
  local ws; ws="$(mk_workspace ws-t-restore)"
  run_cli -w "$ws" create-tag --name "lone" --description "Restorable tag."
  local blocks; blocks="[$(block_paragraph 'hi')]"
  run_cli -w "$ws" create-doc --title "Tagged" --tag lone --blocks "$blocks"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"

  run_cli -w "$ws" delete-tag "lone"
  expect_ok "soft delete"
  run_cli -w "$ws" get-doc "$slug"
  expect_count ".doc.tags" "0" "deleted tag hidden from the doc"
  run_cli -w "$ws" list-tags
  if jq -e '.tags | map(.slug) | index("lone") | not' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "deleted tag hidden from list-tags"
  else
    fail "deleted tag still listed"
  fi

  run_cli -w "$ws" restore-tag "lone"
  expect_ok "restore"
  run_cli -w "$ws" get-doc "$slug"
  expect_count ".doc.tags" "1" "attachment came back with the tag"

  run_cli -w "$ws" restore-tag "lone"
  expect_err "not_found" 4 "restoring a live tag → not_found (no deleted row)"
}

test_tag_sort_key_orders_lists() {
  local ws; ws="$(mk_workspace ws-t-sort)"
  # Template seeds sort keys on scope values: lifecycle order, not
  # alphabetical (approved would otherwise sort first).
  run_cli -w "$ws" list-tags
  local stages; stages="$(jq -r '[.tags[].slug | select(startswith("stage:"))] | join(",")' <<<"$LAST_OUT_TEXT")"
  if [ "$stages" = "stage:draft,stage:in-review,stage:approved,stage:cancelled" ]; then
    pass "stage values in lifecycle order"
  else
    fail "stage order wrong: $stages"
  fi

  # Reorder via edit-tag --sort-key: a new version, one tag touched.
  run_cli -w "$ws" edit-tag "stage:draft" --sort-key "stage:9"
  expect_ok "sort-key edit ok"
  expect_eq ".tag.version_number" "2" "reorder is a versioned edit"
  run_cli -w "$ws" list-tags
  local last; last="$(jq -r '[.tags[].slug | select(startswith("stage:"))] | last' <<<"$LAST_OUT_TEXT")"
  if [ "$last" = "stage:draft" ]; then
    pass "reorder took effect"
  else
    fail "reorder didn't take: last stage is $last"
  fi

  # "" clears back to alphabetical-by-slug.
  run_cli -w "$ws" edit-tag "stage:draft" --sort-key ""
  expect_ok "clear sort key"
  expect_eq ".tag.sort_key" "null" "sort key cleared"
}
