# shellcheck shell=bash
# Doc lifecycle — delete, restore, kudos.

test_delete_doc_then_list_excludes_it() {
  local ws; ws="$(mk_workspace ws-del)"
  local slug; slug="$(mk_doc "$ws" "Doomed")"
  run_cli -w "$ws" delete-doc "$slug"
  expect_ok "delete-doc ok"
  run_cli -w "$ws" list-docs
  expect_ok "list-docs ok after delete"
  if jq -e --arg s "$slug" '.docs | map(.slug) | index($s) | not' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "deleted doc not in default list"
  else
    fail "deleted doc still listed"
  fi
}

test_restore_doc_makes_it_visible_again() {
  local ws; ws="$(mk_workspace ws-restore)"
  local slug; slug="$(mk_doc "$ws" "Recoverable")"
  run_cli -w "$ws" delete-doc "$slug"
  expect_ok "delete ok"
  run_cli -w "$ws" restore-doc "$slug"
  expect_ok "restore-doc ok"
  run_cli -w "$ws" get-doc "$slug"
  expect_ok "get-doc after restore ok"
}

test_restore_doc_not_user_deleted() {
  local ws; ws="$(mk_workspace ws-restore-nud)"
  local slug; slug="$(mk_doc "$ws" "NeverDeleted")"
  run_cli -w "$ws" restore-doc "$slug"
  expect_err "not_user_deleted" 2 "restore on live doc → not_user_deleted"
}

test_delete_doc_not_found() {
  local ws; ws="$(mk_workspace ws-del-nf)"
  run_cli -w "$ws" delete-doc "ghost-$(us)"
  expect_err "not_found" 4 "delete missing doc → not_found"
}

test_kudos_doc_by_other_user_succeeds() {
  local ws; ws="$(mk_workspace ws-kudos)"
  local slug; slug="$(mk_doc "$ws" "AliceWrote")"
  add_member "$ws" "bob"
  AVELINE_E2E_PERSONA=bob run_cli -w "$ws" kudos-doc "$slug"
  expect_ok "bob's kudos on alice's doc ok"
}

test_kudos_doc_by_owner_forbidden() {
  local ws; ws="$(mk_workspace ws-kudos-self)"
  local slug; slug="$(mk_doc "$ws" "Mine")"
  run_cli -w "$ws" kudos-doc "$slug"
  expect_err "self_kudos" 2 "kudos on own doc → self_kudos"
}

test_delete_already_deleted_doc() {
  local ws; ws="$(mk_workspace ws-deldel)"
  local slug; slug="$(mk_doc "$ws" "Once")"
  run_cli -w "$ws" delete-doc "$slug"
  expect_ok "first delete ok"
  run_cli -w "$ws" delete-doc "$slug"
  # Behavior is currently to return not_found (deleted docs are hidden).
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "second delete on already-deleted doc errors"
  else
    fail "second delete unexpectedly succeeded"
  fi
}
