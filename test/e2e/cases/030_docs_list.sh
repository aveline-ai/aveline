# shellcheck shell=bash
# list-docs — filters, scoping. Each test creates its own workspace.

test_list_docs_empty_workspace() {
  local ws; ws="$(mk_workspace ws-list-empty)"
  run_cli -w "$ws" list-docs
  expect_ok "list-docs on empty ws ok"
  expect_count "$MY_DOCS" "0" "no docs beyond the seeded orientation doc"
  if jq -e '.docs | map(select(.orientation)) | length == 1' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "exactly one orientation doc among the seeded set"
  else
    fail "orientation doc missing or duplicated"
  fi
}

test_list_docs_after_creating_three() {
  local ws; ws="$(mk_workspace ws-list-three)"
  mk_doc "$ws" "Alpha" >/dev/null
  mk_doc "$ws" "Beta"  >/dev/null
  mk_doc "$ws" "Gamma" >/dev/null
  run_cli -w "$ws" list-docs
  expect_ok "list-docs ok"
  expect_count "$MY_DOCS" "3" "three docs listed"
}

test_list_docs_shows_pin_slot() {
  local ws; ws="$(mk_workspace ws-pinned)"
  local blocks; blocks="[$(block_paragraph 'hi')]"
  run_cli -w "$ws" create-doc --title "Pinned" --blocks "$blocks"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" pin-doc "$slug" --slot 2
  expect_ok "pin-doc ok"
  run_cli -w "$ws" list-docs
  if jq -e --arg s "$slug" '.docs[] | select(.slug == $s) | .pin_slot == 2' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "pin_slot echoed in list-docs"
  else
    fail "pin_slot missing from list-docs"
  fi
}
test_list_docs_filter_by_tag() {
  local ws; ws="$(mk_workspace ws-bytag)"
  mk_tag "$ws" "alpha" >/dev/null
  mk_tag "$ws" "beta"  >/dev/null
  mk_doc "$ws" "WithAlpha" "alpha" >/dev/null
  mk_doc "$ws" "WithBeta"  "beta"  >/dev/null
  run_cli -w "$ws" list-docs --tag alpha
  expect_ok "list --tag alpha ok"
  expect_count ".docs" "1" "exactly one alpha-tagged doc"
}

test_list_docs_filter_multiple_tags_intersection() {
  local ws; ws="$(mk_workspace ws-multi)"
  mk_tag "$ws" "x" >/dev/null
  mk_tag "$ws" "y" >/dev/null
  mk_doc "$ws" "BothXY"  "x,y" >/dev/null
  mk_doc "$ws" "OnlyX"   "x"   >/dev/null
  mk_doc "$ws" "OnlyY"   "y"   >/dev/null
  run_cli -w "$ws" list-docs --tag x --tag y
  expect_ok "list intersection ok"
  expect_count ".docs" "1" "only the doc tagged x∩y"
}

test_list_docs_unknown_tag_returns_empty() {
  local ws; ws="$(mk_workspace ws-unktag)"
  mk_doc "$ws" "Doc" >/dev/null
  run_cli -w "$ws" list-docs --tag tag-not-there
  expect_ok "list with unknown tag still ok"
  expect_count ".docs" "0" "unknown tag → empty"
}

test_list_docs_unknown_workspace_via_flag() {
  run_cli -w "ghost-$(us)" list-docs
  expect_err "workspace_not_found" 4 "unknown ws via -w → workspace_not_found"
}

test_list_docs_unauthorized_token() {
  # Hit a workspace as a user who isn't a member.
  local ws; ws="$(mk_workspace ws-foreign)"
  # bob isn't a member.
  AVELINE_E2E_PERSONA=bob run_cli -w "$ws" list-docs
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "non-member → non-zero exit"
  else
    fail "non-member unexpectedly allowed to list-docs"
  fi
}
