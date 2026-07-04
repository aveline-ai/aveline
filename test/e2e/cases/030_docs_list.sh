# shellcheck shell=bash
# list-docs — filters, scoping. Each test creates its own workspace.

test_list_docs_empty_workspace() {
  local ws; ws="$(mk_workspace ws-list-empty)"
  run_cli -w "$ws" list-docs
  expect_ok "list-docs on empty ws ok"
  expect_count "$MY_DOCS" "0" "no docs beyond the seeded orientation doc"
  expect_eq '.docs[0].slug' "agents" "orientation doc is the only one there"
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

test_list_docs_filter_pinned() {
  local ws; ws="$(mk_workspace ws-pinned)"
  # Create one pinned, one not. Pinning happens via apply-ops or
  # create-doc --pin.
  mk_tag "$ws" "ops" >/dev/null
  local blocks; blocks="[$(block_paragraph 'hi')]"
  run_cli -w "$ws" create-doc --title "Pinned" --tag ops --pin --blocks "$blocks"
  expect_ok "pinned doc created"
  run_cli -w "$ws" create-doc --title "Unpinned" --tag ops --blocks "$blocks"
  expect_ok "unpinned doc created"
  run_cli -w "$ws" list-docs --pinned
  expect_ok "list --pinned ok"
  expect_count "$MY_DOCS" "1" "exactly one pinned doc (plus the pinned orientation doc)"
  if jq -e '.docs | all(.pinned == true)' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "every returned doc is pinned"
  else
    fail "non-pinned doc leaked into --pinned"
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
