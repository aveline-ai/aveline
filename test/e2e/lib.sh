# shellcheck shell=bash
# Assertion + driver helpers shared by every case file.
#
# The contract: every test function in cases/*.sh is `function_named_*`
# and is invoked by run.sh. Helpers below increment PASS / FAIL counters
# and print a compact diff so the runner can summarize at the end.

# ---- Global state ----------------------------------------------------

E2E_PASS=0
E2E_FAIL=0
E2E_FAILURES=()   # human strings, printed at end
E2E_CURRENT_CASE=""

# Colors (only when stdout is a TTY)
if [[ -t 1 ]]; then
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_DIM=$'\033[2m'
  C_BOLD=$'\033[1m'
  C_RESET=$'\033[0m'
else
  C_RED='' C_GREEN='' C_YELLOW='' C_DIM='' C_BOLD='' C_RESET=''
fi

# ---- CLI driver ------------------------------------------------------

# persona_xdg [persona] — return the XDG dir for a persona (defaults
# to $AVELINE_E2E_PERSONA, which defaults to alice).
persona_xdg() {
  local p="${1:-${AVELINE_E2E_PERSONA:-alice}}"
  printf "%s/%s" "$E2E_XDG" "$p"
}

# run_cli <args...>
#
# Runs `aveline <args>` as the current persona. Captures stdout to
# $LAST_OUT, stderr to $LAST_ERR, exit to $LAST_EXIT. Switch persona by
# setting AVELINE_E2E_PERSONA={alice,bob,carol} before the call.
run_cli() {
  LAST_OUT="$(mktemp)"
  LAST_ERR="$(mktemp)"
  XDG_CONFIG_HOME="$(persona_xdg)" \
    AVELINE_API_URL="$E2E_API_URL" \
    "$E2E_BIN" "$@" \
    >"$LAST_OUT" 2>"$LAST_ERR"
  LAST_EXIT=$?
  LAST_OUT_TEXT="$(cat "$LAST_OUT")"
  LAST_ERR_TEXT="$(cat "$LAST_ERR")"
}

# as_persona <persona> <cmd...> — invoke run_cli as a specific persona
# without touching the default.
as_persona() {
  local persona="$1"; shift
  local saved="${AVELINE_E2E_PERSONA:-alice}"
  AVELINE_E2E_PERSONA="$persona"
  run_cli "$@"
  AVELINE_E2E_PERSONA="$saved"
}

# ---- Assertion primitives --------------------------------------------

pass() {
  E2E_PASS=$((E2E_PASS + 1))
  printf "  %s✓%s %s\n" "$C_GREEN" "$C_RESET" "$1"
}

fail() {
  E2E_FAIL=$((E2E_FAIL + 1))
  local msg="$1"
  E2E_FAILURES+=("$E2E_CURRENT_CASE :: $msg")
  printf "  %s✗%s %s\n" "$C_RED" "$C_RESET" "$msg"
  if [[ -n "${LAST_OUT_TEXT:-}" || -n "${LAST_ERR_TEXT:-}" ]]; then
    printf "    %sstdout:%s %s\n" "$C_DIM" "$C_RESET" "$(printf '%s' "$LAST_OUT_TEXT" | head -c 400)"
    if [[ -n "${LAST_ERR_TEXT:-}" ]]; then
      printf "    %sstderr:%s %s\n" "$C_DIM" "$C_RESET" "$(printf '%s' "$LAST_ERR_TEXT" | head -c 400)"
    fi
    printf "    %sexit:%s %s\n" "$C_DIM" "$C_RESET" "${LAST_EXIT:-?}"
  fi
}

# expect_exit <expected> <message>
expect_exit() {
  local want="$1" msg="$2"
  if [[ "$LAST_EXIT" == "$want" ]]; then pass "$msg"; else fail "$msg (exit ${LAST_EXIT} != $want)"; fi
}

# expect_ok <message> — success envelope on stdout AND exit 0
expect_ok() {
  local msg="$1"
  if [[ "$LAST_EXIT" != "0" ]]; then
    fail "$msg (non-zero exit ${LAST_EXIT})"; return
  fi
  local ok
  ok="$(jq -r 'try .ok catch "?"' <<<"$LAST_OUT_TEXT" 2>/dev/null)"
  if [[ "$ok" != "true" ]]; then
    fail "$msg (ok != true; got: $(printf '%s' "$LAST_OUT_TEXT" | head -c 200))"
  else
    pass "$msg"
  fi
}

# expect_err <expected_code> <expected_exit> <message>
expect_err() {
  local want_code="$1" want_exit="$2" msg="$3"
  if [[ "$LAST_EXIT" == "0" ]]; then
    fail "$msg (expected error, got success: $(printf '%s' "$LAST_OUT_TEXT" | head -c 200))"
    return
  fi
  if [[ "$LAST_EXIT" != "$want_exit" ]]; then
    fail "$msg (exit ${LAST_EXIT} != $want_exit)"
    return
  fi
  local code
  code="$(jq -r 'try .error.code catch "?"' <<<"$LAST_ERR_TEXT" 2>/dev/null)"
  if [[ -z "$code" || "$code" == "null" ]]; then
    code="$(jq -r 'try .error.code catch "?"' <<<"$LAST_OUT_TEXT" 2>/dev/null)"
  fi
  if [[ "$code" != "$want_code" ]]; then
    fail "$msg (code '$code' != '$want_code')"
  else
    pass "$msg"
  fi
}

# expect_eq <jq-path> <expected-string> <message>
#
# Runs jq against $LAST_OUT_TEXT. Stringifies the result via -r so
# booleans round-trip ("true"/"false"). DO NOT use `// empty` here:
# jq's `//` operator treats `false` (and `null`) as fallthrough, which
# silently turns a real `false` into the empty string.
expect_eq() {
  local path="$1" want="$2" msg="$3"
  local got
  got="$(jq -r "$path" <<<"$LAST_OUT_TEXT" 2>/dev/null || echo "null")"
  if [[ "$got" == "$want" ]]; then pass "$msg"; else fail "$msg ('$got' != '$want')"; fi
}

# expect_present <jq-path> <message> — path resolves to a non-null value
# (false counts as present; only null or missing fails).
expect_present() {
  local path="$1" msg="$2"
  if jq -e "($path) != null" <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "$msg"
  else
    fail "$msg (missing $path)"
  fi
}

# expect_absent <jq-path> <message> — path is null or missing.
expect_absent() {
  local path="$1" msg="$2"
  if jq -e "($path) != null" <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    local got
    got="$(jq -r "$path" <<<"$LAST_OUT_TEXT" 2>/dev/null || echo "?")"
    fail "$msg (unexpected $path = $got)"
  else
    pass "$msg"
  fi
}

# Docs the test itself created — excludes the seeded orientation doc
# (orientation: true) that every workspace ships with.
MY_DOCS='.docs | map(select(.orientation | not))'

# expect_count <jq-array-path> <expected-int> <message>
expect_count() {
  local path="$1" want="$2" msg="$3"
  local got
  got="$(jq -r "$path | length" <<<"$LAST_OUT_TEXT" 2>/dev/null || echo "?")"
  if [[ "$got" == "$want" ]]; then pass "$msg"; else fail "$msg (count $got != $want)"; fi
}

# expect_contains <jq-path-to-array> <substring> <message>
#
# Asserts at least one element matches; element compared as JSON.
expect_contains() {
  local path="$1" needle="$2" msg="$3"
  if jq -e "$path | any(. == \"$needle\")" <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "$msg"
  else
    fail "$msg (no element of $path == '$needle')"
  fi
}

# ---- Case scaffolding ------------------------------------------------

begin_case() {
  E2E_CURRENT_CASE="$1"
  printf "\n%s▸ %s%s\n" "$C_BOLD" "$E2E_CURRENT_CASE" "$C_RESET"
}

# Unique slug helper. Combines PID + epoch nanoseconds + RANDOM so two
# concurrent test functions can never collide even if invoked in the same
# millisecond. The output stays inside slug rules: [a-z0-9-]+.
us() {
  local nanos="${RANDOM}${RANDOM}"
  local prefix; prefix="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
  printf "%s-%s%s" "$prefix" "$$" "$nanos"
}

# ---- Test fixtures ---------------------------------------------------
#
# Every helper below sets up state OWNED by the calling test. None depend
# on the seeded data (other than the seeded user tokens). Each helper
# echoes a single identifier on success and dies loud on failure so a
# broken fixture never gets confused with a real test failure.

# mk_workspace [label] — create a fresh workspace owned by alice and echo
# its slug. Use the returned slug for every subsequent call in the test.
mk_workspace() {
  local label="${1:-ws}"
  local slug; slug="$(us "$label")"
  local out
  out="$( XDG_CONFIG_HOME="$(persona_xdg)" AVELINE_API_URL="$E2E_API_URL" \
           "$E2E_BIN" create-workspace --name "$label" --slug "$slug" 2>&1 )" || {
    echo "mk_workspace failed: $out" >&2
    return 1
  }
  printf "%s" "$slug"
}

# mk_tag <ws> <name> [description] — create a tag in <ws>. Echoes the
# tag slug. Description defaults to a stock placeholder that satisfies
# the server's 6-280 char rule.
mk_tag() {
  local ws="$1" name="$2"
  local desc="${3:-test tag $name}"
  XDG_CONFIG_HOME="$(persona_xdg)" AVELINE_API_URL="$E2E_API_URL" \
    "$E2E_BIN" -w "$ws" create-tag --name "$name" --description "$desc" >/dev/null 2>&1 || {
    echo "mk_tag failed for $name in $ws" >&2; return 1
  }
  printf "%s" "$name"
}

# block_paragraph <text> — emit a minimal valid paragraph block JSON.
block_paragraph() {
  jq -nc --arg text "$1" '{type: "paragraph", content: [{text: $text}]}'
}

# block_heading <level> <text>
block_heading() {
  jq -nc --arg text "$2" --argjson level "$1" \
    '{type: "heading", level: $level, text: $text}'
}

# mk_doc <ws> [title] [tag1,tag2,...] — create a doc and echo its slug.
# Tags must already exist (use mk_tag first); the helper will create them
# if absent. Always uses agent actor.
mk_doc() {
  local ws="$1"
  local title="${2:-Doc $(us t)}"
  local tagcsv="${3:-}"
  # Build a minimal blocks array — ONE block so version-count math in
  # tests stays simple. Tests that need more blocks should append via
  # apply-ops.
  local blocks; blocks="[$(block_paragraph "$title body")]"
  local args=(-w "$ws" create-doc --title "$title" --blocks "$blocks")
  if [[ -n "$tagcsv" ]]; then
    IFS=',' read -ra arr <<<"$tagcsv"
    for t in "${arr[@]}"; do
      mk_tag "$ws" "$t" >/dev/null
      args+=(--tag "$t")
    done
  fi
  local out
  out="$( XDG_CONFIG_HOME="$(persona_xdg)" AVELINE_API_URL="$E2E_API_URL" \
           "$E2E_BIN" "${args[@]}" 2>&1 )" || {
    echo "mk_doc failed: $out" >&2; return 1
  }
  jq -r '.slug' <<<"$out"
}

# mk_comment <ws> <doc-slug> <body> — top-level comment. Echoes id.
mk_comment() {
  local ws="$1" doc="$2" body="$3"
  local out
  out="$( XDG_CONFIG_HOME="$(persona_xdg)" AVELINE_API_URL="$E2E_API_URL" \
           "$E2E_BIN" -w "$ws" create-comment "$doc" --body "$body" 2>&1 )" || {
    echo "mk_comment failed: $out" >&2; return 1
  }
  jq -r '.id' <<<"$out"
}

# add_member <ws> <username> — adds a seeded user to <ws>. No-op if
# already a member.
add_member() {
  local ws="$1" username="$2"
  XDG_CONFIG_HOME="$(persona_xdg)" AVELINE_API_URL="$E2E_API_URL" \
    "$E2E_BIN" -w "$ws" add-member --username "$username" >/dev/null 2>&1 || true
}
