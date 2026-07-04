# shellcheck shell=bash
# Home-page pin slots — 6 numbered slots per workspace, set via
# pin-doc/unpin-doc. Occupied slots never displace silently. The
# orientation doc has its own card and can't be slotted.

# Creates a plain doc and echoes its slug.
mk_plain() {
  local ws="$1" title="$2"
  run_cli -w "$ws" create-doc --title "$title" --blocks "[$(block_paragraph 'body')]"
  jq -r '.slug' <<<"$LAST_OUT_TEXT"
}

test_pin_explicit_and_auto_slots() {
  local ws; ws="$(mk_workspace pin-slots)"
  local a b
  a="$(mk_plain "$ws" "Doc A")"
  b="$(mk_plain "$ws" "Doc B")"

  run_cli -w "$ws" pin-doc "$a" --slot 3
  expect_ok "explicit slot 3"
  expect_eq ".pin_slot" "3" "slot echoed"

  run_cli -w "$ws" pin-doc "$b"
  expect_ok "auto-assign"
  expect_eq ".pin_slot" "1" "lowest free slot taken"
}

test_pin_occupied_slot_rejected() {
  local ws; ws="$(mk_workspace pin-occupied)"
  local a b
  a="$(mk_plain "$ws" "Holder")"
  b="$(mk_plain "$ws" "Challenger")"

  run_cli -w "$ws" pin-doc "$a" --slot 2
  expect_ok "slot 2 taken"
  run_cli -w "$ws" pin-doc "$b" --slot 2
  expect_err "pin_slot_taken" 2 "occupied slot → pin_slot_taken"
  if grep -q "$a" <<<"$LAST_ERR_TEXT"; then
    pass "error names the occupant"
  else
    fail "occupant slug missing from error"
  fi
}

test_pin_budget_caps_at_six() {
  local ws; ws="$(mk_workspace pin-cap)"
  for i in 1 2 3 4 5 6; do
    local s; s="$(mk_plain "$ws" "Pin $i")"
    run_cli -w "$ws" pin-doc "$s"
    expect_ok "slot filled ($i of 6)"
  done

  local extra; extra="$(mk_plain "$ws" "One too many")"
  run_cli -w "$ws" pin-doc "$extra"
  expect_err "pin_limit_reached" 2 "7th pin rejected with pin_limit_reached"

  # Unpin one → the next pin succeeds.
  run_cli -w "$ws" unpin-doc "pin-3"
  expect_ok "unpin frees a slot"
  run_cli -w "$ws" pin-doc "$extra"
  expect_ok "pin succeeds after freeing a slot"
}

test_pin_invalid_slot_rejected() {
  local ws; ws="$(mk_workspace pin-invalid)"
  local s; s="$(mk_plain "$ws" "Doc")"
  run_cli -w "$ws" pin-doc "$s" --slot 9
  expect_err "validation_failed" 2 "slot 9 → validation_failed"
}

test_orientation_cannot_take_a_slot() {
  local ws; ws="$(mk_workspace pin-orient)"
  run_cli -w "$ws" get-orientation
  local oslug; oslug="$(jq -r '.doc.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" pin-doc "$oslug" --slot 1
  expect_err "validation_failed" 2 "orientation doc can't be slotted"
}

test_unpin_unpinned_doc_rejected() {
  local ws; ws="$(mk_workspace pin-nounpin)"
  local s; s="$(mk_plain "$ws" "Loose")"
  run_cli -w "$ws" unpin-doc "$s"
  expect_err "validation_failed" 2 "unpinning an unpinned doc errors"
}
