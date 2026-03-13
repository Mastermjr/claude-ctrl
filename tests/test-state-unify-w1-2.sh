#!/usr/bin/env bash
# test-state-unify-w1-2.sh — Tests for proof_state typed table + API (W1-2).
#
# Validates:
#   - proof_state table creation via _state_ensure_schema()
#   - proof_state_get() pipe-delimited output
#   - proof_state_set() with monotonic lattice enforcement
#   - proof_epoch_reset() allows regression after epoch bump
#   - history audit trail for proof_state_set()
#   - CHECK constraint rejection of invalid status values
#   - Dual-read fallback to flat file when SQLite empty
#   - Concurrent proof_state_set() with forward-only progression
#
# Usage: bash tests/test-state-unify-w1-2.sh
#
# Test environment: each test gets its own isolated CLAUDE_DIR to prevent
# cross-test contamination. The _setup() helper creates a git repo to satisfy
# detect_project_root(). All grep/sqlite3 calls use || true to prevent
# set -euo pipefail from aborting the script on non-match exits.
#
# @decision DEC-STATE-UNIFY-W1-2-TEST-001
# @title Isolated temp DB per test, matching test-sqlite-state.sh pattern
# @status accepted
# @rationale Hermetic tests prevent state leakage between test cases. Per-test
#   CLAUDE_DIR is the same pattern used by test-sqlite-state.sh — callers
#   of _run_state() reset _STATE_SCHEMA_INITIALIZED and _WORKFLOW_ID so each
#   test starts from a clean slate without needing separate DB files.
#   All verification commands use || true so grep non-matches don't abort
#   the script under set -euo pipefail.

set -euo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT_OUTER="$(cd "$TEST_DIR/.." && pwd)"
HOOKS_DIR="$PROJECT_ROOT_OUTER/hooks"

# Resolve the main repo root. When running from a worktree, git's commondir
# points to the main .git — use that to find the main repo tmp/ dir so that
# CLAUDE_DIR and PROJECT_ROOT paths never contain ".worktrees/" (which the
# pre-bash hook blocks).
_MAIN_GIT_COMMON=$(git -C "$PROJECT_ROOT_OUTER" rev-parse --git-common-dir 2>/dev/null || echo "")
if [[ -n "$_MAIN_GIT_COMMON" && "$_MAIN_GIT_COMMON" != ".git" ]]; then
    _MAIN_REPO_ROOT="${_MAIN_GIT_COMMON%/.git}"
else
    _MAIN_REPO_ROOT="$PROJECT_ROOT_OUTER"
fi
# Fallback: strip .worktrees suffix if still present
if [[ "$_MAIN_REPO_ROOT" == *"/.worktrees"* ]]; then
    _MAIN_REPO_ROOT="${_MAIN_REPO_ROOT%%/.worktrees*}"
fi

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local test_name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Running: $test_name"
}

pass_test() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS"
}

fail_test() {
    local reason="$1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: $reason"
}

# Global tmp dir — use main repo tmp/ to avoid .worktrees/ path restriction.
# Cleaned on EXIT.
TMPDIR_BASE="${_MAIN_REPO_ROOT}/tmp/test-state-unify-w1-2-$$"
mkdir -p "$TMPDIR_BASE"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# _run_state — execute proof_state operations in an isolated bash subshell.
# Usage: _run_state CLAUDE_DIR PROJECT_ROOT_PATH "bash code using state functions"
_run_state() {
    local _rcd="$1"
    local _rpr="$2"
    local _rcode="$3"
    bash -c "
source '${HOOKS_DIR}/source-lib.sh' 2>/dev/null
require_state
_STATE_SCHEMA_INITIALIZED=''
_WORKFLOW_ID=''
export CLAUDE_DIR='${_rcd}'
export PROJECT_ROOT='${_rpr}'
export CLAUDE_SESSION_ID='test-session-\$\$'
${_rcode}
" 2>/dev/null
}

# _setup — create isolated env for a test.
# Outputs: sets _CD (CLAUDE_DIR) and _PR (PROJECT_ROOT) for the test.
_setup() {
    local test_id="$1"
    _CD="${TMPDIR_BASE}/${test_id}/claude"
    _PR="${TMPDIR_BASE}/${test_id}/project"
    mkdir -p "${_CD}/state" "${_PR}"
    git -C "${_PR}" init -q 2>/dev/null || true
}

# _sqlite — run sqlite3 against a DB, suppressing errors, never failing.
# Usage: _sqlite DB SQL
_sqlite() {
    sqlite3 "$1" "$2" 2>/dev/null || true
}

# ─────────────────────────────────────────────────────────────────────────────
# T01: proof_state table created on first state operation
# ─────────────────────────────────────────────────────────────────────────────
run_test "T01: proof_state table created on first state operation"
_setup t01

_run_state "$_CD" "$_PR" "state_update 'bootstrap' 'yes' 'test'" || true

_T01_DB="${_CD}/state/state.db"
_T01_FAIL=""

if [[ ! -f "$_T01_DB" ]]; then
    _T01_FAIL="state.db was not created"
else
    _T01_TABLES=$(_sqlite "$_T01_DB" ".tables" | tr ' ' '\n' | grep -c '^proof_state$' || true)
    if [[ "${_T01_TABLES:-0}" -ne 1 ]]; then
        _T01_FAIL="proof_state table not found (got: $(_sqlite "$_T01_DB" ".tables"))"
    fi
fi

[[ -z "$_T01_FAIL" ]] && pass_test || fail_test "$_T01_FAIL"

# ─────────────────────────────────────────────────────────────────────────────
# T02: proof_state_set writes correct status
# ─────────────────────────────────────────────────────────────────────────────
run_test "T02: proof_state_set writes correct status"
_setup t02

_T02_DB="${_CD}/state/state.db"

_run_state "$_CD" "$_PR" "proof_state_set 'pending' 'test'" >/dev/null || true

_T02_STATUS=$(_sqlite "$_T02_DB" "SELECT status FROM proof_state LIMIT 1;")

if [[ "$_T02_STATUS" == "pending" ]]; then
    pass_test
else
    fail_test "Expected 'pending' in proof_state, got '${_T02_STATUS}'"
fi

# ─────────────────────────────────────────────────────────────────────────────
# T03: proof_state_get returns pipe-delimited format
# ─────────────────────────────────────────────────────────────────────────────
run_test "T03: proof_state_get returns pipe-delimited format: status|epoch|updated_at|updated_by"
_setup t03

_T03_RESULT=$(_run_state "$_CD" "$_PR" "
proof_state_set 'pending' 'test-source'
proof_state_get
") || true

# Expect 4 pipe-delimited fields
_T03_FIELDS=$(echo "$_T03_RESULT" | awk -F'|' '{print NF}' || true)
_T03_STATUS=$(echo "$_T03_RESULT" | cut -d'|' -f1 || true)
_T03_EPOCH=$(echo "$_T03_RESULT" | cut -d'|' -f2 || true)

if [[ "${_T03_FIELDS:-0}" -eq 4 ]] && [[ "$_T03_STATUS" == "pending" ]] && [[ "${_T03_EPOCH:-x}" == "0" ]]; then
    pass_test
else
    fail_test "Expected 4 fields with status=pending,epoch=0; got '${_T03_RESULT}' (fields=${_T03_FIELDS:-?})"
fi

# ─────────────────────────────────────────────────────────────────────────────
# T04: Lattice enforcement — verified→pending rejected
# ─────────────────────────────────────────────────────────────────────────────
run_test "T04: Lattice enforcement — verified→pending rejected (regression without epoch bump)"
_setup t04

_T04_RESULT=$(_run_state "$_CD" "$_PR" "
proof_state_set 'verified' 'test'
# Try to regress to pending — should fail (return 1)
if proof_state_set 'pending' 'test'; then
    echo 'allowed'
else
    echo 'rejected'
fi
# Verify the state remained at verified
proof_state_get | cut -d'|' -f1
") || true

_T04_VERDICT=$(echo "$_T04_RESULT" | head -1 || true)
_T04_STATUS=$(echo "$_T04_RESULT" | tail -1 || true)

if [[ "$_T04_VERDICT" == "rejected" ]] && [[ "$_T04_STATUS" == "verified" ]]; then
    pass_test
else
    fail_test "Expected regression rejected + status=verified; got verdict='${_T04_VERDICT}' status='${_T04_STATUS}'"
fi

# ─────────────────────────────────────────────────────────────────────────────
# T05: Lattice enforcement — none→verified allowed (forward progression)
# ─────────────────────────────────────────────────────────────────────────────
run_test "T05: Lattice enforcement — none→verified allowed (forward progression skipping steps)"
_setup t05

_T05_RESULT=$(_run_state "$_CD" "$_PR" "
# none→verified should succeed (forward progression)
if proof_state_set 'verified' 'test'; then
    echo 'allowed'
else
    echo 'rejected'
fi
proof_state_get | cut -d'|' -f1
") || true

_T05_VERDICT=$(echo "$_T05_RESULT" | head -1 || true)
_T05_STATUS=$(echo "$_T05_RESULT" | tail -1 || true)

if [[ "$_T05_VERDICT" == "allowed" ]] && [[ "$_T05_STATUS" == "verified" ]]; then
    pass_test
else
    fail_test "Expected progression allowed + status=verified; got verdict='${_T05_VERDICT}' status='${_T05_STATUS}'"
fi

# ─────────────────────────────────────────────────────────────────────────────
# T06: proof_epoch_reset allows regression after epoch bump
# ─────────────────────────────────────────────────────────────────────────────
run_test "T06: proof_epoch_reset allows regression after epoch bump"
_setup t06

_T06_RESULT=$(_run_state "$_CD" "$_PR" "
# Advance to verified
proof_state_set 'verified' 'test'
# Without epoch reset: regression should fail
if proof_state_set 'none' 'test'; then
    echo 'r1:allowed'
else
    echo 'r1:rejected'
fi
# Bump epoch
proof_epoch_reset
# Now regression should succeed
if proof_state_set 'none' 'test'; then
    echo 'r2:allowed'
else
    echo 'r2:rejected'
fi
proof_state_get | cut -d'|' -f1-2
") || true

_T06_R1=$(echo "$_T06_RESULT" | grep '^r1:' | head -1 || true)
_T06_R2=$(echo "$_T06_RESULT" | grep '^r2:' | head -1 || true)
_T06_FINAL=$(echo "$_T06_RESULT" | tail -1 || true)

# After epoch reset + regression, status should be 'none' and epoch should be 1
_T06_STATUS=$(echo "$_T06_FINAL" | cut -d'|' -f1 || true)
_T06_EPOCH=$(echo "$_T06_FINAL" | cut -d'|' -f2 || true)

if [[ "$_T06_R1" == "r1:rejected" ]] && [[ "$_T06_R2" == "r2:allowed" ]] && \
   [[ "$_T06_STATUS" == "none" ]] && [[ "${_T06_EPOCH:-0}" -eq 1 ]]; then
    pass_test
else
    fail_test "Expected r1:rejected r2:allowed status=none epoch=1; got r1='${_T06_R1}' r2='${_T06_R2}' final='${_T06_FINAL}'"
fi

# ─────────────────────────────────────────────────────────────────────────────
# T07: proof_state_set records history entry
# ─────────────────────────────────────────────────────────────────────────────
run_test "T07: proof_state_set records history entry for audit trail"
_setup t07

_T07_DB="${_CD}/state/state.db"

_run_state "$_CD" "$_PR" "
proof_state_set 'needs-verification' 'test-hook'
proof_state_set 'pending' 'test-hook'
proof_state_set 'verified' 'test-hook'
" >/dev/null || true

_T07_HIST=$(_sqlite "$_T07_DB" "SELECT COUNT(*) FROM history WHERE key='proof_state';")

if [[ "${_T07_HIST:-0}" -ge 3 ]]; then
    pass_test
else
    fail_test "Expected ≥3 history entries for proof_state, got ${_T07_HIST:-0}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# T08: CHECK constraint rejects invalid status values
# ─────────────────────────────────────────────────────────────────────────────
run_test "T08: CHECK constraint rejects invalid status values directly via sqlite3"
_setup t08

# Bootstrap schema
_run_state "$_CD" "$_PR" "state_update 'bootstrap' 'yes' 'test'" >/dev/null || true

_T08_DB="${_CD}/state/state.db"

# Attempt to insert invalid status directly — should fail with constraint error
_T08_RESULT=$(sqlite3 "$_T08_DB" "
INSERT INTO proof_state (workflow_id, status, epoch, updated_at, updated_by)
VALUES ('test_wf', 'invalid-status', 0, strftime('%s','now'), 'test');
" 2>&1 || true)

_T08_MATCH=$(echo "$_T08_RESULT" | grep -ci "constraint\|CHECK" || true)

if [[ "${_T08_MATCH:-0}" -gt 0 ]]; then
    pass_test
else
    fail_test "Expected CHECK constraint violation for 'invalid-status', got: '${_T08_RESULT}'"
fi

# ─────────────────────────────────────────────────────────────────────────────
# T09: Dual-read fallback — reads flat file when SQLite empty
# ─────────────────────────────────────────────────────────────────────────────
run_test "T09: Dual-read fallback — proof_state_get reads flat file when SQLite empty"
_setup t09

# Bootstrap schema (creates DB but no proof_state rows)
_run_state "$_CD" "$_PR" "state_update 'bootstrap' 'yes' 'test'" >/dev/null || true

# Compute project hash the same way state-lib.sh does
# (shasum on macOS, sha256sum on Linux)
if command -v shasum >/dev/null 2>&1; then
    _T09_PHASH=$(echo "$_PR" | shasum -a 256 | cut -c1-8)
elif command -v sha256sum >/dev/null 2>&1; then
    _T09_PHASH=$(echo "$_PR" | sha256sum | cut -c1-8)
else
    _T09_PHASH="00000000"
fi

mkdir -p "${_CD}/state/${_T09_PHASH}"
_T09_TS=$(date +%s)
printf 'pending|%s' "$_T09_TS" > "${_CD}/state/${_T09_PHASH}/proof-status"

_T09_RESULT=$(_run_state "$_CD" "$_PR" "proof_state_get") || true

# Should return something pipe-delimited with 'pending' as first field
_T09_STATUS=$(echo "$_T09_RESULT" | cut -d'|' -f1 || true)
_T09_SOURCE=$(echo "$_T09_RESULT" | cut -d'|' -f4 || true)

if [[ "$_T09_STATUS" == "pending" ]] && [[ "$_T09_SOURCE" == "flat-file-fallback" ]]; then
    pass_test
else
    fail_test "Expected pending|...|...|flat-file-fallback; got '${_T09_RESULT}'"
fi

# ─────────────────────────────────────────────────────────────────────────────
# T10: Concurrent proof_state_set (5 parallel, all advance forward)
# ─────────────────────────────────────────────────────────────────────────────
run_test "T10: Concurrent proof_state_set — 5 parallel forward-only sets, DB remains consistent"
_setup t10

_T10_DB="${_CD}/state/state.db"
_T10_RESULTS="${TMPDIR_BASE}/t10-results"
mkdir -p "$_T10_RESULTS"

# Bootstrap schema
_run_state "$_CD" "$_PR" "state_update 'bootstrap' 'yes' 'test'" >/dev/null || true

# Launch 5 parallel writers all setting 'pending' (forward-only from none)
_T10_PIDS=()
for _i in $(seq 1 5); do
    bash -c "
source '${HOOKS_DIR}/source-lib.sh' 2>/dev/null
require_state
_STATE_SCHEMA_INITIALIZED=''
_WORKFLOW_ID=''
export CLAUDE_DIR='${_CD}'
export PROJECT_ROOT='${_PR}'
export CLAUDE_SESSION_ID='test-session-t10-${_i}'
if proof_state_set 'pending' 'concurrent-test-${_i}'; then
    printf 'ok' > '${_T10_RESULTS}/result-${_i}.txt'
else
    printf 'fail' > '${_T10_RESULTS}/result-${_i}.txt'
fi
" 2>/dev/null &
    _T10_PIDS+=($!)
done

for _pid in "${_T10_PIDS[@]}"; do
    wait "$_pid" 2>/dev/null || true
done

# DB should be consistent: status should be 'pending', ≥1 history entry
_T10_FINAL=$(_sqlite "$_T10_DB" "SELECT status FROM proof_state LIMIT 1;")
_T10_HIST=$(_sqlite "$_T10_DB" "SELECT COUNT(*) FROM history WHERE key='proof_state';")

if [[ "$_T10_FINAL" == "pending" ]] && [[ "${_T10_HIST:-0}" -ge 1 ]]; then
    pass_test
else
    fail_test "Expected status=pending and ≥1 history entries; got status='${_T10_FINAL}' history=${_T10_HIST:-0}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "Results: ${TESTS_PASSED}/${TESTS_RUN} passed, ${TESTS_FAILED} failed"

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
exit 0
