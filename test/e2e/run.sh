#!/usr/bin/env bash
# End-to-end test runner.
#
# What this does:
#   1. Boots Phoenix on an isolated port (4099) against an isolated
#      DB (aveline_e2e) — your normal dev server and DB are untouched.
#   2. Resets + seeds that DB.
#   3. Builds the CLI binary.
#   4. Sources every cases/*.sh in order and runs every function named
#      `test_*` it defines.
#   5. Tears down the server. Reports pass/fail and exits non-zero if
#      anything failed.
#
# Usage:
#   ./test/e2e/run.sh                # run everything
#   ./test/e2e/run.sh 050_           # only files whose name matches glob
#   ./test/e2e/run.sh -k slug_taken  # only test functions whose name matches
#
# Requirements: bash 4+, jq, mix, postgres reachable via the standard env
# vars (PGUSER/PGPASSWORD/PGHOST), Go 1.22+.
#
# The CLI repo is expected at ../cli relative to the aveline repo root.

set -uo pipefail

# ---- Paths -----------------------------------------------------------

E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AVELINE_DIR="$(cd "$E2E_DIR/../.." && pwd)"
CLI_DIR="$(cd "$AVELINE_DIR/../cli" && pwd)"
CASES_DIR="$E2E_DIR/cases"

# ---- Config (export so children see it) ------------------------------

export E2E_PORT="${E2E_PORT:-4099}"
export E2E_API_URL="http://localhost:$E2E_PORT"
export E2E_DB_NAME="${E2E_DB_NAME:-aveline_e2e}"
export E2E_BIN="$CLI_DIR/bin/aveline-e2e"
export E2E_XDG="$(mktemp -d -t aveline-e2e-xdg.XXXXXX)"

# Seeded credentials — these are hardcoded in priv/repo/seeds.exs. If
# the seed changes, update both sides.
export E2E_TOKEN_ALICE="avl_locseed_alice_aaaaaaaaaaaaaaaaaa"
export E2E_TOKEN_BOB="avl_locseed_bob_bbbbbbbbbbbbbbbbbbbb"
export E2E_TOKEN_CAROL="avl_locseed_carol_cccccccccccccccccc"
export E2E_WORKSPACE="local-pod"

# ---- Args ------------------------------------------------------------

ONLY_FILES="*"
ONLY_TESTS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -k) ONLY_TESTS="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^set -uo/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) ONLY_FILES="$1"; shift ;;
  esac
done

# ---- Logging ---------------------------------------------------------

log() { printf "\033[36m▸\033[0m %s\n" "$*" >&2; }
die() { printf "\033[31m✗ %s\033[0m\n" "$*" >&2; exit 1; }

# Recursively collect SERVER_PID + all of its descendants. `mix
# phx.server` spawns beam.smp, possibly with esbuild/tzdata as
# grandchildren; killing only the top doesn't always reach beam.
_descendants() {
  local parent="$1"
  local kids; kids="$(pgrep -P "$parent" 2>/dev/null || true)"
  for k in $kids; do
    _descendants "$k"
  done
  echo "$parent"
}

cleanup() {
  if [[ -n "${SERVER_PID:-}" ]]; then
    local pids; pids="$(_descendants "$SERVER_PID" 2>/dev/null | sort -u)"
    if [[ -n "$pids" ]]; then
      kill -TERM $pids 2>/dev/null || true
      # Give beam ~2s to shut down cleanly.
      for _ in 1 2 3 4; do
        if ! kill -0 $pids 2>/dev/null; then break; fi
        sleep 0.5
      done
      kill -KILL $pids 2>/dev/null || true
    fi
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  # Final sweep — kill anyone still on our port. Safe because port
  # 4099 is e2e-owned.
  if lsof -nP -iTCP:"$E2E_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    lsof -nP -iTCP:"$E2E_PORT" -sTCP:LISTEN -t 2>/dev/null \
      | xargs kill -TERM 2>/dev/null || true
    sleep 1
    lsof -nP -iTCP:"$E2E_PORT" -sTCP:LISTEN -t 2>/dev/null \
      | xargs kill -KILL 2>/dev/null || true
  fi
  if [[ -d "${E2E_XDG:-}" ]]; then rm -rf "$E2E_XDG"; fi
}
trap cleanup EXIT INT TERM

# ---- Pre-flight ------------------------------------------------------

command -v jq  >/dev/null || die "jq not on PATH"
command -v mix >/dev/null || die "mix not on PATH"
command -v go  >/dev/null || die "go not on PATH"

# Reclaim our port if a previous run leaked a process. Since port 4099
# is e2e-only, killing whatever's there is safe — it's either an
# orphaned mix/beam from a prior crash or someone else has stolen our
# port (rare). If reclamation fails, the user can pick a different
# port via E2E_PORT.
if lsof -nP -iTCP:"$E2E_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  log "Port $E2E_PORT is in use — assuming orphaned e2e process and reclaiming"
  lsof -nP -iTCP:"$E2E_PORT" -sTCP:LISTEN -t 2>/dev/null \
    | xargs -r kill -TERM 2>/dev/null || true
  sleep 1
  if lsof -nP -iTCP:"$E2E_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    lsof -nP -iTCP:"$E2E_PORT" -sTCP:LISTEN -t 2>/dev/null \
      | xargs -r kill -KILL 2>/dev/null || true
    sleep 1
  fi
  if lsof -nP -iTCP:"$E2E_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    die "couldn't reclaim port $E2E_PORT — set E2E_PORT=<free port> or stop the process manually"
  fi
fi

# ---- Build CLI -------------------------------------------------------

log "Building CLI -> $E2E_BIN"
( cd "$CLI_DIR" && mkdir -p bin && go build -o "$E2E_BIN" ./cmd/aveline ) \
  || die "CLI build failed"

# ---- Reset + seed DB --------------------------------------------------

log "Resetting DB '$E2E_DB_NAME'"
(
  cd "$AVELINE_DIR"
  PGDATABASE="$E2E_DB_NAME" MIX_ENV=dev mix ecto.drop --quiet 2>/dev/null || true
  PGDATABASE="$E2E_DB_NAME" MIX_ENV=dev mix ecto.create --quiet
  PGDATABASE="$E2E_DB_NAME" MIX_ENV=dev mix ecto.migrate --quiet
  PGDATABASE="$E2E_DB_NAME" MIX_ENV=dev mix run priv/repo/seeds.exs
) > "$E2E_DIR/.seed.log" 2>&1 || { cat "$E2E_DIR/.seed.log"; die "DB reset failed"; }

# Pre-populate one config per persona so tests can switch users by
# selecting an XDG dir. No `aveline login` needed.
for persona in alice bob carol; do
  d="$E2E_XDG/$persona"
  mkdir -p "$d/aveline"
  case "$persona" in
    alice) tok="$E2E_TOKEN_ALICE" ;;
    bob)   tok="$E2E_TOKEN_BOB" ;;
    carol) tok="$E2E_TOKEN_CAROL" ;;
  esac
  cat > "$d/aveline/config.toml" <<EOF
api_url   = "$E2E_API_URL"
token     = "$tok"
EOF
  chmod 600 "$d/aveline/config.toml"
done

# ---- Boot server -----------------------------------------------------

log "Booting Phoenix on :$E2E_PORT"
(
  cd "$AVELINE_DIR"
  PGDATABASE="$E2E_DB_NAME" \
  PORT="$E2E_PORT" \
  MIX_ENV=dev \
  mix phx.server > "$E2E_DIR/.server.log" 2>&1
) &
SERVER_PID=$!

# Wait for /api/heartbeat to come up. 30s should be plenty.
log "Waiting for server …"
for _ in $(seq 1 60); do
  if curl -fsS "$E2E_API_URL/api/heartbeat" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    cat "$E2E_DIR/.server.log"
    die "server died before becoming ready"
  fi
  sleep 0.5
done
curl -fsS "$E2E_API_URL/api/heartbeat" >/dev/null 2>&1 \
  || { cat "$E2E_DIR/.server.log"; die "server never became ready"; }

# ---- Run cases -------------------------------------------------------

# shellcheck disable=SC1091
source "$E2E_DIR/lib.sh"

shopt -s nullglob
matched_files=()
for f in "$CASES_DIR"/${ONLY_FILES}*.sh; do
  matched_files+=("$f")
done
if [[ ${#matched_files[@]} -eq 0 ]]; then
  die "no case files matched glob '$ONLY_FILES*'"
fi

for f in "${matched_files[@]}"; do
  printf "\n\033[1m═══ %s ═══\033[0m\n" "$(basename "$f" .sh)"
  # shellcheck disable=SC1090
  source "$f"
  # Find every function named test_*
  while IFS= read -r fn; do
    if [[ -n "$ONLY_TESTS" && "$fn" != *"$ONLY_TESTS"* ]]; then
      continue
    fi
    begin_case "$fn"
    # Reset per-test persona to alice. Tests that want another user
    # set AVELINE_E2E_PERSONA=bob (or carol) before calling run_cli /
    # mk_*.
    AVELINE_E2E_PERSONA="alice"
    "$fn"
  done < <(declare -F | awk '$3 ~ /^test_/ {print $3}')
  # Unset so the next file's `declare -F` doesn't re-see them.
  while IFS= read -r fn; do
    unset -f "$fn"
  done < <(declare -F | awk '$3 ~ /^test_/ {print $3}')
done

# ---- Summary ---------------------------------------------------------

printf "\n\033[1m──────────────────────────────\033[0m\n"
printf "  %sPass:%s %d\n" "$C_GREEN" "$C_RESET" "$E2E_PASS"
printf "  %sFail:%s %d\n" "$C_RED" "$C_RESET" "$E2E_FAIL"
if [[ "$E2E_FAIL" -gt 0 ]]; then
  printf "\n\033[31mFailures:\033[0m\n"
  for line in "${E2E_FAILURES[@]}"; do
    printf "  • %s\n" "$line"
  done
  printf "\nServer log: %s\n" "$E2E_DIR/.server.log"
  exit 1
fi

printf "\n\033[32mAll green.\033[0m\n"
