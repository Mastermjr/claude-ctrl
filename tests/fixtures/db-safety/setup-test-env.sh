#!/usr/bin/env bash
# tests/fixtures/db-safety/setup-test-env.sh — Shared test setup for database safety tests.
#
# Provides isolated test environments for db-safety hook testing:
#   - Temp directory per test (DBSAFE_TEST_DIR)
#   - Mock DB CLIs on PATH (psql, mysql, mongosh, redis-cli, sqlite3)
#   - Standard env vars for testing (APP_ENV, DATABASE_URL, etc.)
#   - Cleanup function for guaranteed teardown
#
# Usage (source this file in test scripts):
#   source "$(dirname "$0")/fixtures/db-safety/setup-test-env.sh"
#   dbsafe_setup           # Creates temp dir + sets mock PATH
#   dbsafe_teardown        # Cleanup (also registered via trap)
#
# Or use scoped helper:
#   with_dbsafe_env "test name" "PROD|STAGING|DEV|UNKNOWN" bash -c 'psql -c "..."'
#
# @decision DEC-DBSAFE-SETUP-001
# @title Centralized setup/teardown for db-safety test isolation
# @status accepted
# @rationale Each db-safety test needs: (1) a clean temp dir, (2) mock CLIs on PATH,
#   (3) standard env vars. Without a shared setup, each test file duplicates this
#   boilerplate and diverges. Centralizing in setup-test-env.sh means Wave 2+ tests
#   source one file and get everything they need. The teardown registers via trap
#   so it runs even on test failure, preventing temp dir accumulation.

# ---------------------------------------------------------------------------
# Global state (set by dbsafe_setup, used by assertions and teardown)
# ---------------------------------------------------------------------------
DBSAFE_TEST_DIR=""       # Temp directory for current test
DBSAFE_MOCK_BIN_DIR=""   # Mock binaries directory (placed on PATH)
DBSAFE_ORIG_PATH=""      # Original PATH (restored on teardown)
DBSAFE_FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# dbsafe_setup [TEST_NAME]
#   Creates an isolated temp directory and sets mock CLIs on PATH.
#   Sets: DBSAFE_TEST_DIR, DBSAFE_MOCK_BIN_DIR, MOCK_LOG_DIR, PATH
#   Registers dbsafe_teardown via trap.
# ---------------------------------------------------------------------------
dbsafe_setup() {
    local test_name="${1:-dbsafe-test}"
    local safe_name
    safe_name=$(echo "$test_name" | tr ' /' '_-' | tr -cd '[:alnum:]_-')

    DBSAFE_ORIG_PATH="$PATH"
    DBSAFE_TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dbsafe-${safe_name}-XXXXXX")
    DBSAFE_MOCK_BIN_DIR="$DBSAFE_TEST_DIR/mock-bin"
    MOCK_LOG_DIR="$DBSAFE_TEST_DIR/mock-logs"
    export MOCK_LOG_DIR

    mkdir -p "$DBSAFE_MOCK_BIN_DIR" "$MOCK_LOG_DIR"

    # Install mock CLIs as symlinks (or copies for portability)
    for cli in psql mysql mongosh redis-cli sqlite3; do
        local mock_src="$DBSAFE_FIXTURES_DIR/mock-${cli}.sh"
        if [[ -f "$mock_src" ]]; then
            cp "$mock_src" "$DBSAFE_MOCK_BIN_DIR/$cli"
            chmod +x "$DBSAFE_MOCK_BIN_DIR/$cli"
        fi
    done

    # Place mock bin dir FIRST on PATH so it intercepts CLI calls
    PATH="$DBSAFE_MOCK_BIN_DIR:$PATH"
    export PATH

    # Register cleanup on EXIT
    trap dbsafe_teardown EXIT

    return 0
}

# ---------------------------------------------------------------------------
# dbsafe_teardown
#   Removes temp directory and restores original PATH.
#   Called automatically via trap, or manually.
# ---------------------------------------------------------------------------
dbsafe_teardown() {
    if [[ -n "$DBSAFE_ORIG_PATH" ]]; then
        PATH="$DBSAFE_ORIG_PATH"
        export PATH
        DBSAFE_ORIG_PATH=""
    fi
    if [[ -n "$DBSAFE_TEST_DIR" && -d "$DBSAFE_TEST_DIR" ]]; then
        rm -rf "$DBSAFE_TEST_DIR"
        DBSAFE_TEST_DIR=""
    fi
    unset MOCK_LOG_DIR
    trap - EXIT
}

# ---------------------------------------------------------------------------
# with_dbsafe_env ENV_PROFILE CMD [ARGS...]
#   Run CMD with the given env profile (PROD, STAGING, DEV, UNKNOWN) active.
#   Restores env vars after CMD completes.
#   Requires dbsafe_setup to have been called first.
#
#   ENV_PROFILE: PROD | STAGING | DEV | UNKNOWN (case insensitive)
# ---------------------------------------------------------------------------
with_dbsafe_env() {
    local env_profile="$1"
    shift

    # Source env-profiles.sh to get setup_* functions
    # shellcheck source=tests/fixtures/db-safety/env-profiles.sh
    source "$DBSAFE_FIXTURES_DIR/env-profiles.sh"

    # Save current env vars
    local saved_app_env="${APP_ENV:-}"
    local saved_db_url="${DATABASE_URL:-}"
    local saved_rails_env="${RAILS_ENV:-}"
    local saved_node_env="${NODE_ENV:-}"
    local saved_flask_env="${FLASK_ENV:-}"

    # Activate requested profile
    local env_profile_upper
    env_profile_upper=$(echo "$env_profile" | tr '[:lower:]' '[:upper:]')
    case "$env_profile_upper" in
        PROD|PRODUCTION)      setup_prod_env ;;
        STAGING)              setup_staging_env ;;
        DEV|DEVELOPMENT)      setup_dev_env ;;
        UNKNOWN|UNSET)        setup_unknown_env ;;
        *)
            echo "with_dbsafe_env: unknown profile '$env_profile'" >&2
            return 1
            ;;
    esac

    # Run the command
    "$@"
    local cmd_exit=$?

    # Restore env vars
    if [[ -n "$saved_app_env" ]]; then
        export APP_ENV="$saved_app_env"
    else
        unset APP_ENV
    fi
    if [[ -n "$saved_db_url" ]]; then
        export DATABASE_URL="$saved_db_url"
    else
        unset DATABASE_URL
    fi
    if [[ -n "$saved_rails_env" ]]; then
        export RAILS_ENV="$saved_rails_env"
    else
        unset RAILS_ENV
    fi
    if [[ -n "$saved_node_env" ]]; then
        export NODE_ENV="$saved_node_env"
    else
        unset NODE_ENV
    fi
    if [[ -n "$saved_flask_env" ]]; then
        export FLASK_ENV="$saved_flask_env"
    else
        unset FLASK_ENV
    fi

    return $cmd_exit
}

# ---------------------------------------------------------------------------
# dbsafe_assert_cli_called CLI [PATTERN]
#   Assert that CLI was called during the current test.
#   Optionally assert the call matched PATTERN (grep -E).
#   Outputs PASS/FAIL to stdout for human-readable test reporting.
# ---------------------------------------------------------------------------
dbsafe_assert_cli_called() {
    local cli="$1"
    local pattern="${2:-}"
    local log_file="${MOCK_LOG_DIR}/${cli}.log"

    if [[ ! -f "$log_file" ]]; then
        echo "FAIL dbsafe_assert_cli_called $cli: log file not found ($log_file)"
        return 1
    fi

    if [[ -z "$pattern" ]]; then
        echo "PASS dbsafe_assert_cli_called $cli: called at least once"
        return 0
    fi

    if grep -qE "$pattern" "$log_file"; then
        echo "PASS dbsafe_assert_cli_called $cli pattern '$pattern'"
        return 0
    else
        echo "FAIL dbsafe_assert_cli_called $cli: pattern '$pattern' not found in log:"
        cat "$log_file" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# dbsafe_assert_cli_not_called CLI
#   Assert that CLI was NOT called during the current test.
# ---------------------------------------------------------------------------
dbsafe_assert_cli_not_called() {
    local cli="$1"
    local log_file="${MOCK_LOG_DIR}/${cli}.log"

    if [[ ! -f "$log_file" ]] || [[ ! -s "$log_file" ]]; then
        echo "PASS dbsafe_assert_cli_not_called $cli"
        return 0
    fi

    echo "FAIL dbsafe_assert_cli_not_called $cli: CLI was called:"
    cat "$log_file" >&2
    return 1
}

# ---------------------------------------------------------------------------
# dbsafe_get_cli_calls CLI
#   Print all logged calls to CLI (one per line).
# ---------------------------------------------------------------------------
dbsafe_get_cli_calls() {
    local cli="$1"
    local log_file="${MOCK_LOG_DIR}/${cli}.log"
    if [[ -f "$log_file" ]]; then
        cat "$log_file"
    fi
}

# ---------------------------------------------------------------------------
# dbsafe_reset_logs
#   Clear all mock logs (for multi-step tests where you want to isolate
#   one step's calls from another's).
# ---------------------------------------------------------------------------
dbsafe_reset_logs() {
    if [[ -n "$MOCK_LOG_DIR" && -d "$MOCK_LOG_DIR" ]]; then
        rm -f "$MOCK_LOG_DIR"/*.log
    fi
}
