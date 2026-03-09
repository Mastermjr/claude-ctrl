#!/usr/bin/env bash
# tests/fixtures/db-safety/mock-psql.sh — Mock psql CLI for database safety testing.
#
# Intercepts psql invocations during tests to:
#   1. Log the full command line to $MOCK_LOG_DIR/psql.log
#   2. Return canned output for well-known queries (SELECT version(), \dt, etc.)
#   3. Exit 0 for recognized queries, 1 for unrecognized to simulate real behavior
#
# Usage: Place this script on PATH before the real psql when running tests.
#   Setup is handled by setup-test-env.sh which sets MOCK_BIN_DIR on PATH.
#
# @decision DEC-DBSAFE-MOCK-001
# @title Stub database CLIs via PATH injection rather than function overrides
# @status accepted
# @rationale Function overrides (alias/function in bash) do not propagate into
#   subshells or child processes, which is exactly where hook scripts invoke
#   CLIs. PATH injection makes the mock visible to ALL child processes including
#   hooks, subshells, and process substitutions. The mock logs to MOCK_LOG_DIR
#   (set by setup-test-env.sh) so tests can assert on what was called.

set -euo pipefail

# Determine log directory — fall back to /tmp if MOCK_LOG_DIR is unset.
# Tests should always set MOCK_LOG_DIR via setup-test-env.sh.
LOG_DIR="${MOCK_LOG_DIR:-${TMPDIR:-/tmp}/mock-db-logs}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/psql.log"

# Log: timestamp + full command line (argv[0] = "psql", then args)
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) psql $*" >> "$LOG_FILE"

# Parse arguments to identify the query (look for -c "..." patterns)
QUERY=""
ARGS=("$@")
i=0
while [[ $i -lt ${#ARGS[@]} ]]; do
    case "${ARGS[$i]}" in
        -c|--command)
            i=$((i + 1))
            QUERY="${ARGS[$i]:-}"
            ;;
        -f|--file)
            i=$((i + 1))
            # File-based queries: log but return generic success
            echo "MOCK psql: reading from file ${ARGS[$i]:-}" >&2
            ;;
    esac
    i=$((i + 1))
done

# Normalize query for matching (trim leading/trailing whitespace, lowercase)
QUERY_NORM=$(echo "$QUERY" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

# Canned responses for well-known queries
case "$QUERY_NORM" in
    "select version()")
        echo "                                                       version                                                        "
        echo "------------------------------------------------------------------------------------------------------------------------"
        echo " PostgreSQL 15.3 on x86_64-pc-linux-gnu, compiled by gcc (GCC) 11.3.0, 64-bit"
        echo "(1 row)"
        exit 0
        ;;
    "\\dt"|"\dt")
        echo "         List of relations"
        echo " Schema |  Name   | Type  |  Owner   "
        echo "--------+---------+-------+----------"
        echo " public | users   | table | postgres "
        echo " public | orders  | table | postgres "
        echo "(2 rows)"
        exit 0
        ;;
    "select 1"|"select 1;")
        echo " ?column? "
        echo "----------"
        echo "        1"
        echo "(1 row)"
        exit 0
        ;;
    "select count(*) from"*|"select * from"*)
        echo " count "
        echo "-------"
        echo "    42"
        echo "(1 row)"
        exit 0
        ;;
    "show tables"|"\\l"|"\l")
        echo "   Name    |  Owner   "
        echo "-----------+----------"
        echo " myapp     | postgres "
        echo "(1 row)"
        exit 0
        ;;
    *"drop table"*|*"drop database"*|*"truncate"*|*"delete from"*|*"alter table"*"drop column"*)
        # Destructive: return success (mock doesn't actually do it, but exit 0 to test hook blocking)
        echo "mock psql: destructive operation would execute (blocked by hook in production)"
        exit 0
        ;;
    "")
        # No -c argument — likely a connection test or interactive mode
        echo "psql (15.3)"
        echo "Type \"help\" for help."
        exit 0
        ;;
    *)
        # Unknown query: exit 0 with generic message (psql doesn't error on unknown SQL, the server does)
        echo "MOCK psql: unrecognized query: $QUERY_NORM"
        exit 0
        ;;
esac
