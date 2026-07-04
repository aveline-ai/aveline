# shellcheck shell=bash
# doc_link blocks — links as plain blocks in plain docs. Covers slug→id
# resolution, workspace scoping, the read-time target echo, and
# deleted-target behavior.

# Local helper: doc_link block by slug, with a note.
block_doc_link() {
  jq -nc --arg doc "$1" --arg note "$2" \
    '{type: "doc_link", doc: $doc, note: [{text: $note}]}'
}

test_doc_link_slug_resolves_to_base_doc_id() {
  local ws; ws="$(mk_workspace dl-resolve)"
  local target; target="$(mk_doc "$ws" "Target One")"

  run_cli -w "$ws" get-doc "$target"
  local base; base="$(jq -r '.doc.base_doc_id' <<<"$LAST_OUT_TEXT")"

  run_cli -w "$ws" create-doc --title "Story $(us s)" \
    --blocks "[$(block_doc_link "$target" "start here")]"
  expect_ok "create story with slug-form doc_link"
  local story; story="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"

  run_cli -w "$ws" get-doc "$story"
  expect_ok "get story"
  expect_eq '.doc.blocks[0].doc_id' "$base" "slug resolved to target base_doc_id"
  expect_absent '.doc.blocks[0].doc' "slug form not persisted"
}

test_doc_link_echoes_target_metadata() {
  local ws; ws="$(mk_workspace dl-echo)"
  local target; target="$(mk_doc "$ws" "Echo Target")"

  run_cli -w "$ws" create-doc --title "Story $(us s)" \
    --blocks "[$(block_doc_link "$target" "why this stop")]"
  local story; story="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"

  run_cli -w "$ws" get-doc "$story"
  expect_eq '.doc.blocks[0].target.slug' "$target" "target slug echoed"
  expect_eq '.doc.blocks[0].target.title' "Echo Target" "target title echoed"
  expect_eq '.doc.blocks[0].target.deleted' "false" "target not deleted"
  expect_present '.doc.blocks[0].target.updated_at' "target updated_at echoed"
}

test_doc_link_unknown_slug_rejected() {
  local ws; ws="$(mk_workspace dl-unknown)"
  run_cli -w "$ws" create-doc --title "Bad story" \
    --blocks "[$(block_doc_link "ghost-$(us g)" "nope")]"
  expect_err "doc_link_target_not_found" 2 "unknown slug → doc_link_target_not_found / exit 2"
}

test_doc_link_cross_workspace_id_rejected() {
  local ws_a; ws_a="$(mk_workspace dl-cross-a)"
  local ws_b; ws_b="$(mk_workspace dl-cross-b)"
  local target; target="$(mk_doc "$ws_a" "A-only doc")"

  run_cli -w "$ws_a" get-doc "$target"
  local base; base="$(jq -r '.doc.base_doc_id' <<<"$LAST_OUT_TEXT")"

  run_cli -w "$ws_b" create-doc --title "Cross story" \
    --blocks "$(jq -nc --arg id "$base" '[{type: "doc_link", doc_id: $id}]')"
  expect_err "doc_link_target_not_found" 2 "other workspace's doc_id rejected"
}

test_doc_link_non_uuid_doc_id_rejected() {
  local ws; ws="$(mk_workspace dl-baduuid)"
  run_cli -w "$ws" create-doc --title "Bad id story" \
    --blocks '[{"type": "doc_link", "doc_id": "not-a-uuid"}]'
  expect_err "validation_failed" 2 "non-UUID doc_id → validation_failed"
}

test_doc_link_multiple_links_echo_in_order() {
  local ws; ws="$(mk_workspace dl-order)"
  local one; one="$(mk_doc "$ws" "Stop One")"
  local two; two="$(mk_doc "$ws" "Stop Two")"

  run_cli -w "$ws" create-doc --title "Ordered story $(us s)" \
    --blocks "[$(block_doc_link "$one" "first"), $(block_doc_link "$two" "second")]"
  local story; story="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"

  run_cli -w "$ws" get-doc "$story"
  expect_ok "get-doc ok"
  expect_eq '.doc.blocks | map(select(.type == "doc_link")) | length' "2" "two doc_link blocks"
  expect_eq '.doc.blocks[0].target.slug' "$one" "block order preserved (first)"
  expect_eq '.doc.blocks[1].target.slug' "$two" "block order preserved (second)"
}

test_doc_link_deleted_target_becomes_stub() {
  local ws; ws="$(mk_workspace dl-deleted)"
  local target; target="$(mk_doc "$ws" "Doomed doc")"

  run_cli -w "$ws" create-doc --title "Story $(us s)" \
    --blocks "[$(block_doc_link "$target" "still points here")]"
  local story; story="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"

  run_cli -w "$ws" delete-doc "$target"
  expect_ok "delete target"

  run_cli -w "$ws" get-doc "$story"
  expect_eq '.doc.blocks[0].target.deleted' "true" "echo flags deleted target"
  expect_eq '.doc.blocks[0].target.title' "Doomed doc" "deleted target keeps metadata"

  run_cli -w "$ws" restore-doc "$target"
  expect_ok "restore target"

  run_cli -w "$ws" get-doc "$story"
  expect_eq '.doc.blocks[0].target.deleted' "false" "restored stop comes back"
}

test_doc_link_modify_block_reanchors_to_new_slug() {
  local ws; ws="$(mk_workspace dl-modify)"
  local one; one="$(mk_doc "$ws" "Old stop")"
  local two; two="$(mk_doc "$ws" "New stop")"

  run_cli -w "$ws" create-doc --title "Story $(us s)" \
    --blocks "[$(block_doc_link "$one" "points at old")]"
  local story; story="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"

  run_cli -w "$ws" get-doc "$story"
  local block_id; block_id="$(jq -r '.doc.blocks[0].id' <<<"$LAST_OUT_TEXT")"

  run_cli -w "$ws" get-doc "$two"
  local base_two; base_two="$(jq -r '.doc.base_doc_id' <<<"$LAST_OUT_TEXT")"

  run_cli -w "$ws" apply-ops "$story" --intent "swap stop" \
    --ops "$(jq -nc --arg id "$block_id" --arg doc "$two" \
      '[{op: "modify_block", id: $id, patch: {doc: $doc}}]')"
  expect_ok "modify_block with new slug"

  run_cli -w "$ws" get-doc "$story"
  expect_eq '.doc.blocks[0].doc_id' "$base_two" "link reanchored to new target"
  expect_eq '.doc.blocks[0].target.slug' "$two" "echo follows the new target"
}

test_doc_link_stale_echo_stripped_on_write() {
  local ws; ws="$(mk_workspace dl-strip)"
  local target; target="$(mk_doc "$ws" "Real title")"

  run_cli -w "$ws" get-doc "$target"
  local base; base="$(jq -r '.doc.base_doc_id' <<<"$LAST_OUT_TEXT")"

  # Paste a block that carries a stale/forged target echo — the server
  # must rebuild the block from schema fields and drop it.
  run_cli -w "$ws" create-doc --title "Story $(us s)" \
    --blocks "$(jq -nc --arg id "$base" \
      '[{type: "doc_link", doc_id: $id, target: {title: "FORGED", deleted: false}}]')"
  expect_ok "create with forged target accepted"
  local story; story="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"

  run_cli -w "$ws" get-doc "$story"
  expect_eq '.doc.blocks[0].target.title' "Real title" "echo is fresh, not the pasted one"
}
