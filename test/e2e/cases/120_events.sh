# shellcheck shell=bash
# Events — activity feed.

test_events_empty_in_fresh_workspace() {
  local ws; ws="$(mk_workspace ws-ev-empty)"
  run_cli -w "$ws" list-events
  expect_ok "list-events ok"
  # A brand-new workspace will have at least the "workspace_created"
  # event, but should not have docs/comments. Accept ≥ 0.
  if jq -e '.events | type == "array"' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "events is an array"
  else
    fail "events isn't an array"
  fi
}

test_events_records_doc_creation() {
  local ws; ws="$(mk_workspace ws-ev-doc)"
  local slug; slug="$(mk_doc "$ws" "Eventful")"
  run_cli -w "$ws" list-events
  expect_ok "list-events ok"
  # At least one event should reference the new doc slug.
  if jq -e --arg s "$slug" '.events | any(.target_slug == $s)' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "doc creation produced an event with target_slug"
  else
    fail "no event references the newly-created doc"
  fi
}

test_events_limit_flag_caps_results() {
  local ws; ws="$(mk_workspace ws-ev-lim)"
  for i in 1 2 3 4 5; do
    mk_doc "$ws" "D$i" >/dev/null
  done
  run_cli -w "$ws" list-events --limit 2
  expect_ok "list-events --limit 2 ok"
  local n; n="$(jq '.events | length' <<<"$LAST_OUT_TEXT")"
  if [[ "$n" -le 2 ]]; then
    pass "--limit honored (got $n)"
  else
    fail "--limit ignored (got $n)"
  fi
}

test_events_pagination_with_before_id() {
  local ws; ws="$(mk_workspace ws-ev-pag)"
  for i in 1 2 3; do mk_doc "$ws" "P$i" >/dev/null; done
  run_cli -w "$ws" list-events --limit 1
  expect_ok "first page ok"
  local first_id; first_id="$(jq -r '.events[0].id' <<<"$LAST_OUT_TEXT")"
  if [[ -z "$first_id" || "$first_id" == "null" ]]; then
    fail "couldn't get a first-page id"; return
  fi
  run_cli -w "$ws" list-events --limit 1 --before-id "$first_id"
  expect_ok "second page ok"
  local second_id; second_id="$(jq -r '.events[0].id' <<<"$LAST_OUT_TEXT")"
  if [[ -n "$second_id" && "$second_id" != "$first_id" ]]; then
    pass "before-id returned a different event"
  else
    fail "pagination didn't advance (got $second_id)"
  fi
}
