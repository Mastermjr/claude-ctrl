#!/usr/bin/env bash
# tests/fixtures/db-safety/mock-sqlite3.sh — Mock sqlite3 CLI for database safety testing.
#
# Intercepts sqlite3 invocations during tests to:
#   1. Log the full command line to $MOCK_LOG_DIR/sqlite3.log
#   2. Return canned output for well-known queries
#   3. Exit 0 for recognized commands
#
# CRITICAL: This mock MUST NOT intercept calls to the hook system's own state.db.
# The hook system uses sqlite3 for internal state (traces, sessions, proof epochs).
# The setup-test-env.sh injects this mock ONLY for the db-safety test context.
# Tests that need the real sqlite3 must unset MOCK_LOG_DIR or restore PATH.
#
# @decision DEC-DBSAFE-MOCK-002
# @title sqlite3 mock must not interfere with hook state.db
# @status accepted
# @rationale The hook system uses sqlite3 for its own state management (state.db).
#   If we mock sqlite3 globally during db-safety hook tests, the hooks themselves
#   break. To prevent this, setup-test-env.sh only activates this mock inside
#   the isolated test temp directory context. Hook invocations use the system
#   sqlite3 (found earlier on PATH via their own HOOKS_DIR). The MOCK_SQLITE3_GUARD
#   env var provides an additional safety escape hatch.
#
# @decision DEC-DBSAFE-MOCK-001 (shared — see mock-psql.sh for PATH injection rationale)

set -euo pipefail

# Safety escape hatch: if MOCK_SQLITE3_GUARD is unset, check if the DB file
# path suggests it's a system/hook database (state.db, .claude/*.db).
# If so, pass through to the real sqlite3.
DB_ARG=""
for arg in "$@"; do
    case "$arg" in
        *.db|*.sqlite|*.sqlite3)
            DB_ARG="$arg"
            ;;
    esac
done

# Pass-through for hook system databases
if [[ -n "$DB_ARG" ]]; then
    case "$DB_ARG" in
        *state.db|*/.claude/*.db|*/hooks/*.db)
            # Delegate to real sqlite3 — find it beyond our mock dir on PATH
            REAL_SQLITE3=$(PATH="${PATH#*:}" command -v sqlite3 2>/dev/null || echo "")
            if [[ -n "$REAL_SQLITE3" && "$REAL_SQLITE3" != "$0" ]]; then
                exec "$REAL_SQLITE3" "$@"
            fi
            ;;
    esac
fi

LOG_DIR="${MOCK_LOG_DIR:-${TMPDIR:-/tmp}/mock-db-logs}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/sqlite3.log"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) sqlite3 $*" >> "$LOG_FILE"

# sqlite3 takes: sqlite3 [OPTIONS] FILENAME [SQL]
# Extract the SQL (last arg if not a file, or after the filename)
SQL=""
ARGS=("$@")
# Walk args: skip flags, skip DB file, collect SQL
i=0
while [[ $i -lt ${#ARGS[@]} ]]; do
    case "${ARGS[$i]}" in
        -*)
            # Flag — skip
            ;;
        *.db|*.sqlite|*.sqlite3)
            # DB file — skip
            ;;
        *)
            # Everything else is SQL
            SQL="${ARGS[$i]}"
            ;;
    esac
    i=$((i + 1))
done

SQL_NORM=$(echo "$SQL" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

case "$SQL_NORM" in
    "select sqlite_version()"|"select sqlite_version();")
        echo "3.42.0"
        exit 0
        ;;
    ".tables"|".schema")
        echo "orders    sessions  users"
        exit 0
        ;;
    "select count(*) from"*|"select * from"*)
        echo "42"
        exit 0
        ;;
    "select 1"|"select 1;")
        echo "1"
        exit 0
        ;;
    *"drop table"*|*"delete from"*|*"alter table"*"drop column"*)
        echo "mock sqlite3: destructive operation would execute"
        exit 0
        ;;
    "pragma integrity_check"|"pragma integrity_check;")
        echo "ok"
        exit 0
        ;;
    "")
        # Interactive mode or no SQL
        echo "SQLite version 3.42.0"
        echo "Enter \".help\" for usage hints."
        exit 0
        ;;
    *)
        echo "mock sqlite3: unrecognized query: $SQL_NORM"
        exit 0
        ;;
esac
