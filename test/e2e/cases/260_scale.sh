# shellcheck shell=bash
# Scale — many blocks, many comments, many versions. Catches O(n²)
# regressions and serialization size issues.

test_doc_with_thirty_blocks() {
  local ws; ws="$(mk_workspace ws-sc-30)"
  # Build 30 paragraph blocks inline.
  local parts=""
  for i in $(seq 1 30); do
    [[ -z "$parts" ]] || parts+=","
    parts+="$(block_paragraph "block #$i")"
  done
  local blocks="[$parts]"
  run_cli -w "$ws" create-doc --title "Big" --blocks "$blocks"
  expect_ok "create 30-block doc"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  expect_count ".doc.blocks" "30" "all 30 blocks round-trip"
}

test_doc_with_ten_versions() {
  local ws; ws="$(mk_workspace ws-sc-10v)"
  local slug; slug="$(mk_doc "$ws" "Iter")"
  for i in $(seq 1 9); do
    local ops; ops="[$(jq -nc --argjson b "$(block_paragraph "v$((i+1))")" '{op:"append_block",block:$b}')]"
    run_cli -w "$ws" apply-ops "$slug" --ops "$ops"
    expect_ok "bump to v$((i+1))"
  done
  run_cli -w "$ws" list-versions "$slug"
  expect_count ".versions" "10" "10 versions total"
  run_cli -w "$ws" get-doc "$slug"
  expect_eq ".doc.version_number" "10" "current is v10"
}

test_doc_with_many_comments() {
  local ws; ws="$(mk_workspace ws-sc-cm)"
  local slug; slug="$(mk_doc "$ws" "TalkPiece")"
  for i in $(seq 1 15); do
    mk_comment "$ws" "$slug" "remark $i" >/dev/null
  done
  run_cli -w "$ws" list-comments "$slug"
  expect_ok "list-comments ok"
  # At least 15 entries surface (exact shape may vary based on
  # thread-rendering).
  local count
  count="$(jq '[..|objects|select(.body? != null)] | length' <<<"$LAST_OUT_TEXT")"
  if [[ "$count" -ge "15" ]]; then
    pass "all 15 comments returned (count=$count)"
  else
    fail "only $count comments returned (expected ≥ 15)"
  fi
}

test_list_docs_with_many_docs() {
  local ws; ws="$(mk_workspace ws-sc-many)"
  for i in $(seq 1 25); do
    mk_doc "$ws" "D$i" >/dev/null
  done
  run_cli -w "$ws" list-docs
  expect_ok "list-docs ok"
  expect_count ".docs" "25" "25 docs"
}

test_apply_ops_with_many_ops_in_one_call() {
  local ws; ws="$(mk_workspace ws-sc-ops)"
  local slug; slug="$(mk_doc "$ws" "Many")"
  # Build 10 append_block ops in one array.
  local ops_parts=""
  for i in $(seq 1 10); do
    [[ -z "$ops_parts" ]] || ops_parts+=","
    ops_parts+="$(jq -nc --argjson b "$(block_paragraph "appended $i")" '{op:"append_block",block:$b}')"
  done
  local ops="[$ops_parts]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops"
  expect_ok "10 ops in one call"
  run_cli -w "$ws" get-doc "$slug"
  expect_count ".doc.blocks" "11" "11 blocks total (orig + 10 appended)"
  expect_eq ".doc.version_number" "2" "single version bump from 10 ops"
}
