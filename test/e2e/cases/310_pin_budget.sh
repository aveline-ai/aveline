# shellcheck shell=bash
# Pin budget — 6 pinned docs per workspace (GitHub-style). The
# orientation doc permanently holds slot 1; humans/agents pick the rest.

test_pin_budget_caps_at_six() {
  local ws; ws="$(mk_workspace pin-cap)"
  local blocks; blocks="[$(block_paragraph 'body')]"

  # Orientation holds slot 1; fill slots 2-6.
  for i in 1 2 3 4 5; do
    run_cli -w "$ws" create-doc --title "Pin $i" --pin --blocks "$blocks"
    expect_ok "pin slot filled ($i of 5)"
  done

  run_cli -w "$ws" create-doc --title "One too many" --pin --blocks "$blocks"
  expect_err "pin_limit_reached" 2 "7th pin rejected with pin_limit_reached"
}

test_pin_budget_frees_on_unpin() {
  local ws; ws="$(mk_workspace pin-free)"
  local blocks; blocks="[$(block_paragraph 'body')]"

  for i in 1 2 3 4 5; do
    run_cli -w "$ws" create-doc --title "Pin $i" --pin --blocks "$blocks"
  done

  # Budget full — unpin one, then the next pin succeeds.
  run_cli -w "$ws" apply-ops pin-1 --unpin --intent "free a slot" --ops "[]"
  expect_ok "unpin frees a slot"

  run_cli -w "$ws" create-doc --title "Fits now" --pin --blocks "$blocks"
  expect_ok "pin succeeds after freeing a slot"
}

test_orientation_cannot_be_unpinned() {
  local ws; ws="$(mk_workspace pin-orient)"
  run_cli -w "$ws" apply-ops agents --unpin --intent "try to unpin" --ops "[]"
  expect_err "orientation_pin_required" 2 "unpinning orientation rejected"
}
