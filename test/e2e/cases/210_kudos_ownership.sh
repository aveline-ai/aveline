# shellcheck shell=bash
# Kudos + ownership invariants.

test_kudos_toggle_returns_new_state() {
  local ws; ws="$(mk_workspace ws-k-tog)"
  local slug; slug="$(mk_doc "$ws" "OwnedByAlice")"
  add_member "$ws" "bob"
  AVELINE_E2E_PERSONA=bob run_cli -w "$ws" kudos-doc "$slug"
  expect_ok "bob kudos ok"
  # Toggle off
  AVELINE_E2E_PERSONA=bob run_cli -w "$ws" kudos-doc "$slug"
  expect_ok "bob kudos toggle off ok"
}

test_multiple_users_kudos_accumulates() {
  local ws; ws="$(mk_workspace ws-k-acc)"
  local slug; slug="$(mk_doc "$ws" "Popular")"
  add_member "$ws" "bob"
  add_member "$ws" "carol"
  AVELINE_E2E_PERSONA=bob   run_cli -w "$ws" kudos-doc "$slug"
  expect_ok "bob kudos"
  AVELINE_E2E_PERSONA=carol run_cli -w "$ws" kudos-doc "$slug"
  expect_ok "carol kudos"
}

test_self_kudos_blocked_even_after_doc_edit() {
  local ws; ws="$(mk_workspace ws-k-selfedit)"
  local slug; slug="$(mk_doc "$ws" "Mine")"
  local ops; ops="[$(jq -nc --argjson b "$(block_paragraph 'x')" \
    '{op:"append_block", block:$b}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops"
  expect_ok "apply-ops ok"
  run_cli -w "$ws" kudos-doc "$slug"
  expect_err "self_kudos" 2 "self_kudos still blocked after own edits"
}

test_kudos_on_deleted_doc_errors() {
  local ws; ws="$(mk_workspace ws-k-del)"
  local slug; slug="$(mk_doc "$ws" "Gone")"
  run_cli -w "$ws" delete-doc "$slug"
  expect_ok "deleted"
  add_member "$ws" "bob"
  AVELINE_E2E_PERSONA=bob run_cli -w "$ws" kudos-doc "$slug"
  expect_err "not_found" 4 "kudos on deleted doc → not_found"
}

test_doc_lists_show_owner() {
  local ws; ws="$(mk_workspace ws-k-own)"
  mk_doc "$ws" "ByAlice" >/dev/null
  run_cli -w "$ws" list-docs
  expect_ok "list-docs ok"
  expect_eq ".docs[0].owner.username" "alice" "owner is alice"
}

test_doc_owner_persists_across_apply_ops() {
  # apply-ops doesn't change ownership even if a different user calls
  # it (currently bob isn't allowed to apply-ops on alice's doc; this
  # asserts the owner field stays alice on her own edits).
  local ws; ws="$(mk_workspace ws-k-own-stable)"
  local slug; slug="$(mk_doc "$ws" "Stable")"
  local ops; ops="[$(jq -nc --argjson b "$(block_paragraph 'y')" \
    '{op:"append_block", block:$b}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops"
  expect_ok "apply ok"
  run_cli -w "$ws" get-doc "$slug"
  expect_eq ".doc.owner.username" "alice" "owner remains alice"
}
