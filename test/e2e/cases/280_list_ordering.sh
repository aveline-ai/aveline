# shellcheck shell=bash
# List ordering — sort semantics (pins are a home-page concept, not a sort).

test_list_docs_recent_first() {
  local ws; ws="$(mk_workspace ws-lo-rec)"
  mk_doc "$ws" "Old"  >/dev/null
  sleep 1
  mk_doc "$ws" "Mid"  >/dev/null
  sleep 1
  mk_doc "$ws" "Last" >/dev/null
  run_cli -w "$ws" list-docs
  # Last-modified comes first.
  expect_eq "$MY_DOCS | .[0].title" "Last" "newest first"
}

test_list_versions_descending_by_number() {
  local ws; ws="$(mk_workspace ws-lo-ver)"
  local slug; slug="$(mk_doc "$ws" "V")"
  for i in 1 2 3; do
    local ops; ops="[$(jq -nc --argjson b "$(block_paragraph "v$((i+1))")" '{op:"append_block",block:$b}')]"
    run_cli -w "$ws" apply-ops "$slug" --ops "$ops"
  done
  run_cli -w "$ws" list-versions "$slug"
  expect_count ".versions" "4" "4 versions"
  # First entry should be the highest version_number.
  local first; first="$(jq -r '.versions[0].version_number' <<<"$LAST_OUT_TEXT")"
  if [[ "$first" == "4" ]]; then
    pass "versions are newest-first"
  else
    fail "versions ordering wrong (first=$first)"
  fi
}

test_list_events_newest_first() {
  local ws; ws="$(mk_workspace ws-lo-ev)"
  mk_doc "$ws" "First" >/dev/null
  sleep 1
  mk_doc "$ws" "Last"  >/dev/null
  run_cli -w "$ws" list-events --limit 5
  expect_ok "events ok"
  local first_slug
  first_slug="$(jq -r '.events[0].target_slug' <<<"$LAST_OUT_TEXT")"
  # Last-created doc's slug should be in the first event slot.
  if [[ "$first_slug" == "last" ]]; then
    pass "events newest-first (target_slug=last)"
  else
    fail "events newest-first wrong (got $first_slug)"
  fi
}

test_list_tags_includes_usage_counts() {
  local ws; ws="$(mk_workspace ws-lo-tags)"
  mk_tag "$ws" "popular" >/dev/null
  mk_doc "$ws" "D1" "popular" >/dev/null
  mk_doc "$ws" "D2" "popular" >/dev/null
  run_cli -w "$ws" list-tags
  expect_ok "list-tags ok"
  local count
  count="$(jq -r '.tags[0].doc_count // 0' <<<"$LAST_OUT_TEXT")"
  if [[ "$count" -ge "2" ]]; then
    pass "tag doc_count surfaces ($count)"
  else
    fail "tag doc_count missing or wrong (got $count)"
  fi
}
