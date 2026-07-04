# shellcheck shell=bash
# Combined filters + pagination edges.

test_list_events_large_set_with_limit() {
  local ws; ws="$(mk_workspace ws-cf-bulk)"
  for i in 1 2 3 4 5 6 7 8 9 10; do
    mk_doc "$ws" "D$i" >/dev/null
  done
  run_cli -w "$ws" list-events --limit 5
  expect_ok "list with limit=5"
  expect_count ".events" "5" "exactly 5 events returned"
}

test_list_events_pagination_round_trip() {
  local ws; ws="$(mk_workspace ws-cf-page)"
  for i in 1 2 3 4 5; do mk_doc "$ws" "P$i" >/dev/null; done
  run_cli -w "$ws" list-events --limit 2
  expect_ok "page 1 ok"
  local oldest; oldest="$(jq -r '.events[-1].id' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" list-events --limit 2 --before-id "$oldest"
  expect_ok "page 2 ok"
  # No duplicate id between pages.
  local p2_top; p2_top="$(jq -r '.events[0].id' <<<"$LAST_OUT_TEXT")"
  if [[ -n "$p2_top" && "$p2_top" != "$oldest" ]]; then
    pass "page 2 doesn't repeat the cursor row"
  else
    fail "pagination overlapped (top of p2 = cursor)"
  fi
}

test_list_docs_no_filter_lists_all_undeleted() {
  local ws; ws="$(mk_workspace ws-cf-all)"
  mk_doc "$ws" "Live1" >/dev/null
  local doomed; doomed="$(mk_doc "$ws" "Doomed")"
  mk_doc "$ws" "Live2" >/dev/null
  run_cli -w "$ws" delete-doc "$doomed"
  run_cli -w "$ws" list-docs
  expect_ok "list-docs ok"
  expect_count "$MY_DOCS" "2" "deleted doc excluded"
}

test_list_events_limit_zero_uses_default() {
  local ws; ws="$(mk_workspace ws-cf-lz)"
  mk_doc "$ws" "X" >/dev/null
  # limit=0 is invalid; server falls back to default (50).
  run_cli -w "$ws" list-events --limit 0
  expect_ok "limit=0 still ok"
  local n; n="$(jq '.events | length' <<<"$LAST_OUT_TEXT")"
  if [[ "$n" -ge "1" ]]; then
    pass "limit=0 returned default-sized batch (n=$n)"
  else
    fail "limit=0 returned empty"
  fi
}
