# shellcheck shell=bash
# Time-travel — fetching a specific version returns exactly the state
# at that version. Critical for the version history feature.

test_v1_snapshot_reflects_initial_content() {
  local ws; ws="$(mk_workspace ws-tt-v1)"
  local blocks; blocks="[$(block_paragraph 'original text')]"
  run_cli -w "$ws" create-doc --title "Doc1" --blocks "$blocks"
  expect_ok "create"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  # Bump to v2 with a modify
  run_cli -w "$ws" get-doc "$slug"
  local bid; bid="$(jq -r '.doc.blocks[0].id' <<<"$LAST_OUT_TEXT")"
  local ops; ops="[$(jq -nc --arg id "$bid" '{op:"modify_block",id:$id,patch:{content:[{text:"NEW"}]}}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops"
  expect_ok "bump to v2"
  # Now v1 snapshot should still have 'original text'.
  run_cli -w "$ws" get-version "$slug" 1
  expect_ok "get-version 1 ok"
  expect_eq ".doc.version_number" "1" "version is 1"
  expect_eq ".doc.blocks[0].content[0].text" "original text" "v1 still has original"
}

test_v2_snapshot_reflects_post_modify() {
  local ws; ws="$(mk_workspace ws-tt-v2)"
  local blocks; blocks="[$(block_paragraph 'orig')]"
  run_cli -w "$ws" create-doc --title "D" --blocks "$blocks"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  local bid; bid="$(jq -r '.doc.blocks[0].id' <<<"$LAST_OUT_TEXT")"
  local ops; ops="[$(jq -nc --arg id "$bid" '{op:"modify_block",id:$id,patch:{content:[{text:"changed"}]}}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops"
  expect_ok "v2"
  run_cli -w "$ws" get-version "$slug" 2
  expect_eq ".doc.blocks[0].content[0].text" "changed" "v2 has changed text"
}

test_intent_preserved_per_version() {
  local ws; ws="$(mk_workspace ws-tt-int)"
  local blocks; blocks="[$(block_paragraph 'p')]"
  run_cli -w "$ws" create-doc --title "T" --intent "first cut" --blocks "$blocks"
  expect_ok "v1 create"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  local ops; ops="[$(jq -nc --argjson b "$(block_paragraph 'extra')" '{op:"append_block",block:$b}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops" --intent "add detail"
  expect_ok "v2"
  run_cli -w "$ws" get-version "$slug" 1
  expect_eq ".doc.intent" "first cut" "v1 intent"
  run_cli -w "$ws" get-version "$slug" 2
  expect_eq ".doc.intent" "add detail" "v2 intent"
}

test_list_versions_chronological() {
  local ws; ws="$(mk_workspace ws-tt-chr)"
  local blocks; blocks="[$(block_paragraph 'p')]"
  run_cli -w "$ws" create-doc --title "C" --blocks "$blocks"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  for i in 1 2 3 4; do
    local ops; ops="[$(jq -nc --argjson b "$(block_paragraph "step $i")" '{op:"append_block",block:$b}')]"
    run_cli -w "$ws" apply-ops "$slug" --ops "$ops" --intent "step $i"
    expect_ok "bump v$((i+1))"
  done
  run_cli -w "$ws" list-versions "$slug"
  expect_ok "list-versions"
  expect_count ".versions" "5" "five versions total"
}

test_get_version_nonexistent_above_current() {
  local ws; ws="$(mk_workspace ws-tt-above)"
  local slug; slug="$(mk_doc "$ws" "Sole")"
  run_cli -w "$ws" get-version "$slug" 99
  expect_err "not_found" 4 "out-of-range version → not_found"
}

test_get_version_zero_or_negative_rejected() {
  local ws; ws="$(mk_workspace ws-tt-bad)"
  local slug; slug="$(mk_doc "$ws" "Sole")"
  run_cli -w "$ws" get-version "$slug" 0
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "version=0 errors"
  else
    fail "version=0 unexpectedly accepted"
  fi
}
