# shellcheck shell=bash
# Workspace isolation — non-members denied, no data leakage.

test_non_member_cannot_list_docs() {
  local ws; ws="$(mk_workspace ws-iso-list)"
  mk_doc "$ws" "Secret" >/dev/null
  AVELINE_E2E_PERSONA=bob run_cli -w "$ws" list-docs
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "non-member can't list-docs"
  else
    fail "non-member listed docs"
  fi
}

test_non_member_cannot_get_doc() {
  local ws; ws="$(mk_workspace ws-iso-get)"
  local slug; slug="$(mk_doc "$ws" "Hidden")"
  AVELINE_E2E_PERSONA=bob run_cli -w "$ws" get-doc "$slug"
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "non-member can't get-doc"
  else
    fail "non-member retrieved doc"
  fi
}

test_non_member_cannot_create_doc() {
  local ws; ws="$(mk_workspace ws-iso-create)"
  local blocks; blocks="[$(block_paragraph 'x')]"
  AVELINE_E2E_PERSONA=bob run_cli -w "$ws" create-doc --title "Bob" --blocks "$blocks"
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "non-member can't create-doc"
  else
    fail "non-member created doc"
  fi
}

test_non_member_cannot_create_comment() {
  local ws; ws="$(mk_workspace ws-iso-cm)"
  local slug; slug="$(mk_doc "$ws" "X")"
  AVELINE_E2E_PERSONA=bob run_cli -w "$ws" create-comment "$slug" --body "hi"
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "non-member can't comment"
  else
    fail "non-member commented"
  fi
}

test_non_member_cannot_list_tags() {
  local ws; ws="$(mk_workspace ws-iso-tag)"
  mk_tag "$ws" "secret" >/dev/null
  AVELINE_E2E_PERSONA=bob run_cli -w "$ws" list-tags
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "non-member can't list-tags"
  else
    fail "non-member listed tags"
  fi
}

test_non_member_cannot_list_events() {
  local ws; ws="$(mk_workspace ws-iso-ev)"
  AVELINE_E2E_PERSONA=bob run_cli -w "$ws" list-events
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "non-member can't list-events"
  else
    fail "non-member listed events"
  fi
}

test_list_workspaces_only_returns_my_workspaces() {
  # alice and bob each create workspaces; bob's list should not include
  # alice-only workspaces.
  local ws_alice; ws_alice="$(mk_workspace ws-iso-alice)"
  # Bob makes one independently. Use an explicit unique slug so the
  # globally-unique workspace slug index can't collide with anything
  # from other tests in the same suite run.
  local bob_slug; bob_slug="$(us bob-iso)"
  AVELINE_E2E_PERSONA=bob run_cli create-workspace --name "BobOnly" --slug "$bob_slug"
  expect_ok "bob creates"
  local ws_bob; ws_bob="$(jq -r '.workspace.slug' <<<"$LAST_OUT_TEXT")"
  AVELINE_E2E_PERSONA=bob run_cli list-workspaces
  expect_ok "bob list-workspaces"
  if jq -e --arg s "$ws_alice" '.workspaces | map(.slug) | index($s) | not' \
       <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "alice's workspace hidden from bob"
  else
    fail "alice's workspace leaked to bob"
  fi
  if jq -e --arg s "$ws_bob" '.workspaces | map(.slug) | index($s)' \
       <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "bob sees his own workspace"
  else
    fail "bob missing his own workspace"
  fi
}

test_tags_dont_leak_across_workspaces() {
  local a; a="$(mk_workspace ws-iso-tag-a)"
  local b; b="$(mk_workspace ws-iso-tag-b)"
  mk_tag "$a" "secret-a" >/dev/null
  mk_tag "$b" "secret-b" >/dev/null
  run_cli -w "$a" list-tags
  if jq -e '.tags | map(.slug) | index("secret-b") | not' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "tag from B not visible in A"
  else
    fail "tag from B leaked into A"
  fi
}

test_docs_dont_leak_across_workspaces() {
  local a; a="$(mk_workspace ws-iso-doc-a)"
  local b; b="$(mk_workspace ws-iso-doc-b)"
  mk_doc "$a" "InA" >/dev/null
  mk_doc "$b" "InB" >/dev/null
  run_cli -w "$a" list-docs
  expect_count "$MY_DOCS" "1" "A has exactly 1 created doc"
  expect_eq "$MY_DOCS | .[0].title" "InA" "right doc"
}

test_member_added_can_then_access() {
  local ws; ws="$(mk_workspace ws-iso-add)"
  mk_doc "$ws" "X" >/dev/null
  add_member "$ws" "bob"
  AVELINE_E2E_PERSONA=bob run_cli -w "$ws" list-docs
  expect_ok "bob can list after add"
  expect_count "$MY_DOCS" "1" "bob sees the doc"
}
