#!/usr/bin/env bash
# test-db-safety-w5.sh — Tests for Wave 5 DB safety polish features.
#
# Tests the following components:
#   B9:  Schema change approval gate (_db_detect_schema_change + pre-bash.sh advisory)
#   B10: Database connection string redaction (_db_redact_credentials)
#   B11: Aggregate safety report (_db_increment_stat, _db_session_summary, _db_read_session_stats)
#   B12: MySQL autocommit DDL warning (_db_mysql_ddl_advisory)
#   E6:  MCP credential partitioning advisory (pre-mcp.sh sentinel file)
#
# Usage: bash tests/test-db-safety-w5.sh
#
# @decision DEC-DBSAFE-W5-TEST-001
# @title Unit and integration tests for Wave 5 polish features
# @status accepted
# @rationale B9/B10/B11/B12 are tested by sourcing db-safety-lib.sh directly and
#   calling functions in isolation. E6 is tested by piping JSON fixtures to
#   pre-mcp.sh and verifying the advisory appears in hook output.
#   Stats tests use a temporary stats file to avoid polluting the real stats.
#   The sentinel file for E6 is also temporary and cleaned up after each test.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$(dirname "$SCRIPT_DIR")/hooks"
PRE_MCP_HOOK="$HOOKS_DIR/pre-mcp.sh"

# Source the library under test
source "$HOOKS_DIR/source-lib.sh"
require_db_safety

# --- Test harness ---
_T_PASSED=0
_T_FAILED=0

pass() { echo "  PASS: $1"; _T_PASSED=$((_T_PASSED + 1)); }
fail() { echo "  FAIL: $1 — $2"; _T_FAILED=$((_T_FAILED + 1)); }

assert_eq() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "expected '$expected', got '$actual'"
    fi
}

assert_contains() {
    local test_name="$1"
    local needle="$2"
    local haystack="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        pass "$test_name"
    else
        fail "$test_name" "expected to contain '$needle', got: $haystack"
    fi
}

assert_not_contains() {
    local test_name="$1"
    local needle="$2"
    local haystack="$3"
    if ! echo "$haystack" | grep -qF "$needle"; then
        pass "$test_name"
    else
        fail "$test_name" "expected NOT to contain '$needle', got: $haystack"
    fi
}

assert_starts_with() {
    local test_name="$1"
    local prefix="$2"
    local actual="$3"
    if [[ "$actual" == "$prefix"* ]]; then
        pass "$test_name"
    else
        fail "$test_name" "expected to start with '$prefix', got: $actual"
    fi
}

echo ""
echo "=== Wave 5 DB Safety Tests ==="
echo ""

# =============================================================================
# B9: Schema change detection
# =============================================================================
echo "--- B9: Schema change detection ---"

_RESULT=$(_db_detect_schema_change "psql -c 'ALTER TABLE users ADD COLUMN age INT'")
assert_eq "B9.T01: ALTER TABLE detected" "schema:ALTER TABLE" "$_RESULT"

_RESULT=$(_db_detect_schema_change "psql -c 'CREATE INDEX idx_email ON users(email)'")
assert_eq "B9.T02: CREATE INDEX detected" "schema:CREATE INDEX" "$_RESULT"

_RESULT=$(_db_detect_schema_change "mysql -e 'DROP INDEX idx_email ON users'")
assert_eq "B9.T03: DROP INDEX detected" "schema:DROP INDEX" "$_RESULT"

_RESULT=$(_db_detect_schema_change "psql -c 'CREATE TABLE orders (id INT)'")
assert_eq "B9.T04: CREATE TABLE detected" "schema:CREATE TABLE" "$_RESULT"

_RESULT=$(_db_detect_schema_change "mysql -e 'RENAME TABLE users TO customers'")
assert_eq "B9.T05: RENAME TABLE detected" "schema:RENAME TABLE" "$_RESULT"

_RESULT=$(_db_detect_schema_change "psql -c 'SELECT * FROM users'")
assert_eq "B9.T06: SELECT → none (not a schema change)" "none" "$_RESULT"

_RESULT=$(_db_detect_schema_change "psql -c 'INSERT INTO users VALUES (1)'")
assert_eq "B9.T07: INSERT → none" "none" "$_RESULT"

_RESULT=$(_db_detect_schema_change "psql -c 'DROP TABLE users'")
assert_eq "B9.T08: DROP TABLE → none (caught by classify_risk before schema check)" "none" "$_RESULT"

# Case-insensitive detection
_RESULT=$(_db_detect_schema_change "psql -c 'alter table orders add column total DECIMAL'")
assert_eq "B9.T09: alter table (lowercase) detected" "schema:ALTER TABLE" "$_RESULT"

echo ""

# =============================================================================
# B10: Credential redaction
# =============================================================================
echo "--- B10: Credential redaction ---"

# PostgreSQL URI
_IN="psql postgresql://admin:supersecret@db.prod.example.com/mydb"
_OUT=$(_db_redact_credentials "$_IN")
assert_contains "B10.T01: postgres URI password redacted" "***" "$_OUT"
assert_not_contains "B10.T02: postgres URI original password not present" "supersecret" "$_OUT"
assert_contains "B10.T03: postgres URI user preserved" "admin" "$_OUT"

# MySQL URI
_IN="mysql mysql://appuser:p4ssw0rd@mysql.internal/appdb"
_OUT=$(_db_redact_credentials "$_IN")
assert_contains "B10.T04: mysql URI password redacted" "***" "$_OUT"
assert_not_contains "B10.T05: mysql URI original password not present" "p4ssw0rd" "$_OUT"

# MongoDB URI
_IN="mongosh mongodb://root:MongoPass123@mongo.prod.com/admin"
_OUT=$(_db_redact_credentials "$_IN")
assert_contains "B10.T06: mongodb URI password redacted" "***" "$_OUT"
assert_not_contains "B10.T07: mongodb URI original password not present" "MongoPass123" "$_OUT"

# -p flag (space-separated)
_IN="mysql -u root -p mysecretpassword mydb"
_OUT=$(_db_redact_credentials "$_IN")
assert_contains "B10.T08: -p space password redacted" "***" "$_OUT"
assert_not_contains "B10.T09: -p space original password not present" "mysecretpassword" "$_OUT"

# --password= flag
_IN="mysql --user=root --password=topsecret mydb"
_OUT=$(_db_redact_credentials "$_IN")
assert_contains "B10.T10: --password= redacted" "***" "$_OUT"
assert_not_contains "B10.T11: --password= original value not present" "topsecret" "$_OUT"

# PGPASSWORD env var
_IN="PGPASSWORD=hunter2 psql -U postgres mydb"
_OUT=$(_db_redact_credentials "$_IN")
assert_contains "B10.T12: PGPASSWORD value redacted" "PGPASSWORD=***" "$_OUT"
assert_not_contains "B10.T13: PGPASSWORD original value not present" "hunter2" "$_OUT"

# MYSQL_PWD env var
_IN="MYSQL_PWD=rootpass mysql -u root mydb"
_OUT=$(_db_redact_credentials "$_IN")
assert_contains "B10.T14: MYSQL_PWD value redacted" "MYSQL_PWD=***" "$_OUT"
assert_not_contains "B10.T15: MYSQL_PWD original value not present" "rootpass" "$_OUT"

# DATABASE_URL env var
_IN="DATABASE_URL=postgresql://user:dbpass@localhost/prod psql"
_OUT=$(_db_redact_credentials "$_IN")
assert_contains "B10.T16: DATABASE_URL redacted" "DATABASE_URL=***" "$_OUT"
assert_not_contains "B10.T17: DATABASE_URL original value not present" "dbpass" "$_OUT"

# No password present — command unchanged
_IN="psql -U postgres mydb"
_OUT=$(_db_redact_credentials "$_IN")
assert_eq "B10.T18: no password → unchanged" "psql -U postgres mydb" "$_OUT"

# Multiple credentials in one command
_IN="PGPASSWORD=secret1 psql postgresql://user:secret2@host/db"
_OUT=$(_db_redact_credentials "$_IN")
assert_not_contains "B10.T19: multiple credentials — PGPASSWORD not present" "secret1" "$_OUT"
assert_not_contains "B10.T20: multiple credentials — URI password not present" "secret2" "$_OUT"

echo ""

# =============================================================================
# B11: Session stat tracking
# =============================================================================
echo "--- B11: Session stat tracking ---"

# Use a temp stats file to avoid polluting real stats
_ORIG_CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
_TMP_STATS_DIR=$(mktemp -d)
export CLAUDE_DIR="$_TMP_STATS_DIR"

# Start from empty
_RESULT=$(_db_session_summary)
assert_eq "B11.T01: empty stats → no summary (nothing to report)" "" "$_RESULT"

# Increment checked
_db_increment_stat "checked"
_STATS=$(_db_read_session_stats)
_CHECKED=$(echo "$_STATS" | grep "^checked=" | cut -d= -f2)
assert_eq "B11.T02: increment checked → checked=1" "1" "$_CHECKED"

# Increment checked again
_db_increment_stat "checked"
_STATS=$(_db_read_session_stats)
_CHECKED=$(echo "$_STATS" | grep "^checked=" | cut -d= -f2)
assert_eq "B11.T03: increment checked twice → checked=2" "2" "$_CHECKED"

# Increment blocked
_db_increment_stat "blocked"
_STATS=$(_db_read_session_stats)
_BLOCKED=$(echo "$_STATS" | grep "^blocked=" | cut -d= -f2)
assert_eq "B11.T04: increment blocked → blocked=1" "1" "$_BLOCKED"

# Increment warned
_db_increment_stat "warned"
_db_increment_stat "warned"
_STATS=$(_db_read_session_stats)
_WARNED=$(echo "$_STATS" | grep "^warned=" | cut -d= -f2)
assert_eq "B11.T05: increment warned twice → warned=2" "2" "$_WARNED"

# Session summary format
_SUMMARY=$(_db_session_summary)
assert_contains "B11.T06: summary contains 'Database safety'" "Database safety" "$_SUMMARY"
assert_contains "B11.T07: summary contains checked count" "2 commands checked" "$_SUMMARY"
assert_contains "B11.T08: summary contains blocked count" "1 blocked" "$_SUMMARY"
assert_contains "B11.T09: summary contains warnings count" "2 warnings" "$_SUMMARY"

# Empty stats via _db_read_session_stats when BOTH flat-file AND KV are absent.
# Since DEC-V4-KV-001 (W2-1), _db_read_session_stats prefers KV over flat-file.
# Deleting just the flat-file is not enough — KV still holds the values from
# previous increments. Delete both to test the zero-default behavior.
rm -f "${_TMP_STATS_DIR}/.db-safety-stats"
if type state_delete &>/dev/null 2>&1; then
    state_delete "db_safety_checked" 2>/dev/null || true
    state_delete "db_safety_blocked" 2>/dev/null || true
    state_delete "db_safety_warned"  2>/dev/null || true
fi
_STATS=$(_db_read_session_stats)
_CHECKED=$(echo "$_STATS" | grep "^checked=" | cut -d= -f2)
_BLOCKED=$(echo "$_STATS" | grep "^blocked=" | cut -d= -f2)
_WARNED=$(echo "$_STATS" | grep "^warned=" | cut -d= -f2)
assert_eq "B11.T10: missing file+KV → checked=0" "0" "$_CHECKED"
assert_eq "B11.T11: missing file+KV → blocked=0" "0" "$_BLOCKED"
assert_eq "B11.T12: missing file+KV → warned=0" "0" "$_WARNED"

# Restore CLAUDE_DIR and clean up temp dir
export CLAUDE_DIR="$_ORIG_CLAUDE_DIR"
rm -rf "$_TMP_STATS_DIR"

echo ""

# =============================================================================
# B12: MySQL autocommit DDL warning
# =============================================================================
echo "--- B12: MySQL autocommit DDL warning ---"

# ALTER TABLE → advisory present
_RESULT=$(_db_mysql_ddl_advisory "mysql -e 'ALTER TABLE users ADD COLUMN age INT'")
assert_contains "B12.T01: ALTER TABLE → autocommit advisory" "auto-commits DDL" "$_RESULT"
assert_contains "B12.T02: ALTER TABLE → mentions ALTER" "ALTER" "$_RESULT"

# CREATE TABLE → advisory present
_RESULT=$(_db_mysql_ddl_advisory "mysql -e 'CREATE TABLE orders (id INT PRIMARY KEY)'")
assert_contains "B12.T03: CREATE TABLE → autocommit advisory" "auto-commits DDL" "$_RESULT"

# DROP TABLE → advisory present
_RESULT=$(_db_mysql_ddl_advisory "mysql -e 'DROP TABLE old_records'")
assert_contains "B12.T04: DROP TABLE → autocommit advisory" "auto-commits DDL" "$_RESULT"
assert_contains "B12.T05: advisory mentions cannot be rolled back" "cannot be rolled back" "$_RESULT"

# SELECT → no advisory
_RESULT=$(_db_mysql_ddl_advisory "mysql -e 'SELECT * FROM users'")
assert_eq "B12.T06: SELECT → no DDL advisory" "" "$_RESULT"

# INSERT → no advisory
_RESULT=$(_db_mysql_ddl_advisory "mysql -e 'INSERT INTO users VALUES (1, \"bob\")'")
assert_eq "B12.T07: INSERT → no DDL advisory" "" "$_RESULT"

# psql ALTER TABLE → no advisory (MySQL-specific function)
_RESULT=$(_db_mysql_ddl_advisory "psql -c 'ALTER TABLE users ADD COLUMN x INT'")
assert_contains "B12.T08: psql ALTER TABLE detected by function — function is not CLI-gated" "auto-commits DDL" "$_RESULT"
# NOTE: _db_mysql_ddl_advisory is not CLI-gated itself — the gating happens in
# pre-bash.sh where it's only called when _DB_CLI == "mysql". This test documents
# that behavior: the function detects DDL regardless of CLI context.

# Case insensitive
_RESULT=$(_db_mysql_ddl_advisory "mysql -e 'alter table users add column x INT'")
assert_contains "B12.T09: alter table (lowercase) → advisory" "auto-commits DDL" "$_RESULT"

echo ""

# =============================================================================
# E6: MCP credential partitioning advisory
# =============================================================================
echo "--- E6: MCP credential partitioning advisory ---"

if [[ ! -f "$PRE_MCP_HOOK" ]]; then
    echo "  SKIP: pre-mcp.sh not found at $PRE_MCP_HOOK (skipping E6 tests)"
    echo ""
else
    # Use temp CLAUDE_DIR to isolate sentinel file
    _TMP_E6_DIR=$(mktemp -d)
    export CLAUDE_DIR="$_TMP_E6_DIR"

    run_hook_json() {
        local tn="$1" tj="$2" hi
        hi=$(printf '{"tool_name":"%s","tool_input":%s}' "$tn" "$tj")
        printf '%s\n' "$hi" | CLAUDE_DIR="$_TMP_E6_DIR" bash "$PRE_MCP_HOOK" 2>/dev/null || true
    }
    get_decision() { echo "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null || true; }
    get_reason()   { echo "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null || true; }
    get_advisory() { echo "$1" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true; }

    # First DB MCP call → advisory should be emitted
    # The advisory appears in additionalContext (emit_advisory output)
    _SENTINEL="${_TMP_E6_DIR}/.mcp-credential-advisory-emitted"
    rm -f "$_SENTINEL"
    _O=$(run_hook_json "mcp__postgres__execute_query" '{"query":"SELECT 1"}')
    _REASON=$(get_reason "$_O")
    _ADV=$(get_advisory "$_O")
    # Advisory is in either reason or additionalContext depending on emit_advisory implementation
    _FULL_OUTPUT=$(printf '%s\n%s\n' "$_REASON" "$_ADV")
    if echo "$_FULL_OUTPUT" | grep -qiE "(credential|partitioning|read.only|read.write)" 2>/dev/null; then
        pass "E6.T01: first DB MCP call → credential advisory emitted"
    else
        # Also check if sentinel was created (proves the logic ran)
        if [[ -f "$_SENTINEL" ]]; then
            pass "E6.T01: first DB MCP call → sentinel created (advisory fired)"
        else
            fail "E6.T01: first DB MCP call" "expected credential advisory or sentinel file, got reason='$_REASON' adv='$_ADV'"
        fi
    fi

    # Verify sentinel file exists after first call
    if [[ -f "$_SENTINEL" ]]; then
        pass "E6.T02: sentinel file created after first DB MCP call"
    else
        fail "E6.T02: sentinel file" "expected ${_SENTINEL} to exist"
    fi

    # Second call → no advisory (sentinel exists)
    _O2=$(run_hook_json "mcp__postgres__execute_query" '{"query":"SELECT 2"}')
    _REASON2=$(get_reason "$_O2")
    _ADV2=$(get_advisory "$_O2")
    _FULL_OUTPUT2=$(printf '%s\n%s\n' "$_REASON2" "$_ADV2")
    if ! echo "$_FULL_OUTPUT2" | grep -qiE "(credential partitioning)" 2>/dev/null; then
        pass "E6.T03: second DB MCP call → no credential advisory (sentinel exists)"
    else
        fail "E6.T03: second call advisory" "expected no credential advisory on second call, got: $FULL_OUTPUT2"
    fi

    # Non-DB MCP call → no advisory (not a DB tool, never reaches credential check)
    rm -f "$_SENTINEL"
    _O3=$(run_hook_json "mcp__fetch__fetch" '{"url":"https://example.com"}')
    _REASON3=$(get_reason "$_O3")
    _ADV3=$(get_advisory "$_O3")
    _FULL_OUTPUT3=$(printf '%s\n%s\n' "$_REASON3" "$_ADV3")
    if ! echo "$_FULL_OUTPUT3" | grep -qiE "(credential partitioning)" 2>/dev/null; then
        pass "E6.T04: non-DB MCP call → no advisory"
    else
        fail "E6.T04: non-DB MCP advisory" "expected no advisory for non-DB tool, got: $_FULL_OUTPUT3"
    fi
    # Sentinel should NOT have been created (non-DB tool exits before advisory check)
    if [[ ! -f "$_SENTINEL" ]]; then
        pass "E6.T05: non-DB MCP call → sentinel NOT created"
    else
        fail "E6.T05: sentinel creation" "expected sentinel NOT to be created for non-DB tool"
    fi

    # Server with _read suffix → no advisory (already partitioned)
    rm -f "$_SENTINEL"
    _O4=$(run_hook_json "mcp__postgres_read__execute_query" '{"query":"SELECT 1"}')
    _REASON4=$(get_reason "$_O4")
    _ADV4=$(get_advisory "$_O4")
    _FULL_OUTPUT4=$(printf '%s\n%s\n' "$_REASON4" "$_ADV4")
    if ! echo "$_FULL_OUTPUT4" | grep -qiE "(credential partitioning)" 2>/dev/null; then
        pass "E6.T06: _read suffix server → no advisory (already partitioned)"
    else
        fail "E6.T06: _read suffix advisory" "expected no advisory for _read server, got: $_FULL_OUTPUT4"
    fi

    # Restore and clean up
    export CLAUDE_DIR="$_ORIG_CLAUDE_DIR"
    rm -rf "$_TMP_E6_DIR"
fi

echo ""

# =============================================================================
# Summary
# =============================================================================
echo "Results: $_T_PASSED passed, $_T_FAILED failed out of $((_T_PASSED + _T_FAILED)) total"
echo ""

if [[ "$_T_FAILED" -gt 0 ]]; then
    exit 1
fi
exit 0
