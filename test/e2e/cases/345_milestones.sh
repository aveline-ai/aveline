# shellcheck shell=bash
# Timeline milestones — dated facts that annotate time-series charts.

test_milestone_round_trip() {
  local ws; ws="$(mk_workspace ws-tl)"

  run_cli -w "$ws" create-milestone --name "v1.4 shipped" --date 2026-07-06 \
    --description "the big release"
  expect_ok "create-milestone ok"
  local id; id="$(jq -r '.milestone.id' <<<"$LAST_OUT_TEXT")"
  expect_eq '.milestone.date' "2026-07-06" "date echoed"

  run_cli -w "$ws" create-milestone --name "pricing change" --date 2026-07-10
  expect_ok "second milestone ok"

  run_cli -w "$ws" list-milestones
  expect_ok "list ok"
  expect_count '.milestones' "2" "both listed"
  expect_eq '.milestones[0].name' "v1.4 shipped" "oldest first"

  run_cli -w "$ws" delete-milestone "$id"
  expect_ok "delete ok"
  run_cli -w "$ws" list-milestones
  expect_count '.milestones' "1" "deleted milestone gone"
}

test_milestone_validation() {
  local ws; ws="$(mk_workspace ws-tl-bad)"

  run_cli -w "$ws" create-milestone --name "bad" --date "not-a-date"
  expect_err "validation_failed" 2 "garbage date refused"

  run_cli -w "$ws" delete-milestone "00000000-0000-0000-0000-000000000000"
  expect_err "not_found" 4 "unknown id → not_found"
}
