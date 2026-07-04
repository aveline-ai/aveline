# shellcheck shell=bash
# Workspace orientation doc — marked by the orientation boolean (one
# per workspace, constraint-enforced), seeded at workspace creation,
# undeletable, fetchable via get-orientation.

# Echoes the orientation doc's slug for a workspace.
orientation_slug() {
  run_cli -w "$1" get-orientation
  jq -r '.doc.slug' <<<"$LAST_OUT_TEXT"
}

test_orientation_seeded_on_workspace_create() {
  local ws; ws="$(mk_workspace orient-seed)"
  run_cli -w "$ws" get-orientation
  expect_ok "get-orientation on a fresh workspace"
  expect_eq '.doc.orientation' "true" "marked by the orientation flag"
  expect_eq '.doc.version_number' "1" "fresh template at v1"
}

test_orientation_appears_in_list_docs() {
  local ws; ws="$(mk_workspace orient-list)"
  run_cli -w "$ws" list-docs
  expect_ok "list-docs ok"
  if jq -e '.docs | map(select(.orientation)) | length == 1' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "orientation doc shows up in the normal list"
  else
    fail "orientation doc missing from list-docs"
  fi
}

test_orientation_cannot_be_deleted() {
  local ws; ws="$(mk_workspace orient-del)"
  local oslug; oslug="$(orientation_slug "$ws")"
  run_cli -w "$ws" delete-doc "$oslug"
  expect_err "orientation_undeletable" 2 "delete rejected with orientation_undeletable"
  run_cli -w "$ws" get-orientation
  expect_ok "orientation still there after delete attempt"
}

test_orientation_is_editable() {
  local ws; ws="$(mk_workspace orient-edit)"
  local oslug; oslug="$(orientation_slug "$ws")"
  run_cli -w "$ws" apply-ops "$oslug" --intent "fill in conventions" \
    --ops "[$(jq -nc '{op: "append_block", block: {type: "paragraph", content: [{text: "we ship on fridays"}]}}')]"
  expect_ok "apply-ops on orientation doc"
  expect_eq '.version_number' "2" "new version minted"
}

test_orientation_can_carry_doc_links() {
  local ws; ws="$(mk_workspace orient-links)"
  local target; target="$(mk_doc "$ws" "First stop")"

  local oslug; oslug="$(orientation_slug "$ws")"
  run_cli -w "$ws" apply-ops "$oslug" --intent "add first stop" \
    --ops "$(jq -nc --arg doc "$target" \
      '[{op: "append_block", block: {type: "doc_link", doc: $doc}}]')"
  expect_ok "doc_link added to orientation"

  run_cli -w "$ws" get-orientation
  expect_ok "get-orientation ok"
  expect_eq '.doc.blocks[-1].target.slug' "$target" "doc_link target echoed on orientation"
}
