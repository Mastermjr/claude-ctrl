#!/usr/bin/env bash
# test-state-unify-w1-1.sh — Tests for State Unification Wave 1-1.
#
# Validates: BEGIN IMMEDIATE upgrade, _migrations table schema, migration runner
# idempotency, concurrent write correctness under RESERVED lock, and migration
# checksum recording.
#
# Usage: bash tests/test-state-unify-w1-1.sh
#
# Design mirrors test-sqlite-state.sh: isolated CLAUDE_DIR per test, _run_state
# helper for subshell sourcing, pass_test/fail_test counters at top level.
#
# @decision DEC-STATE-UNIFY-TEST-001
# @title Isolated temp DB per test for W1-1 migration framework tests
# @status accepted
# @rationale Migration tests must be hermetic: each test needs a fresh DB to
#   confirm that migration 001 is applied on first schema init, not carried
#   over from a prior test's DB. Concurrent write tests (T06) use a shared DB
#   because they exercise multi-writer behavior. Same pattern as DEC-SQLITE-TEST-001.

set -euo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT_OUTER="$(cd "$TEST_DIR/.." && pwd)"
HOOKS_DIR="$PROJECT_ROOT_OUTER/hooks"

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

# Global tmp dir — cleaned on EXIT
TMPDIR_BASE="$PROJECT_ROOT_OUTER/tmp/test-state-unify-w1-1-$$"
mkdir -p "$TMPDIR_BASE"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# _run_state — execute state-lib operations in an isolated bash subshell.
# Usage: _run_state CLAUDE_DIR PROJECT_ROOT_PATH "bash code using state functions"
# The subshell sources hooks, resets module guards, exports env, and runs the code.
_run_state() {
    local cd="$1"
    local pr="$2"
    local code="$3"
    bash -c "
source '${HOOKS_DIR}/source-lib.sh' 2>/dev/null
require_state
_STATE_SCHEMA_INITIALIZED=''
_WORKFLOW_ID=''
export CLAUDE_DIR='${cd}'
export PROJECT_ROOT='${pr}'
export CLAUDE_SESSION_ID='test-session-\$\$'
${code}
" 2>/dev/null
}

# _setup — create an isolated env for a test and set up a git repo.
# Outputs: sets _CD (CLAUDE_DIR) and _PR (PROJECT_ROOT) for the test.
_setup() {
    local test_id="$1"
    _CD="${TMPDIR_BASE}/${test_id}/claude"
    _PR="${TMPDIR_BASE}/${test_id}/project"
    mkdir -p "${_CD}/state" "${_PR}"
    git -C "${_PR}" init -q 2>/dev/null || true
}

# ─────────────────────────────────────────────────────────────────────────────
# T01: BEGIN IMMEDIATE present in state_update SQL
# ─────────────────────────────────────────────────────────────────────────────
run_test "T01: BEGIN IMMEDIATE present in state_update() function body"

# Extract the state_update function body from state-lib.sh and check for BEGIN IMMEDIATE
_T01_FOUND=""
if grep -A 30 "^state_update\(\)" "${HOOKS_DIR}/state-lib.sh" 2>/dev/null | grep -q "BEGIN IMMEDIATE"; then
    _T01_FOUND="yes"
fi

if [[ "$_T01_FOUND" == "yes" ]]; then
    pass_test
else
    fail_test "BEGIN IMMEDIATE not found in state_update() body in ${HOOKS_DIR}/state-lib.sh"
fi

# ─────────────────────────────────────────────────────────────────────────────
# T02: BEGIN IMMEDIATE present in state_cas SQL
# ─────────────────────────────────────────────────────────────────────────────
run_test "T02: BEGIN IMMEDIATE present in state_cas() function body"

# state_cas() is a longer function — use a 60-line window to capture the SQL block
_T02_FOUND=""
if grep -A 60 "^state_cas\(\)" "${HOOKS_DIR}/state-lib.sh" 2>/dev/null | grep -q "BEGIN IMMEDIATE"; then
    _T02_FOUND="yes"
fi

if [[ "$_T02_FOUND" == "yes" ]]; then
    pass_test
else
    fail_test "BEGIN IMMEDIATE not found in state_cas() body in ${HOOKS_DIR}/state-lib.sh"
fi

# ─────────────────────────────────────────────────────────────────────────────
# T03: _migrations table created on first state operation
# ─────────────────────────────────────────────────────────────────────────────
run_test "T03: _migrations table created on first state operation"
_setup t03

_run_state "$_CD" "$_PR" "state_update 'bootstrap' 'yes' 'test'" >/dev/null

_T03_DB="${_CD}/state/state.db"
_T03_FAIL=""

if [[ ! -f "$_T03_DB" ]]; then
    _T03_FAIL="state.db was not created at ${_T03_DB}"
else
    _T03_TABLES=$(sqlite3 "$_T03_DB" ".tables" 2>/dev/null | tr ' ' '\n' | grep -E '^_migrations$' | head -1)
    if [[ "$_T03_TABLES" != "_migrations" ]]; then
        _T03_FAIL="_migrations table not found in DB (tables: $(sqlite3 "$_T03_DB" ".tables" 2>/dev/null))"
    fi
fi

[[ -z "$_T03_FAIL" ]] && pass_test || fail_test "$_T03_FAIL"

# ─────────────────────────────────────────────────────────────────────────────
# T04: Migration 001 recorded after schema init
# ─────────────────────────────────────────────────────────────────────────────
run_test "T04: Migration 001 recorded in _migrations after schema init"
_setup t04

_run_state "$_CD" "$_PR" "state_update 'bootstrap' 'yes' 'test'" >/dev/null

_T04_DB="${_CD}/state/state.db"
_T04_FAIL=""

if [[ ! -f "$_T04_DB" ]]; then
    _T04_FAIL="state.db not created"
else
    _T04_COUNT=$(sqlite3 "$_T04_DB" "
SELECT COUNT(*) FROM _migrations WHERE version=1;
" 2>/dev/null || echo "0")
    if [[ "$_T04_COUNT" -ne 1 ]]; then
        _T04_FAIL="Migration 001 not recorded: expected 1 row with version=1, got ${_T04_COUNT}"
    fi

    # Also verify the name is correct
    _T04_NAME=$(sqlite3 "$_T04_DB" "
SELECT name FROM _migrations WHERE version=1;
" 2>/dev/null || echo "")
    if [[ -z "$_T04_NAME" ]]; then
        _T04_FAIL="Migration 001 recorded but name is empty"
    fi
fi

[[ -z "$_T04_FAIL" ]] && pass_test || fail_test "$_T04_FAIL"

# ─────────────────────────────────────────────────────────────────────────────
# T05: Migration runner idempotent — run twice, same result
# ─────────────────────────────────────────────────────────────────────────────
run_test "T05: Migration runner idempotent — running state_migrate twice produces same result"
_setup t05

# First run: schema init + migrations
_run_state "$_CD" "$_PR" "state_update 'bootstrap' 'yes' 'test'" >/dev/null

_T05_DB="${_CD}/state/state.db"
_T05_FAIL=""

_T05_COUNT_BEFORE=$(sqlite3 "$_T05_DB" "SELECT COUNT(*) FROM _migrations;" 2>/dev/null || echo "0")

# Second run: re-source, reset guard, run migrations again via state_migrate
_run_state "$_CD" "$_PR" "state_migrate" >/dev/null 2>/dev/null || true

_T05_COUNT_AFTER=$(sqlite3 "$_T05_DB" "SELECT COUNT(*) FROM _migrations;" 2>/dev/null || echo "0")

if [[ "$_T05_COUNT_BEFORE" -eq "$_T05_COUNT_AFTER" ]] && [[ "$_T05_COUNT_BEFORE" -gt 0 ]]; then
    pass_test
else
    fail_test "Idempotency failed: before=${_T05_COUNT_BEFORE}, after=${_T05_COUNT_AFTER} (expected equal and >0)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# T06: Concurrent writes — 10 parallel processes, 0 failures (BEGIN IMMEDIATE)
# ─────────────────────────────────────────────────────────────────────────────
run_test "T06: Concurrent writes — 10 parallel processes, 0 failures (validates BEGIN IMMEDIATE)"
_setup t06

_T06_DB="${_CD}/state/state.db"
_T06_RESULTS="${TMPDIR_BASE}/t06-results"
mkdir -p "$_T06_RESULTS"

# Bootstrap schema first
_run_state "$_CD" "$_PR" "state_update 'bootstrap' 'yes' 'test'" >/dev/null

# Launch 10 parallel writers — each writes a unique key and records exit status
_T06_PIDS=()
for _i in $(seq 1 10); do
    bash -c "
source '${HOOKS_DIR}/source-lib.sh' 2>/dev/null
require_state
_STATE_SCHEMA_INITIALIZED=''
_WORKFLOW_ID=''
export CLAUDE_DIR='${_CD}'
export PROJECT_ROOT='${_PR}'
export CLAUDE_SESSION_ID='test-concurrent-${_i}'
if state_update 'concurrent.w1-1.key.${_i}' 'value-${_i}' 'test'; then
    printf 'ok' > '${_T06_RESULTS}/result-${_i}.txt'
else
    printf 'fail' > '${_T06_RESULTS}/result-${_i}.txt'
fi
" 2>/dev/null &
    _T06_PIDS+=($!)
done

for _pid in "${_T06_PIDS[@]}"; do
    wait "$_pid" 2>/dev/null || true
done

_T06_OK=0
_T06_FAIL=0
for _i in $(seq 1 10); do
    _f="${_T06_RESULTS}/result-${_i}.txt"
    if [[ -f "$_f" ]]; then
        _content=$(cat "$_f" 2>/dev/null || echo "fail")
        if [[ "$_content" == "ok" ]]; then
            _T06_OK=$((_T06_OK + 1))
        else
            _T06_FAIL=$((_T06_FAIL + 1))
        fi
    else
        _T06_FAIL=$((_T06_FAIL + 1))
    fi
done

# Also verify all 10 rows are visible in the DB
_T06_DB_COUNT=$(sqlite3 "$_T06_DB" "
SELECT COUNT(*) FROM state WHERE key LIKE 'concurrent.w1-1.key.%';
" 2>/dev/null || echo "0")

if [[ "$_T06_OK" -eq 10 && "$_T06_FAIL" -eq 0 && "$_T06_DB_COUNT" -eq 10 ]]; then
    pass_test
else
    fail_test "Expected 10 ok, 0 fail, 10 DB rows — got ok=${_T06_OK}, fail=${_T06_FAIL}, db_count=${_T06_DB_COUNT}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# T07: Failed migration stops runner (doesn't skip to next)
# ─────────────────────────────────────────────────────────────────────────────
run_test "T07: Failed migration stops runner — doesn't continue past failed migration"
_setup t07

_T07_DB="${_CD}/state/state.db"

# Bootstrap the schema (runs migration 001)
_run_state "$_CD" "$_PR" "state_update 'bootstrap' 'yes' 'test'" >/dev/null

_T07_FAIL=""

# Verify 001 was applied
_T07_V1=$(sqlite3 "$_T07_DB" "SELECT COUNT(*) FROM _migrations WHERE version=1;" 2>/dev/null || echo "0")
if [[ "$_T07_V1" -ne 1 ]]; then
    _T07_FAIL="Migration 001 not applied before failure test (got ${_T07_V1})"
fi

if [[ -z "$_T07_FAIL" ]]; then
    # Test: inject a migration that fails and a migration that would come after it.
    # We simulate this by calling _state_run_migrations with a failing migration in the array.
    # Use a bash subshell that defines a custom _MIGRATIONS array with a failing entry.
    _T07_RESULT=$(bash -c "
source '${HOOKS_DIR}/source-lib.sh' 2>/dev/null
require_state
_STATE_SCHEMA_INITIALIZED=''
_WORKFLOW_ID=''
export CLAUDE_DIR='${_T07_DB%/state/state.db}'
export PROJECT_ROOT='${_PR}'
export CLAUDE_SESSION_ID='test-t07'

# Override _MIGRATIONS to include a failing migration at version 2
# and a should-not-run migration at version 3
_MIGRATIONS=(
    '1:initial_schema:_migration_001_initial_schema'
    '2:failing_migration:_migration_002_always_fails'
    '3:should_not_run:_migration_003_sentinel'
)

_migration_002_always_fails() {
    return 1
}

_migration_003_sentinel() {
    # This should never run — mark it if it does
    printf 'SENTINEL_RAN' > '${_T07_RESULTS:-${TMPDIR_BASE}/t07-sentinel.txt}'
    return 0
}

# Run migrations — should stop at 002 failure
state_migrate
EXIT_CODE=\$?
echo \$EXIT_CODE
" 2>/dev/null || echo "1")

    # Check the sentinel file was NOT created (migration 3 did not run)
    _T07_SENTINEL="${TMPDIR_BASE}/t07-sentinel.txt"
    if [[ -f "$_T07_SENTINEL" ]]; then
        _T07_FAIL="Migration runner continued past failed migration (sentinel file exists)"
    fi

    # Check migration 002 was NOT recorded in _migrations (failure = no record)
    _T07_V2=$(sqlite3 "$_T07_DB" "SELECT COUNT(*) FROM _migrations WHERE version=2;" 2>/dev/null || echo "0")
    if [[ "$_T07_V2" -ne 0 ]]; then
        _T07_FAIL="Failed migration 002 was incorrectly recorded in _migrations (count=${_T07_V2})"
    fi
fi

[[ -z "$_T07_FAIL" ]] && pass_test || fail_test "$_T07_FAIL"

# ─────────────────────────────────────────────────────────────────────────────
# T08: Migration checksum recorded and non-empty
# ─────────────────────────────────────────────────────────────────────────────
run_test "T08: Migration checksum recorded — _migrations.checksum is non-empty after init"
_setup t08

_run_state "$_CD" "$_PR" "state_update 'bootstrap' 'yes' 'test'" >/dev/null

_T08_DB="${_CD}/state/state.db"
_T08_FAIL=""

if [[ ! -f "$_T08_DB" ]]; then
    _T08_FAIL="state.db not created"
else
    _T08_CHECKSUM=$(sqlite3 "$_T08_DB" "
SELECT checksum FROM _migrations WHERE version=1;
" 2>/dev/null || echo "")
    if [[ -z "$_T08_CHECKSUM" ]]; then
        _T08_FAIL="checksum is NULL or empty for migration 001 (expected non-empty SHA-256)"
    fi
    # Verify it looks like a SHA-256 hash (64 hex chars)
    if [[ -n "$_T08_CHECKSUM" ]] && ! echo "$_T08_CHECKSUM" | grep -qE '^[0-9a-f]{64}'; then
        _T08_FAIL="checksum '${_T08_CHECKSUM}' does not look like a SHA-256 hash (64 hex chars)"
    fi
fi

[[ -z "$_T08_FAIL" ]] && pass_test || fail_test "$_T08_FAIL"

# ─────────────────────────────────────────────────────────────────────────────
# T09: _STATE_LIB_VERSION bumped to 3
# ─────────────────────────────────────────────────────────────────────────────
run_test "T09: _STATE_LIB_VERSION is 3 (bumped from 2 for W1-1)"

_T09_VERSION=$(grep -m1 "^_STATE_LIB_VERSION=" "${HOOKS_DIR}/state-lib.sh" 2>/dev/null | cut -d= -f2)

if [[ "$_T09_VERSION" == "3" ]]; then
    pass_test
else
    fail_test "_STATE_LIB_VERSION is '${_T09_VERSION}', expected '3'"
fi

# ─────────────────────────────────────────────────────────────────────────────
# T10: state_migrate is exported
# ─────────────────────────────────────────────────────────────────────────────
run_test "T10: state_migrate is exported (accessible from subshells)"
_setup t10

_T10_RESULT=$(_run_state "$_CD" "$_PR" "
# Try calling state_migrate — should succeed (no-op if migrations already run)
state_update 'bootstrap' 'yes' 'test' >/dev/null
state_migrate
echo 'ok'
")

if [[ "$_T10_RESULT" == "ok" ]]; then
    pass_test
else
    fail_test "state_migrate not callable from subshell (got '${_T10_RESULT}')"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "──────────────────────────────────────────────────────"
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_RUN total"

if [[ "$TESTS_FAILED" -eq 0 ]]; then
    echo "ALL TESTS PASSED"
    exit 0
else
    echo "SOME TESTS FAILED"
    exit 1
fi
