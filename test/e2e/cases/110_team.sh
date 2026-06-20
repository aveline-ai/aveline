# shellcheck shell=bash
# Team — members + invites.

test_list_members_includes_owner() {
  local ws; ws="$(mk_workspace ws-mem-list)"
  run_cli -w "$ws" list-members
  expect_ok "list-members ok"
  if jq -e '.members | map(.username) | index("alice")' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "creator alice is a member"
  else
    fail "alice missing from member list"
  fi
}

test_add_member_succeeds() {
  local ws; ws="$(mk_workspace ws-mem-add)"
  run_cli -w "$ws" add-member --username "bob"
  expect_ok "add bob ok"
  run_cli -w "$ws" list-members
  if jq -e '.members | map(.username) | index("bob")' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "bob now a member"
  else
    fail "bob missing after add"
  fi
}

test_add_member_already_member() {
  local ws; ws="$(mk_workspace ws-mem-dup)"
  run_cli -w "$ws" add-member --username "bob"
  expect_ok "first add ok"
  run_cli -w "$ws" add-member --username "bob"
  expect_err "already_member" 2 "duplicate add → already_member"
}

test_add_member_unknown_username() {
  local ws; ws="$(mk_workspace ws-mem-unk)"
  run_cli -w "$ws" add-member --username "user-that-does-not-exist"
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "unknown username errors"
  else
    fail "unknown username accepted"
  fi
}

test_remove_member_succeeds() {
  local ws; ws="$(mk_workspace ws-mem-rm)"
  run_cli -w "$ws" add-member --username "bob"
  expect_ok "add bob ok"
  run_cli -w "$ws" remove-member "bob"
  expect_ok "remove bob ok"
  run_cli -w "$ws" list-members
  if jq -e '.members | map(.username) | index("bob") | not' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "bob no longer a member"
  else
    fail "bob still listed after remove"
  fi
}

test_remove_self_forbidden() {
  local ws; ws="$(mk_workspace ws-mem-self)"
  run_cli -w "$ws" remove-member "alice"
  expect_err "self_remove" 2 "self-remove → self_remove"
}

test_remove_non_member() {
  local ws; ws="$(mk_workspace ws-mem-ghost)"
  run_cli -w "$ws" remove-member "bob"
  expect_err "not_member" 2 "remove non-member → not_member"
}

test_get_invite_idempotent() {
  local ws; ws="$(mk_workspace ws-inv-get)"
  run_cli -w "$ws" get-invite
  expect_ok "first get-invite ok"
  local code1; code1="$(jq -r '.invite.code // .code' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-invite
  expect_ok "second get-invite ok"
  local code2; code2="$(jq -r '.invite.code // .code' <<<"$LAST_OUT_TEXT")"
  if [[ -n "$code1" && "$code1" == "$code2" ]]; then
    pass "invite is idempotent (same code)"
  else
    fail "invite codes differ across calls ($code1 != $code2)"
  fi
}

test_revoke_invite_then_new_code() {
  local ws; ws="$(mk_workspace ws-inv-rev)"
  run_cli -w "$ws" get-invite
  expect_ok "first get ok"
  local code1; code1="$(jq -r '.invite.code // .code' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" revoke-invite
  expect_ok "revoke ok"
  run_cli -w "$ws" get-invite
  expect_ok "get-after-revoke ok"
  local code2; code2="$(jq -r '.invite.code // .code' <<<"$LAST_OUT_TEXT")"
  if [[ "$code1" != "$code2" ]]; then
    pass "post-revoke code is fresh"
  else
    fail "post-revoke returned the same code"
  fi
}

test_non_member_cannot_see_workspace() {
  local ws; ws="$(mk_workspace ws-mem-iso)"
  # Bob is NOT added.
  AVELINE_E2E_PERSONA=bob run_cli -w "$ws" list-members
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "non-member denied"
  else
    fail "non-member could list members"
  fi
}
