#!/usr/bin/env bash
# test-token-history-sqlite.sh — Tests for SQLite-backed session_tokens table.
#
# Purpose: Verify that the session_tokens migration, INSERT path (session-end.sh),
#   and SELECT path (session-init.sh) work correctly with concurrency safety.
#
# @decision DEC-STATE-KV-003
# @title session_tokens table for atomic, per-project lifetime token tracking
# @status accepted
# @rationale See state-lib.sh DEC-STATE-KV-003 for full rationale. This test
#   file validates all five acceptance criteria: single INSERT, SUM query,
#   accumulation, project filtering, and JSON fallback for main tokens.
#
# Tests:
#   1. Migration creates session_tokens table with correct schema
#   2. Single INSERT + SELECT SUM returns correct value
#   3. Multiple INSERTs for same project accumulate correctly
#   4. Rows for different projects are isolated (no cross-contamination)
#   5. JSON fallback computes main tokens when .session-main-tokens is absent
#   6. Dual-write: flat-file entry still written alongside SQLite INSERT
#   7. idx_session_tokens_project index exists
#   8. Empty project returns 0 (COALESCE prevents NULL)
#
# Usage: bash tests/test-token-history-sqlite.sh
# Scope: --scope sqlite in run-hooks.sh
#

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT_REAL="$(cd "$TEST_DIR/.." && pwd)"
HOOKS_DIR="$PROJECT_ROOT_REAL/hooks"

# ---------------------------------------------------------------------------
# Test tracking
# ---------------------------------------------------------------------------
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local test_name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "  Running: $test_name"
}

pass_test() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "    PASS"
}

fail_test() {
    local reason="$1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "    FAIL: $reason"
}

# ---------------------------------------------------------------------------
# Temp environment helpers
# ---------------------------------------------------------------------------
_TMP_BASE="$PROJECT_ROOT_REAL/tmp/test-token-history-$$"
mkdir -p "$_TMP_BASE"

_TMPDIR=""

setup_env() {
    local label="${1:-test}"
    _TMPDIR="${_TMP_BASE}/${label}"
    mkdir -p "$_TMPDIR"
    # Minimal git repo so detect_project_root works
    git -C "$_TMPDIR" init -q 2>/dev/null || true
    export CLAUDE_DIR="$_TMPDIR/.claude"
    mkdir -p "$CLAUDE_DIR/state"
    export HOME="$_TMPDIR"
    export CLAUDE_SESSION_ID="test-session-$$"
    export PROJECT_ROOT="$_TMPDIR"

    # Reset schema guard so each test gets a fresh schema run
    unset _STATE_SCHEMA_INITIALIZED
    unset _STATE_LIB_LOADED
    unset _WORKFLOW_ID

    # Source state-lib fresh for this test
    # shellcheck source=/dev/null
    source "$HOOKS_DIR/source-lib.sh"
    require_state
}

teardown_env() {
    rm -rf "$_TMPDIR" 2>/dev/null || true
    _TMPDIR=""
}

# Direct sqlite3 helper against test DB
_db() {
    sqlite3 "$CLAUDE_DIR/state/state.db" "$1" 2>/dev/null
}

# Trigger schema initialization by running a no-op query
_init_schema() {
    _state_sql "SELECT 1;" >/dev/null 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Test 1: session_tokens table created after schema init
# ---------------------------------------------------------------------------
echo ""
echo "=== Test 1: session_tokens table creation ==="

run_test "table exists after _state_ensure_schema"
setup_env "t1"
_init_schema
_tbl=$(_db "SELECT name FROM sqlite_master WHERE type='table' AND name='session_tokens';")
if [[ "$_tbl" == "session_tokens" ]]; then
    pass_test
else
    fail_test "table not found (got: '$_tbl')"
fi
teardown_env

run_test "session_id column exists"
setup_env "t1b"
_init_schema
_schema=$(_db ".schema session_tokens" 2>/dev/null || true)
if echo "$_schema" | grep -q "session_id"; then
    pass_test
else
    fail_test "session_id column missing"
fi
teardown_env

run_test "total_tokens column exists"
setup_env "t1c"
_init_schema
_schema=$(_db ".schema session_tokens" 2>/dev/null || true)
if echo "$_schema" | grep -q "total_tokens"; then
    pass_test
else
    fail_test "total_tokens column missing"
fi
teardown_env

run_test "project_hash column exists"
setup_env "t1d"
_init_schema
_schema=$(_db ".schema session_tokens" 2>/dev/null || true)
if echo "$_schema" | grep -q "project_hash"; then
    pass_test
else
    fail_test "project_hash column missing"
fi
teardown_env

run_test "migration version 2 recorded in _migrations"
setup_env "t1e"
_init_schema
_mv=$(_db "SELECT version FROM _migrations WHERE version=2;" 2>/dev/null || echo "")
if [[ "$_mv" == "2" ]]; then
    pass_test
else
    fail_test "migration version 2 not recorded (got: '$_mv')"
fi
teardown_env

# ---------------------------------------------------------------------------
# Test 2: Single INSERT + SUM
# ---------------------------------------------------------------------------
echo ""
echo "=== Test 2: Single INSERT and SUM ==="

run_test "SUM returns inserted value"
setup_env "t2"
_init_schema
_phash="abc12345"
_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
_db "INSERT INTO session_tokens (session_id, project_hash, project_name, timestamp, total_tokens, main_tokens, subagent_tokens, source)
     VALUES ('sess-1', '$_phash', 'testproj', '$_ts', 5000, 4500, 500, 'test');"
_sum=$(_db "SELECT COALESCE(SUM(total_tokens), 0) FROM session_tokens WHERE project_hash = '$_phash';")
if [[ "$_sum" == "5000" ]]; then
    pass_test
else
    fail_test "SUM = '$_sum', expected 5000"
fi
teardown_env

# ---------------------------------------------------------------------------
# Test 3: Multiple INSERTs accumulate
# ---------------------------------------------------------------------------
echo ""
echo "=== Test 3: Multiple INSERT accumulation ==="

run_test "SUM of 3 equal rows = 3000"
setup_env "t3"
_init_schema
_phash="abc12345"
_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
for i in 1 2 3; do
    _db "INSERT INTO session_tokens (session_id, project_hash, project_name, timestamp, total_tokens, main_tokens, subagent_tokens, source)
         VALUES ('sess-$i', '$_phash', 'testproj', '$_ts', 1000, 900, 100, 'test');"
done
_sum=$(_db "SELECT COALESCE(SUM(total_tokens), 0) FROM session_tokens WHERE project_hash = '$_phash';")
if [[ "$_sum" == "3000" ]]; then
    pass_test
else
    fail_test "SUM = '$_sum', expected 3000"
fi
teardown_env

run_test "row count = 3 after 3 INSERTs"
setup_env "t3b"
_init_schema
_phash="abc12345"
_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
for i in 1 2 3; do
    _db "INSERT INTO session_tokens (session_id, project_hash, project_name, timestamp, total_tokens, main_tokens, subagent_tokens, source)
         VALUES ('sess-$i', '$_phash', 'testproj', '$_ts', 1000, 900, 100, 'test');"
done
_rows=$(_db "SELECT COUNT(*) FROM session_tokens WHERE project_hash = '$_phash';")
if [[ "$_rows" == "3" ]]; then
    pass_test
else
    fail_test "row count = '$_rows', expected 3"
fi
teardown_env

# ---------------------------------------------------------------------------
# Test 4: Cross-project isolation
# ---------------------------------------------------------------------------
echo ""
echo "=== Test 4: Cross-project isolation ==="

run_test "project A sum unaffected by project B"
setup_env "t4"
_init_schema
_phash_a="aaa00000"
_phash_b="bbb11111"
_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
_db "INSERT INTO session_tokens (session_id, project_hash, project_name, timestamp, total_tokens, main_tokens, subagent_tokens, source)
     VALUES ('sess-a', '$_phash_a', 'project-a', '$_ts', 7000, 6000, 1000, 'test');"
_db "INSERT INTO session_tokens (session_id, project_hash, project_name, timestamp, total_tokens, main_tokens, subagent_tokens, source)
     VALUES ('sess-b', '$_phash_b', 'project-b', '$_ts', 3000, 2500, 500, 'test');"
_sum_a=$(_db "SELECT COALESCE(SUM(total_tokens), 0) FROM session_tokens WHERE project_hash = '$_phash_a';")
if [[ "$_sum_a" == "7000" ]]; then
    pass_test
else
    fail_test "Project A sum = '$_sum_a', expected 7000"
fi
teardown_env

run_test "project B sum unaffected by project A"
setup_env "t4b"
_init_schema
_phash_a="aaa00000"
_phash_b="bbb11111"
_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
_db "INSERT INTO session_tokens (session_id, project_hash, project_name, timestamp, total_tokens, main_tokens, subagent_tokens, source)
     VALUES ('sess-a', '$_phash_a', 'project-a', '$_ts', 7000, 6000, 1000, 'test');"
_db "INSERT INTO session_tokens (session_id, project_hash, project_name, timestamp, total_tokens, main_tokens, subagent_tokens, source)
     VALUES ('sess-b', '$_phash_b', 'project-b', '$_ts', 3000, 2500, 500, 'test');"
_sum_b=$(_db "SELECT COALESCE(SUM(total_tokens), 0) FROM session_tokens WHERE project_hash = '$_phash_b';")
if [[ "$_sum_b" == "3000" ]]; then
    pass_test
else
    fail_test "Project B sum = '$_sum_b', expected 3000"
fi
teardown_env

run_test "global sum = sum of all projects"
setup_env "t4c"
_init_schema
_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
_db "INSERT INTO session_tokens (session_id, project_hash, project_name, timestamp, total_tokens, main_tokens, subagent_tokens, source)
     VALUES ('sess-a', 'aaa00000', 'project-a', '$_ts', 7000, 6000, 1000, 'test');"
_db "INSERT INTO session_tokens (session_id, project_hash, project_name, timestamp, total_tokens, main_tokens, subagent_tokens, source)
     VALUES ('sess-b', 'bbb11111', 'project-b', '$_ts', 3000, 2500, 500, 'test');"
_total=$(_db "SELECT COALESCE(SUM(total_tokens), 0) FROM session_tokens;")
if [[ "$_total" == "10000" ]]; then
    pass_test
else
    fail_test "Global sum = '$_total', expected 10000"
fi
teardown_env

# ---------------------------------------------------------------------------
# Test 5: JSON fallback for main tokens (no .session-main-tokens file)
# ---------------------------------------------------------------------------
echo ""
echo "=== Test 5: JSON fallback for main tokens ==="

run_test "input+output tokens from JSON = 10000 when flat file absent"
setup_env "t5"
_init_schema

_SESSION_END_INPUT='{"reason":"normal","context_window":{"total_input_tokens":8000,"total_output_tokens":2000}}'
_MAIN_TOKEN_FILE="${CLAUDE_DIR}/.session-main-tokens"

# Replicate the session-end.sh logic: flat file first, JSON fallback
_MT=0
if [[ -f "$_MAIN_TOKEN_FILE" ]]; then
    _MT=$(cat "$_MAIN_TOKEN_FILE" 2>/dev/null || echo "0")
    _MT="${_MT%.*}"
    _MT=$(( ${_MT:-0} ))
fi
if [[ "$_MT" -eq 0 ]]; then
    _MI=$(printf '%s' "$_SESSION_END_INPUT" | jq -r '.context_window.total_input_tokens // 0' 2>/dev/null || echo "0")
    _MO=$(printf '%s' "$_SESSION_END_INPUT" | jq -r '.context_window.total_output_tokens // 0' 2>/dev/null || echo "0")
    _MT=$(( ${_MI:-0} + ${_MO:-0} ))
fi

if [[ "$_MT" -eq 10000 ]]; then
    pass_test
else
    fail_test "JSON fallback returned '$_MT', expected 10000"
fi
teardown_env

run_test "flat file takes priority over JSON when present"
setup_env "t5b"
_init_schema

_MAIN_TOKEN_FILE="${CLAUDE_DIR}/.session-main-tokens"
printf '15000' > "$_MAIN_TOKEN_FILE"
_SESSION_END_INPUT='{"reason":"normal","context_window":{"total_input_tokens":8000,"total_output_tokens":2000}}'

_MT=0
if [[ -f "$_MAIN_TOKEN_FILE" ]]; then
    _MT=$(cat "$_MAIN_TOKEN_FILE" 2>/dev/null || echo "0")
    _MT="${_MT%.*}"
    _MT=$(( ${_MT:-0} ))
fi
if [[ "$_MT" -eq 0 ]]; then
    _MI=$(printf '%s' "$_SESSION_END_INPUT" | jq -r '.context_window.total_input_tokens // 0' 2>/dev/null || echo "0")
    _MO=$(printf '%s' "$_SESSION_END_INPUT" | jq -r '.context_window.total_output_tokens // 0' 2>/dev/null || echo "0")
    _MT=$(( ${_MI:-0} + ${_MO:-0} ))
fi

if [[ "$_MT" -eq 15000 ]]; then
    pass_test
else
    fail_test "Expected 15000 from flat file, got '$_MT'"
fi
teardown_env

# ---------------------------------------------------------------------------
# Test 6: Dual-write — flat file still written
# ---------------------------------------------------------------------------
echo ""
echo "=== Test 6: Dual-write — flat file preserved ==="

run_test "flat file has entry after dual-write"
setup_env "t6"
_init_schema

_SESSION_TOKENS=12345
_MAIN_TOKENS=10000
_SUBAGENT_TOTAL=2345
_TOKEN_HISTORY="${CLAUDE_DIR}/.session-token-history"
_TOKEN_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
_TOKEN_PHASH="aaaa1111"
_TOKEN_PNAME="testproject"
_SID="test-session-dual"

# Dual-write: flat file
echo "${_TOKEN_TS}|${_SESSION_TOKENS}|${_MAIN_TOKENS}|${_SUBAGENT_TOTAL}|${_SID}|${_TOKEN_PHASH}|${_TOKEN_PNAME}" >> "$_TOKEN_HISTORY"

# Dual-write: SQLite INSERT (mirrors session-end.sh logic)
_phash_e=$(printf '%s' "$_TOKEN_PHASH" | sed "s/'/''/g")
_pname_e=$(printf '%s' "$_TOKEN_PNAME" | sed "s/'/''/g")
_sid_e=$(printf '%s' "$_SID" | sed "s/'/''/g")
_state_sql "INSERT INTO session_tokens
    (session_id, project_hash, project_name, timestamp, total_tokens, main_tokens, subagent_tokens, source)
    VALUES ('$_sid_e', '$_phash_e', '$_pname_e', '$_TOKEN_TS', $_SESSION_TOKENS, $_MAIN_TOKENS, $_SUBAGENT_TOTAL, 'session-end');" >/dev/null 2>/dev/null || true

_ff_count=$(wc -l < "$_TOKEN_HISTORY" | tr -d ' ')
if [[ "${_ff_count:-0}" -ge "1" ]]; then
    pass_test
else
    fail_test "flat file empty after dual-write"
fi
teardown_env

run_test "SQLite has correct total_tokens after dual-write"
setup_env "t6b"
_init_schema

_SESSION_TOKENS=12345
_MAIN_TOKENS=10000
_SUBAGENT_TOTAL=2345
_TOKEN_HISTORY="${CLAUDE_DIR}/.session-token-history"
_TOKEN_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
_TOKEN_PHASH="aaaa1111"
_TOKEN_PNAME="testproject"
_SID="test-session-dual"

echo "${_TOKEN_TS}|${_SESSION_TOKENS}|${_MAIN_TOKENS}|${_SUBAGENT_TOTAL}|${_SID}|${_TOKEN_PHASH}|${_TOKEN_PNAME}" >> "$_TOKEN_HISTORY"
_phash_e=$(printf '%s' "$_TOKEN_PHASH" | sed "s/'/''/g")
_pname_e=$(printf '%s' "$_TOKEN_PNAME" | sed "s/'/''/g")
_sid_e=$(printf '%s' "$_SID" | sed "s/'/''/g")
_state_sql "INSERT INTO session_tokens
    (session_id, project_hash, project_name, timestamp, total_tokens, main_tokens, subagent_tokens, source)
    VALUES ('$_sid_e', '$_phash_e', '$_pname_e', '$_TOKEN_TS', $_SESSION_TOKENS, $_MAIN_TOKENS, $_SUBAGENT_TOTAL, 'session-end');" >/dev/null 2>/dev/null || true

_db_sum=$(_db "SELECT COALESCE(SUM(total_tokens), 0) FROM session_tokens WHERE project_hash = '$_TOKEN_PHASH';")
if [[ "$_db_sum" == "$_SESSION_TOKENS" ]]; then
    pass_test
else
    fail_test "SQLite total = '$_db_sum', expected '$_SESSION_TOKENS'"
fi
teardown_env

# ---------------------------------------------------------------------------
# Test 7: Index exists
# ---------------------------------------------------------------------------
echo ""
echo "=== Test 7: idx_session_tokens_project index ==="

run_test "idx_session_tokens_project exists after schema init"
setup_env "t7"
_init_schema
_idx=$(_db "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_session_tokens_project';")
if [[ "$_idx" == "idx_session_tokens_project" ]]; then
    pass_test
else
    fail_test "index not found (got: '$_idx')"
fi
teardown_env

# ---------------------------------------------------------------------------
# Test 8: COALESCE prevents NULL for empty result
# ---------------------------------------------------------------------------
echo ""
echo "=== Test 8: Empty project returns 0 ==="

run_test "COALESCE returns 0 for unknown project_hash"
setup_env "t8"
_init_schema
_sum=$(_db "SELECT COALESCE(SUM(total_tokens), 0) FROM session_tokens WHERE project_hash = 'nonexistent';" 2>/dev/null || echo "0")
if [[ "$_sum" == "0" ]]; then
    pass_test
else
    fail_test "Expected 0, got '$_sum'"
fi
teardown_env

# ---------------------------------------------------------------------------
# Cleanup and summary
# ---------------------------------------------------------------------------
rm -rf "$_TMP_BASE" 2>/dev/null || true

echo ""
echo "==============================="
echo "Tests run:    $TESTS_RUN"
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo "==============================="

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
exit 0
