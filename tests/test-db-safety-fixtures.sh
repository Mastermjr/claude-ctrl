#!/usr/bin/env bash
# tests/test-db-safety-fixtures.sh — Validates the db-safety test fixture infrastructure.
#
# Verifies that the fixtures in tests/fixtures/db-safety/ work correctly:
#   1. Mock CLIs are executable and produce expected output
#   2. setup-test-env.sh creates and cleans up properly
#   3. sample-commands.sh arrays are non-empty and well-formed
#   4. env-profiles.sh functions set correct variables
#   5. Mock CLIs log received commands correctly
#
# This test file is registered in run-hooks.sh as --scope dbsafe-fixtures.
# Run standalone: bash tests/test-db-safety-fixtures.sh
# Run scoped: bash tests/run-hooks.sh --scope dbsafe-fixtures
#
# @decision DEC-DBSAFE-FIXTURE-TEST-001
# @title Test the fixtures themselves before Wave 2 depends on them
# @status accepted
# @rationale The db-safety fixtures are infrastructure, not just test helpers.
#   If mock-psql.sh is broken, all Wave 2 psql tests fail silently with misleading
#   results. Testing the fixtures explicitly catches regression early and ensures
#   Wave 2 implementers get a working foundation. This follows the pattern of
#   test-source-lib.sh which tests the test library infrastructure itself.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures/db-safety"

# Source test helpers for pass/fail/skip/summary functions
# shellcheck source=tests/lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

echo "=== db-safety fixture infrastructure tests ==="
echo "Fixtures dir: $FIXTURES_DIR"
echo ""

# =============================================================================
# Section 1: File existence and executability
# =============================================================================
echo "--- fixture file existence and permissions ---"

for fixture_file in \
    mock-psql.sh \
    mock-mysql.sh \
    mock-mongosh.sh \
    mock-redis-cli.sh \
    mock-sqlite3.sh \
    setup-test-env.sh \
    sample-commands.sh \
    env-profiles.sh
do
    fpath="$FIXTURES_DIR/$fixture_file"
    if [[ ! -f "$fpath" ]]; then
        fail "$fixture_file exists" "file not found at $fpath"
    elif [[ ! -r "$fpath" ]]; then
        fail "$fixture_file readable" "file not readable"
    else
        pass "$fixture_file — exists and readable"
    fi
done

echo ""

# =============================================================================
# Section 2: Bash syntax validation
# =============================================================================
echo "--- fixture bash syntax validation ---"

for fixture_file in \
    mock-psql.sh \
    mock-mysql.sh \
    mock-mongosh.sh \
    mock-redis-cli.sh \
    mock-sqlite3.sh \
    setup-test-env.sh \
    sample-commands.sh \
    env-profiles.sh
do
    fpath="$FIXTURES_DIR/$fixture_file"
    if [[ ! -f "$fpath" ]]; then
        skip "$fixture_file syntax" "file not found"
        continue
    fi
    if bash -n "$fpath" 2>/dev/null; then
        pass "$fixture_file — bash syntax valid"
    else
        SYNTAX_ERR=$(bash -n "$fpath" 2>&1 || true)
        fail "$fixture_file syntax" "bash -n failed: $SYNTAX_ERR"
    fi
done

echo ""

# =============================================================================
# Section 3: Mock CLI executability and basic output
# =============================================================================
echo "--- mock CLI basic execution ---"

# Create isolated temp dir for this section
_MOCK_TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dbsafe-test-XXXXXX")
_MOCK_LOG_DIR="$_MOCK_TEST_DIR/logs"
mkdir -p "$_MOCK_LOG_DIR"

# Make mock scripts executable for this test
_MOCK_BIN_DIR="$_MOCK_TEST_DIR/bin"
mkdir -p "$_MOCK_BIN_DIR"
for cli in psql mysql mongosh redis-cli sqlite3; do
    src="$FIXTURES_DIR/mock-${cli}.sh"
    if [[ -f "$src" ]]; then
        cp "$src" "$_MOCK_BIN_DIR/$cli"
        chmod +x "$_MOCK_BIN_DIR/$cli"
    fi
done

# Test mock-psql: SELECT version()
if [[ -x "$_MOCK_BIN_DIR/psql" ]]; then
    _OUT=$(MOCK_LOG_DIR="$_MOCK_LOG_DIR" "$_MOCK_BIN_DIR/psql" -c "SELECT version()" 2>/dev/null)
    if echo "$_OUT" | grep -q "PostgreSQL"; then
        pass "mock-psql — SELECT version() returns PostgreSQL version"
    else
        fail "mock-psql SELECT version()" "expected 'PostgreSQL' in output, got: ${_OUT:0:100}"
    fi
else
    skip "mock-psql execution" "mock binary not installed"
fi

# Test mock-psql: \dt
if [[ -x "$_MOCK_BIN_DIR/psql" ]]; then
    _OUT=$(MOCK_LOG_DIR="$_MOCK_LOG_DIR" "$_MOCK_BIN_DIR/psql" -c '\dt' 2>/dev/null)
    if echo "$_OUT" | grep -q "users"; then
        pass "mock-psql — \\dt returns table list"
    else
        fail "mock-psql \\dt" "expected 'users' table in output, got: ${_OUT:0:100}"
    fi
else
    skip "mock-psql \\dt" "mock binary not installed"
fi

# Test mock-mysql: SHOW TABLES
if [[ -x "$_MOCK_BIN_DIR/mysql" ]]; then
    _OUT=$(MOCK_LOG_DIR="$_MOCK_LOG_DIR" "$_MOCK_BIN_DIR/mysql" -e "SHOW TABLES" 2>/dev/null)
    if echo "$_OUT" | grep -q "users"; then
        pass "mock-mysql — SHOW TABLES returns table list"
    else
        fail "mock-mysql SHOW TABLES" "expected 'users' in output, got: ${_OUT:0:100}"
    fi
else
    skip "mock-mysql SHOW TABLES" "mock binary not installed"
fi

# Test mock-mongosh: db.users.find({})
if [[ -x "$_MOCK_BIN_DIR/mongosh" ]]; then
    _OUT=$(MOCK_LOG_DIR="$_MOCK_LOG_DIR" "$_MOCK_BIN_DIR/mongosh" --eval "db.users.find({})" 2>/dev/null)
    if echo "$_OUT" | grep -q "Alice\|_id\|\["; then
        pass "mock-mongosh — db.users.find({}) returns documents"
    else
        fail "mock-mongosh find" "expected document output, got: ${_OUT:0:100}"
    fi
else
    skip "mock-mongosh execution" "mock binary not installed"
fi

# Test mock-redis-cli: PING
if [[ -x "$_MOCK_BIN_DIR/redis-cli" ]]; then
    _OUT=$(MOCK_LOG_DIR="$_MOCK_LOG_DIR" "$_MOCK_BIN_DIR/redis-cli" PING 2>/dev/null)
    if [[ "$_OUT" == "PONG" ]]; then
        pass "mock-redis-cli — PING returns PONG"
    else
        fail "mock-redis-cli PING" "expected 'PONG', got: ${_OUT:0:50}"
    fi
else
    skip "mock-redis-cli PING" "mock binary not installed"
fi

# Test mock-redis-cli: GET
if [[ -x "$_MOCK_BIN_DIR/redis-cli" ]]; then
    _OUT=$(MOCK_LOG_DIR="$_MOCK_LOG_DIR" "$_MOCK_BIN_DIR/redis-cli" GET "session:123" 2>/dev/null)
    if echo "$_OUT" | grep -q "mock-value\|session"; then
        pass "mock-redis-cli — GET returns mock value"
    else
        fail "mock-redis-cli GET" "expected mock value, got: ${_OUT:0:50}"
    fi
else
    skip "mock-redis-cli GET" "mock binary not installed"
fi

# Test mock-sqlite3: SELECT sqlite_version()
if [[ -x "$_MOCK_BIN_DIR/sqlite3" ]]; then
    _OUT=$(MOCK_LOG_DIR="$_MOCK_LOG_DIR" "$_MOCK_BIN_DIR/sqlite3" test.db "SELECT sqlite_version()" 2>/dev/null)
    if echo "$_OUT" | grep -qE "^[0-9]+\.[0-9]+"; then
        pass "mock-sqlite3 — SELECT sqlite_version() returns version"
    else
        fail "mock-sqlite3 version" "expected version number, got: ${_OUT:0:50}"
    fi
else
    skip "mock-sqlite3 execution" "mock binary not installed"
fi

# Cleanup
rm -rf "$_MOCK_TEST_DIR"

echo ""

# =============================================================================
# Section 4: Command logging verification
# =============================================================================
echo "--- mock CLI command logging ---"

_LOG_TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dbsafe-log-XXXXXX")
_LOG_DIR="$_LOG_TEST_DIR/logs"
mkdir -p "$_LOG_DIR"
_LOG_BIN_DIR="$_LOG_TEST_DIR/bin"
mkdir -p "$_LOG_BIN_DIR"
for cli in psql mysql redis-cli; do
    src="$FIXTURES_DIR/mock-${cli}.sh"
    if [[ -f "$src" ]]; then
        cp "$src" "$_LOG_BIN_DIR/$cli"
        chmod +x "$_LOG_BIN_DIR/$cli"
    fi
done

# Run psql and check log
if [[ -x "$_LOG_BIN_DIR/psql" ]]; then
    MOCK_LOG_DIR="$_LOG_DIR" "$_LOG_BIN_DIR/psql" -c "SELECT 1" >/dev/null 2>/dev/null || true
    if [[ -f "$_LOG_DIR/psql.log" ]] && grep -q "psql" "$_LOG_DIR/psql.log"; then
        pass "mock-psql — logs command to psql.log"
    else
        fail "mock-psql logging" "psql.log not created or empty after invocation"
    fi
else
    skip "mock-psql logging" "mock binary not installed"
fi

# Run mysql and check log
if [[ -x "$_LOG_BIN_DIR/mysql" ]]; then
    MOCK_LOG_DIR="$_LOG_DIR" "$_LOG_BIN_DIR/mysql" -e "SELECT 1" >/dev/null 2>/dev/null || true
    if [[ -f "$_LOG_DIR/mysql.log" ]] && grep -q "mysql" "$_LOG_DIR/mysql.log"; then
        pass "mock-mysql — logs command to mysql.log"
    else
        fail "mock-mysql logging" "mysql.log not created or empty after invocation"
    fi
else
    skip "mock-mysql logging" "mock binary not installed"
fi

# Run redis-cli and check log
if [[ -x "$_LOG_BIN_DIR/redis-cli" ]]; then
    MOCK_LOG_DIR="$_LOG_DIR" "$_LOG_BIN_DIR/redis-cli" GET key:123 >/dev/null 2>/dev/null || true
    if [[ -f "$_LOG_DIR/redis-cli.log" ]] && grep -q "redis-cli" "$_LOG_DIR/redis-cli.log"; then
        pass "mock-redis-cli — logs command to redis-cli.log"
    else
        fail "mock-redis-cli logging" "redis-cli.log not created or empty"
    fi
else
    skip "mock-redis-cli logging" "mock binary not installed"
fi

# Verify log contains the args we passed
if [[ -x "$_LOG_BIN_DIR/psql" ]]; then
    MOCK_LOG_DIR="$_LOG_DIR" "$_LOG_BIN_DIR/psql" -c "SELECT * FROM audit_log" >/dev/null 2>/dev/null || true
    if grep -q "audit_log" "$_LOG_DIR/psql.log" 2>/dev/null; then
        pass "mock-psql — log contains passed arguments"
    else
        fail "mock-psql log args" "expected 'audit_log' in psql.log, got: $(cat "$_LOG_DIR/psql.log" 2>/dev/null)"
    fi
else
    skip "mock-psql log args" "mock binary not installed"
fi

# Cleanup
rm -rf "$_LOG_TEST_DIR"

echo ""

# =============================================================================
# Section 5: setup-test-env.sh lifecycle
# =============================================================================
echo "--- setup-test-env.sh lifecycle ---"

if [[ ! -f "$FIXTURES_DIR/setup-test-env.sh" ]]; then
    skip "setup-test-env.sh lifecycle" "setup-test-env.sh not found"
else
    # Source and test setup
    # shellcheck source=tests/fixtures/db-safety/setup-test-env.sh
    source "$FIXTURES_DIR/setup-test-env.sh"

    # Override trap so dbsafe_teardown doesn't fire prematurely within this test
    trap '' EXIT

    _SETUP_PASSED=true

    # Test dbsafe_setup creates temp dir
    dbsafe_setup "lifecycle-test"
    if [[ -n "$DBSAFE_TEST_DIR" && -d "$DBSAFE_TEST_DIR" ]]; then
        pass "setup-test-env.sh — dbsafe_setup creates DBSAFE_TEST_DIR"
    else
        fail "setup-test-env.sh DBSAFE_TEST_DIR" "DBSAFE_TEST_DIR not set or not a directory"
        _SETUP_PASSED=false
    fi

    # Test MOCK_LOG_DIR is set
    if [[ -n "${MOCK_LOG_DIR:-}" && -d "$MOCK_LOG_DIR" ]]; then
        pass "setup-test-env.sh — MOCK_LOG_DIR set and created"
    else
        fail "setup-test-env.sh MOCK_LOG_DIR" "MOCK_LOG_DIR=${MOCK_LOG_DIR:-unset}"
        _SETUP_PASSED=false
    fi

    # Test mock CLIs are on PATH
    _MOCK_PSQL=$(command -v psql 2>/dev/null || echo "")
    if [[ -n "$_MOCK_PSQL" && "$_MOCK_PSQL" == "$DBSAFE_MOCK_BIN_DIR/psql" ]]; then
        pass "setup-test-env.sh — mock psql is first on PATH"
    else
        fail "setup-test-env.sh PATH" "psql on PATH: $_MOCK_PSQL, expected: $DBSAFE_MOCK_BIN_DIR/psql"
        _SETUP_PASSED=false
    fi

    # Save temp dir path before teardown
    _SAVED_TEST_DIR="$DBSAFE_TEST_DIR"

    # Test dbsafe_teardown cleans up
    dbsafe_teardown

    if [[ ! -d "$_SAVED_TEST_DIR" ]]; then
        pass "setup-test-env.sh — dbsafe_teardown removes temp dir"
    else
        fail "setup-test-env.sh teardown" "temp dir still exists after teardown: $_SAVED_TEST_DIR"
        rm -rf "$_SAVED_TEST_DIR"  # cleanup manually to avoid polluting system
    fi

    # Test PATH is restored after teardown
    _MOCK_PSQL_AFTER=$(command -v psql 2>/dev/null || echo "not-found")
    if [[ "$_MOCK_PSQL_AFTER" != "$DBSAFE_MOCK_BIN_DIR/psql" ]]; then
        pass "setup-test-env.sh — PATH restored after teardown"
    else
        fail "setup-test-env.sh PATH restore" "mock psql still on PATH after teardown"
    fi

    # Restore proper EXIT trap for cleanup
    trap - EXIT
fi

echo ""

# =============================================================================
# Section 6: sample-commands.sh array validation
# =============================================================================
echo "--- sample-commands.sh array validation ---"

if [[ ! -f "$FIXTURES_DIR/sample-commands.sh" ]]; then
    skip "sample-commands.sh arrays" "file not found"
else
    # Source the catalog
    # shellcheck source=tests/fixtures/db-safety/sample-commands.sh
    source "$FIXTURES_DIR/sample-commands.sh"

    # Check each array is non-empty
    if [[ ${#DB_CMDS_DESTRUCTIVE[@]} -gt 0 ]]; then
        pass "sample-commands.sh — DB_CMDS_DESTRUCTIVE non-empty (${#DB_CMDS_DESTRUCTIVE[@]} entries)"
    else
        fail "sample-commands.sh DB_CMDS_DESTRUCTIVE" "array is empty"
    fi

    if [[ ${#DB_CMDS_SAFE[@]} -gt 0 ]]; then
        pass "sample-commands.sh — DB_CMDS_SAFE non-empty (${#DB_CMDS_SAFE[@]} entries)"
    else
        fail "sample-commands.sh DB_CMDS_SAFE" "array is empty"
    fi

    if [[ ${#DB_CMDS_IAC_DESTRUCTIVE[@]} -gt 0 ]]; then
        pass "sample-commands.sh — DB_CMDS_IAC_DESTRUCTIVE non-empty (${#DB_CMDS_IAC_DESTRUCTIVE[@]} entries)"
    else
        fail "sample-commands.sh DB_CMDS_IAC_DESTRUCTIVE" "array is empty"
    fi

    if [[ ${#DB_CMDS_MIGRATIONS[@]} -gt 0 ]]; then
        pass "sample-commands.sh — DB_CMDS_MIGRATIONS non-empty (${#DB_CMDS_MIGRATIONS[@]} entries)"
    else
        fail "sample-commands.sh DB_CMDS_MIGRATIONS" "array is empty"
    fi

    # Validate structure: each entry should be a non-empty string starting with a CLI name
    _DESTRUCTIVE_MALFORMED=0
    for cmd in "${DB_CMDS_DESTRUCTIVE[@]}"; do
        if [[ -z "$cmd" ]]; then
            _DESTRUCTIVE_MALFORMED=$((_DESTRUCTIVE_MALFORMED + 1))
        fi
    done
    if [[ $_DESTRUCTIVE_MALFORMED -eq 0 ]]; then
        pass "sample-commands.sh — DB_CMDS_DESTRUCTIVE: no empty entries"
    else
        fail "sample-commands.sh DB_CMDS_DESTRUCTIVE format" "$_DESTRUCTIVE_MALFORMED empty entries found"
    fi

    # Verify known commands are present
    _FOUND_PSQL_DROP=false
    _FOUND_REDIS_FLUSH=false
    _FOUND_MONGO_DROP=false
    for cmd in "${DB_CMDS_DESTRUCTIVE[@]}"; do
        [[ "$cmd" == *"DROP TABLE"* || "$cmd" == *"drop table"* ]] && _FOUND_PSQL_DROP=true
        [[ "$cmd" == *"FLUSHALL"* ]] && _FOUND_REDIS_FLUSH=true
        [[ "$cmd" == *"db.users.drop()"* ]] && _FOUND_MONGO_DROP=true
    done
    if [[ "$_FOUND_PSQL_DROP" == "true" ]]; then
        pass "sample-commands.sh — DB_CMDS_DESTRUCTIVE contains DROP TABLE"
    else
        fail "sample-commands.sh destructive coverage" "expected DROP TABLE entry"
    fi
    if [[ "$_FOUND_REDIS_FLUSH" == "true" ]]; then
        pass "sample-commands.sh — DB_CMDS_DESTRUCTIVE contains FLUSHALL"
    else
        fail "sample-commands.sh destructive coverage" "expected FLUSHALL entry"
    fi
    if [[ "$_FOUND_MONGO_DROP" == "true" ]]; then
        pass "sample-commands.sh — DB_CMDS_DESTRUCTIVE contains mongosh drop"
    else
        fail "sample-commands.sh destructive coverage" "expected mongosh drop entry"
    fi

    # Verify migration commands are present
    _FOUND_MIGRATION=false
    for cmd in "${DB_CMDS_MIGRATIONS[@]}"; do
        [[ "$cmd" == *"migrate"* ]] && _FOUND_MIGRATION=true
    done
    if [[ "$_FOUND_MIGRATION" == "true" ]]; then
        pass "sample-commands.sh — DB_CMDS_MIGRATIONS contains migration commands"
    else
        fail "sample-commands.sh migrations" "expected migrate commands"
    fi

    # Verify dbcmds_describe helper works
    _DESC=$(dbcmds_describe 'psql -c "DROP TABLE users"')
    if [[ -n "$_DESC" ]]; then
        pass "sample-commands.sh — dbcmds_describe returns non-empty description"
    else
        fail "sample-commands.sh dbcmds_describe" "returned empty string"
    fi

    # Verify dbcmds_get_cli helper works
    _CLI=$(dbcmds_get_cli 'psql -c "DROP TABLE users"')
    if [[ "$_CLI" == "psql" ]]; then
        pass "sample-commands.sh — dbcmds_get_cli extracts 'psql'"
    else
        fail "sample-commands.sh dbcmds_get_cli" "expected 'psql', got: '$_CLI'"
    fi
fi

echo ""

# =============================================================================
# Section 7: env-profiles.sh function validation
# =============================================================================
echo "--- env-profiles.sh function validation ---"

if [[ ! -f "$FIXTURES_DIR/env-profiles.sh" ]]; then
    skip "env-profiles.sh functions" "file not found"
else
    # shellcheck source=tests/fixtures/db-safety/env-profiles.sh
    source "$FIXTURES_DIR/env-profiles.sh"

    # Test setup_prod_env
    teardown_env
    setup_prod_env
    if [[ "${APP_ENV:-}" == "production" ]]; then
        pass "env-profiles.sh — setup_prod_env sets APP_ENV=production"
    else
        fail "env-profiles.sh setup_prod_env" "APP_ENV=${APP_ENV:-unset}, expected 'production'"
    fi
    if [[ -n "${DATABASE_URL:-}" ]] && echo "${DATABASE_URL}" | grep -q "prod"; then
        pass "env-profiles.sh — setup_prod_env sets prod DATABASE_URL"
    else
        fail "env-profiles.sh prod DATABASE_URL" "DATABASE_URL=${DATABASE_URL:-unset}"
    fi

    # Test is_prod_env returns true for production
    if is_prod_env; then
        pass "env-profiles.sh — is_prod_env returns true after setup_prod_env"
    else
        fail "env-profiles.sh is_prod_env" "returned false when APP_ENV=production"
    fi

    # Test setup_staging_env
    teardown_env
    setup_staging_env
    if [[ "${APP_ENV:-}" == "staging" ]]; then
        pass "env-profiles.sh — setup_staging_env sets APP_ENV=staging"
    else
        fail "env-profiles.sh setup_staging_env" "APP_ENV=${APP_ENV:-unset}"
    fi

    # Test is_prod_env returns false for staging
    if ! is_prod_env; then
        pass "env-profiles.sh — is_prod_env returns false after setup_staging_env"
    else
        fail "env-profiles.sh is_prod_env staging" "returned true when APP_ENV=staging"
    fi

    # Test setup_dev_env
    teardown_env
    setup_dev_env
    if [[ "${APP_ENV:-}" == "development" ]]; then
        pass "env-profiles.sh — setup_dev_env sets APP_ENV=development"
    else
        fail "env-profiles.sh setup_dev_env" "APP_ENV=${APP_ENV:-unset}"
    fi
    if [[ -n "${DATABASE_URL:-}" ]] && echo "${DATABASE_URL}" | grep -q "localhost"; then
        pass "env-profiles.sh — setup_dev_env sets localhost DATABASE_URL"
    else
        fail "env-profiles.sh dev DATABASE_URL" "DATABASE_URL=${DATABASE_URL:-unset}"
    fi

    # Test setup_unknown_env unsets all env vars
    setup_prod_env  # set them first
    setup_unknown_env
    if [[ -z "${APP_ENV:-}" && -z "${RAILS_ENV:-}" && -z "${NODE_ENV:-}" ]]; then
        pass "env-profiles.sh — setup_unknown_env unsets all env vars"
    else
        fail "env-profiles.sh setup_unknown_env" "vars still set: APP_ENV=${APP_ENV:-}, RAILS_ENV=${RAILS_ENV:-}, NODE_ENV=${NODE_ENV:-}"
    fi

    # Test teardown_env
    setup_prod_env
    teardown_env
    if [[ -z "${APP_ENV:-}" && -z "${DATABASE_URL:-}" ]]; then
        pass "env-profiles.sh — teardown_env clears APP_ENV and DATABASE_URL"
    else
        fail "env-profiles.sh teardown_env" "APP_ENV=${APP_ENV:-}, DATABASE_URL=${DATABASE_URL:-}"
    fi

    # Test env_describe returns non-empty string
    setup_prod_env
    _DESC=$(env_describe)
    if [[ -n "$_DESC" ]]; then
        pass "env-profiles.sh — env_describe returns non-empty in prod env"
    else
        fail "env-profiles.sh env_describe" "returned empty string"
    fi
    teardown_env

    # Test url-only production detection
    setup_url_only_prod_env
    if is_prod_env; then
        pass "env-profiles.sh — is_prod_env detects production from DATABASE_URL hostname"
    else
        fail "env-profiles.sh url-based prod detection" "is_prod_env returned false for prod hostname URL"
    fi
    teardown_env
fi

echo ""

# =============================================================================
# Summary
# =============================================================================
summary
