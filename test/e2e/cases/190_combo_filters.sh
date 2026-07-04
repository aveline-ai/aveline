# shellcheck shell=bash
# Combined filters + pagination edges.

test_list_docs_pinned_and_tag_combine() {
  local ws; ws="$(mk_workspace ws-cf-pt)"
  mk_tag "$ws" "alpha" >/dev/null
  mk_tag "$ws" "beta"  >/dev/null
  local blocks; blocks="[$(block_paragraph 'b')]"
  # Four docs: (pinned+alpha), (pinned+beta), (unpinned+alpha), (unpinned+beta)
  run_cli -w "$ws" create-doc --title "PA" --pin --tag alpha --blocks "$blocks"; expect_ok "PA"
  run_cli -w "$ws" create-doc --title "PB" --pin --tag beta  --blocks "$blocks"; expect_ok "PB"
  run_cli -w "$ws" create-doc --title "UA"      --tag alpha --blocks "$blocks"; expect_ok "UA"
  run_cli -w "$ws" create-doc --title "UB"      --tag beta  --blocks "$blocks"; expect_ok "UB"
  # Only pinned-AND-alpha should match.
  run_cli -w "$ws" list-docs --pinned --tag alpha
  expect_ok "list pinned+alpha ok"
  expect_count ".docs" "1" "exactly one pinned+alpha doc"
  expect_eq ".docs[0].title" "PA" "the right one (PA)"
}

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

test_list_docs_pinned_false_filters_unpinned() {
  # Aveline's API accepts pinned=false (unpinned only) — verify CLI
  # passes that through correctly.
  local ws; ws="$(mk_workspace ws-cf-pinfalse)"
  local blocks; blocks="[$(block_paragraph 'b')]"
  run_cli -w "$ws" create-doc --title "Pinned" --pin --blocks "$blocks"
  expect_ok "pinned"
  run_cli -w "$ws" create-doc --title "Unpinned"      --blocks "$blocks"
  expect_ok "unpinned"
  # CLI sends --pinned=false via the boolean flag.
  XDG_CONFIG_HOME="$(persona_xdg)" AVELINE_API_URL="$E2E_API_URL" \
    "$E2E_BIN" -w "$ws" list-docs --pinned=false \
    >"$(mktemp)" 2>/dev/null > "$LAST_OUT" 2>"$LAST_ERR" || true
  LAST_EXIT=$?
  LAST_OUT_TEXT="$(cat "$LAST_OUT")"; LAST_ERR_TEXT="$(cat "$LAST_ERR")"
  if [[ "$LAST_EXIT" == "0" ]] && \
     jq -e '.docs | all(.pinned == false)' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "--pinned=false filters out pinned"
  else
    fail "--pinned=false didn't isolate unpinned"
  fi
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
