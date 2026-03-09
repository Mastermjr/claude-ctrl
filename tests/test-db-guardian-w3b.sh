#!/usr/bin/env bash
# test-db-guardian-w3b.sh — Unit tests for db-guardian-lib.sh Wave 3b
#
# Tests Wave 3b additions (D3/D4/D5):
#   D3: _dbg_classify_operation — read/write_dml/write_ddl/admin classification
#       _dbg_detect_cascade_risk — FK cascade heuristics
#       _dbg_detect_unbounded — DELETE/UPDATE without WHERE
#       _dbg_evaluate_policy — 9-rule deterministic policy engine
#   D4: _dbg_simulate_explain — EXPLAIN command builder per CLI type
#       _dbg_simulate_rollback — BEGIN/ROLLBACK wrapper command builder
#       _dbg_simulate_dryrun — DDL dry-run description generator
#   D5: _dbg_request_approval — structured approval request emitter
#       _dbg_check_approval — approval token checker via state store
#
# Usage: bash tests/test-db-guardian-w3b.sh
#
# @decision DEC-DBGUARD-W3B-TEST-001
# @title Unit tests for Wave 3b policy engine, simulation helpers, approval gate
# @status accepted
# @rationale All tests source db-guardian-lib.sh directly and call functions in
#   isolation. State functions (state_read/state_update) are tested with a real
#   in-memory state store (temp dir). No mocks for internal functions — all tested
#   against real implementations per Sacred Practice #5. Results format matches
#   Wave 2b (PASS/FAIL prefix) for run-hooks.sh aggregation compatibility.
#   Minimum 35 tests required; this file provides 40+.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$(dirname "$SCRIPT_DIR")/hooks"

# Source the libraries under test
source "$HOOKS_DIR/source-lib.sh"

# We need state functions for D5 approval gate tests
require_state

# Now source the guardian lib (not db-safety-lib — guardian is a separate layer)
# db-guardian-lib.sh is the new file we're creating
source "$HOOKS_DIR/db-guardian-lib.sh"

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

assert_not_eq() {
    local test_name="$1"
    local unexpected="$2"
    local actual="$3"
    if [[ "$actual" != "$unexpected" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "expected NOT '$unexpected', got '$actual'"
    fi
}

echo ""
echo "=== Wave 3b DB Guardian Tests (D3/D4/D5) ==="
echo ""

# =============================================================================
# D3: Operation Classification
# =============================================================================
echo "--- D3: _dbg_classify_operation ---"

assert_eq "classify: SELECT is read" \
    "read" \
    "$(_dbg_classify_operation "SELECT * FROM users")"

assert_eq "classify: select lowercase is read" \
    "read" \
    "$(_dbg_classify_operation "select id, name from accounts where id=1")"

assert_eq "classify: INSERT is write_dml" \
    "write_dml" \
    "$(_dbg_classify_operation "INSERT INTO users (name) VALUES ('alice')")"

assert_eq "classify: UPDATE is write_dml" \
    "write_dml" \
    "$(_dbg_classify_operation "UPDATE users SET active=false WHERE id=5")"

assert_eq "classify: DELETE is write_dml" \
    "write_dml" \
    "$(_dbg_classify_operation "DELETE FROM sessions WHERE expires < NOW()")"

assert_eq "classify: CREATE TABLE is write_ddl" \
    "write_ddl" \
    "$(_dbg_classify_operation "CREATE TABLE orders (id SERIAL PRIMARY KEY)")"

assert_eq "classify: DROP TABLE is write_ddl" \
    "write_ddl" \
    "$(_dbg_classify_operation "DROP TABLE IF EXISTS temp_data")"

assert_eq "classify: ALTER TABLE is write_ddl" \
    "write_ddl" \
    "$(_dbg_classify_operation "ALTER TABLE users ADD COLUMN last_login TIMESTAMP")"

assert_eq "classify: TRUNCATE is write_ddl" \
    "write_ddl" \
    "$(_dbg_classify_operation "TRUNCATE TABLE audit_log")"

assert_eq "classify: CREATE INDEX is write_ddl" \
    "write_ddl" \
    "$(_dbg_classify_operation "CREATE INDEX idx_users_email ON users(email)")"

assert_eq "classify: GRANT is admin" \
    "admin" \
    "$(_dbg_classify_operation "GRANT SELECT ON users TO readonly_role")"

assert_eq "classify: REVOKE is admin" \
    "admin" \
    "$(_dbg_classify_operation "REVOKE ALL ON orders FROM public")"

echo ""
echo "--- D3: _dbg_detect_cascade_risk ---"

assert_eq "cascade: DELETE with REFERENCES is risky" \
    "true" \
    "$(_dbg_detect_cascade_risk "DELETE FROM parent WHERE id=1 -- has REFERENCES children")"

assert_eq "cascade: DROP TABLE with CASCADE is risky" \
    "true" \
    "$(_dbg_detect_cascade_risk "DROP TABLE orders CASCADE")"

assert_eq "cascade: DELETE with ON DELETE CASCADE mention" \
    "true" \
    "$(_dbg_detect_cascade_risk "DELETE FROM users WHERE id=1 -- ON DELETE CASCADE will remove orders")"

assert_eq "cascade: simple SELECT is not risky" \
    "false" \
    "$(_dbg_detect_cascade_risk "SELECT * FROM users")"

assert_eq "cascade: bounded UPDATE is not risky" \
    "false" \
    "$(_dbg_detect_cascade_risk "UPDATE users SET status='active' WHERE id=42")"

assert_eq "cascade: FOREIGN KEY mention is risky" \
    "true" \
    "$(_dbg_detect_cascade_risk "ALTER TABLE orders ADD FOREIGN KEY (user_id) REFERENCES users(id)")"

echo ""
echo "--- D3: _dbg_detect_unbounded ---"

assert_eq "unbounded: DELETE without WHERE is true" \
    "true" \
    "$(_dbg_detect_unbounded "DELETE FROM sessions")"

assert_eq "unbounded: UPDATE without WHERE is true" \
    "true" \
    "$(_dbg_detect_unbounded "UPDATE users SET active=false")"

assert_eq "unbounded: DELETE with WHERE is false" \
    "false" \
    "$(_dbg_detect_unbounded "DELETE FROM sessions WHERE expires < NOW()")"

assert_eq "unbounded: UPDATE with WHERE is false" \
    "false" \
    "$(_dbg_detect_unbounded "UPDATE users SET status='active' WHERE id=5")"

assert_eq "unbounded: SELECT is false (not a DML write)" \
    "false" \
    "$(_dbg_detect_unbounded "SELECT * FROM users")"

assert_eq "unbounded: DELETE with LIMIT is bounded" \
    "false" \
    "$(_dbg_detect_unbounded "DELETE FROM audit_log WHERE id IN (SELECT id FROM audit_log ORDER BY created_at LIMIT 100)")"

echo ""
echo "--- D3: _dbg_evaluate_policy ---"

# Rule: prod-readonly — write in production denied without approval
result="$(_dbg_evaluate_policy "write_dml" "production" "UPDATE users SET active=false WHERE id=1")"
assert_starts_with "policy: prod-readonly write denied" "deny|prod-readonly:" "$result"

# Rule: prod-no-ddl — DDL in production denied (no CASCADE, no backup, but backup-required fires first;
# use a schema object that won't trigger cascade-check)
result="$(_dbg_evaluate_policy "write_ddl" "production" "DROP TABLE users" "" "true")"
assert_starts_with "policy: prod-no-ddl DDL denied" "deny|prod-no-ddl:" "$result"

# Rule: prod-readonly with approval token — write allowed
result="$(_dbg_evaluate_policy "write_dml" "production" "UPDATE users SET active=false WHERE id=1" "approved" "true")"
assert_starts_with "policy: prod-readonly approved write allowed" "allow|prod-readonly-approved:" "$result"

# Rule: staging-approval — destructive DML in staging escalates
result="$(_dbg_evaluate_policy "write_dml" "staging" "DELETE FROM sessions WHERE user_id=5")"
assert_starts_with "policy: staging-approval escalates" "escalate|staging-approval:" "$result"

# Rule: dev-permissive — any operation in development is allowed (bounded query avoids unbounded-delete)
result="$(_dbg_evaluate_policy "write_dml" "development" "DELETE FROM test_data WHERE created_at < '2020-01-01'")"
assert_starts_with "policy: dev-permissive allows" "allow|dev-permissive:" "$result"

# Rule: dev-permissive — DDL in development is allowed
result="$(_dbg_evaluate_policy "write_ddl" "development" "DROP TABLE temp_fixtures")"
assert_starts_with "policy: dev-permissive DDL allowed" "allow|dev-permissive:" "$result"

# Rule: local-permissive — any operation against localhost is allowed (bounded query)
result="$(_dbg_evaluate_policy "write_dml" "local" "DELETE FROM cache WHERE expires < NOW()")"
assert_starts_with "policy: local-permissive allows" "allow|local-permissive:" "$result"

# Rule: unknown-conservative — write in unknown environment denied (bounded UPDATE with WHERE)
result="$(_dbg_evaluate_policy "write_dml" "unknown" "UPDATE config SET value='x' WHERE key='debug'")"
assert_starts_with "policy: unknown-conservative denies write" "deny|unknown-conservative:" "$result"

# Rule: read in unknown env — reads are allowed
result="$(_dbg_evaluate_policy "read" "unknown" "SELECT * FROM users")"
assert_starts_with "policy: read in unknown env allowed" "allow|" "$result"

# Rule: cascade-check — DELETE with CASCADE escalates regardless of env
result="$(_dbg_evaluate_policy "write_dml" "development" "DELETE FROM parent CASCADE")"
assert_starts_with "policy: cascade-check escalates in dev" "escalate|cascade-check:" "$result"

# Rule: unbounded-delete — DELETE without WHERE in prod is denied
result="$(_dbg_evaluate_policy "write_dml" "production" "DELETE FROM sessions")"
assert_starts_with "policy: unbounded-delete denied in prod" "deny|unbounded-delete:" "$result"

# Rule: unbounded-delete — DELETE without WHERE in staging is denied
result="$(_dbg_evaluate_policy "write_dml" "staging" "DELETE FROM cache")"
assert_starts_with "policy: unbounded-delete denied in staging" "deny|unbounded-delete:" "$result"

# Rule: backup-required — DDL in prod without backup denied
result="$(_dbg_evaluate_policy "write_ddl" "production" "ALTER TABLE users ADD COLUMN x INT" "" "false")"
assert_starts_with "policy: backup-required DDL in prod denied" "deny|backup-required:" "$result"

# Rule: backup-required — DDL in prod with backup should proceed to other checks
result="$(_dbg_evaluate_policy "write_ddl" "production" "ALTER TABLE users ADD COLUMN x INT" "" "true")"
# With backup verified, it should hit prod-no-ddl (DDL still denied unless approved in prod)
assert_starts_with "policy: DDL in prod with backup hits prod-no-ddl" "deny|prod-no-ddl:" "$result"

# Rule: read in staging is allowed
result="$(_dbg_evaluate_policy "read" "staging" "SELECT COUNT(*) FROM orders")"
assert_starts_with "policy: read in staging allowed" "allow|" "$result"

echo ""

# =============================================================================
# D4: Simulation Helpers
# =============================================================================
echo "--- D4: _dbg_simulate_explain ---"

# psql: DML gets EXPLAIN ANALYZE false
result="$(_dbg_simulate_explain "psql" "SELECT * FROM users" "")"
assert_contains "simulate_explain psql SELECT" "EXPLAIN (ANALYZE false)" "$result"

# psql: INSERT gets EXPLAIN
result="$(_dbg_simulate_explain "psql" "INSERT INTO t VALUES (1)" "")"
assert_contains "simulate_explain psql INSERT has EXPLAIN" "EXPLAIN" "$result"

# mysql: command contains EXPLAIN keyword
result="$(_dbg_simulate_explain "mysql" "SELECT * FROM users" "")"
assert_contains "simulate_explain mysql has EXPLAIN" "EXPLAIN" "$result"

# mongosh: gets explain() wrapper
result="$(_dbg_simulate_explain "mongosh" "db.users.find({})" "")"
assert_contains "simulate_explain mongosh explain" "explain()" "$result"

# redis-cli: returns unsupported
result="$(_dbg_simulate_explain "redis-cli" "GET key" "")"
assert_eq "simulate_explain redis unsupported" "unsupported" "$result"

# sqlite3: returns unsupported (no EXPLAIN ANALYZE in sqlite3)
result="$(_dbg_simulate_explain "sqlite3" "SELECT * FROM t" "")"
assert_contains "simulate_explain sqlite3" "EXPLAIN" "$result"

echo ""
echo "--- D4: _dbg_simulate_rollback ---"

# psql: wraps in BEGIN/ROLLBACK
result="$(_dbg_simulate_rollback "psql" "DELETE FROM users WHERE id=1" "")"
assert_contains "simulate_rollback psql has BEGIN" "BEGIN" "$result"
assert_contains "simulate_rollback psql has ROLLBACK" "ROLLBACK" "$result"

# mysql DDL auto-commits — returns error message
result="$(_dbg_simulate_rollback "mysql" "DROP TABLE users" "")"
assert_contains "simulate_rollback mysql DDL caveat" "auto-commit" "$result"

# redis-cli: no rollback simulation
result="$(_dbg_simulate_rollback "redis-cli" "DEL key" "")"
assert_eq "simulate_rollback redis unsupported" "unsupported" "$result"

echo ""
echo "--- D4: _dbg_simulate_dryrun ---"

# DDL on psql — describes what would happen
result="$(_dbg_simulate_dryrun "psql" "DROP TABLE orders")"
assert_contains "simulate_dryrun DROP TABLE description" "DROP TABLE" "$result"

# DDL on mysql — notes MySQL auto-commits DDL
result="$(_dbg_simulate_dryrun "mysql" "ALTER TABLE users ADD COLUMN x INT")"
assert_contains "simulate_dryrun mysql ALTER description" "ALTER TABLE" "$result"

# CREATE TABLE on sqlite3 — describe contains CREATE reference
result="$(_dbg_simulate_dryrun "sqlite3" "CREATE TABLE x (id INT)")"
assert_contains "simulate_dryrun sqlite3 CREATE description" "CREATE" "$result"

echo ""

# =============================================================================
# D5: Approval Gate
# =============================================================================
echo "--- D5: _dbg_request_approval / _dbg_check_approval ---"

# Setup: use a temp CLAUDE_DIR so state doesn't pollute real state.db
_ORIG_CLAUDE_DIR="${CLAUDE_DIR:-}"
export CLAUDE_DIR
CLAUDE_DIR="$(mktemp -d)"
mkdir -p "$CLAUDE_DIR/state"

# Initialize state.db schema
require_state

# Test: request approval creates pending state
exec_id="test-$(date +%s)-$$"
approval_json="$(_dbg_request_approval "DROP TABLE critical_data" "Would drop 50000 rows" "$exec_id")"
assert_contains "request_approval returns JSON" "approval_request" "$approval_json"
assert_contains "request_approval has exec_id" "$exec_id" "$approval_json"
assert_contains "request_approval has operation" "DROP TABLE" "$approval_json"

# After request, check_approval should be pending
approval_status="$(_dbg_check_approval "$exec_id")"
assert_eq "check_approval starts pending" "pending" "$approval_status"

# Simulate user approval: write approved token
state_update "dbg.approval.${exec_id}" "approved" "test"

# After approval write, check_approval should be approved
approval_status="$(_dbg_check_approval "$exec_id")"
assert_eq "check_approval after user approval" "approved" "$approval_status"

# Test: unknown exec_id returns pending (safe default)
approval_status="$(_dbg_check_approval "nonexistent-exec-id")"
assert_eq "check_approval unknown id is pending" "pending" "$approval_status"

# Cleanup temp state dir
rm -rf "$CLAUDE_DIR"
if [[ -n "$_ORIG_CLAUDE_DIR" ]]; then
    CLAUDE_DIR="$_ORIG_CLAUDE_DIR"
else
    unset CLAUDE_DIR
fi

echo ""

# =============================================================================
# Results
# =============================================================================
_T_TOTAL=$((_T_PASSED + _T_FAILED))
echo "Results: $_T_PASSED passed, $_T_FAILED failed, $_T_TOTAL total"
echo ""

if [[ $_T_FAILED -gt 0 ]]; then
    echo "SOME TESTS FAILED"
    exit 1
else
    echo "ALL TESTS PASSED"
    exit 0
fi
