#!/usr/bin/env bash
# tests/fixtures/db-safety/mock-mysql.sh — Mock mysql CLI for database safety testing.
#
# Intercepts mysql invocations during tests to:
#   1. Log the full command line to $MOCK_LOG_DIR/mysql.log
#   2. Return canned output for well-known queries (SHOW TABLES, SELECT VERSION(), etc.)
#   3. Exit 0 for recognized queries
#
# Usage: Place this script on PATH before the real mysql when running tests.
#   Setup is handled by setup-test-env.sh.
#
# @decision DEC-DBSAFE-MOCK-001 (shared — see mock-psql.sh for rationale)

set -euo pipefail

LOG_DIR="${MOCK_LOG_DIR:-${TMPDIR:-/tmp}/mock-db-logs}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/mysql.log"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) mysql $*" >> "$LOG_FILE"

# Parse -e "query" or --execute "query"
QUERY=""
ARGS=("$@")
i=0
while [[ $i -lt ${#ARGS[@]} ]]; do
    case "${ARGS[$i]}" in
        -e|--execute)
            i=$((i + 1))
            QUERY="${ARGS[$i]:-}"
            ;;
    esac
    i=$((i + 1))
done

QUERY_NORM=$(echo "$QUERY" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

case "$QUERY_NORM" in
    "show tables"|"show tables;")
        echo "Tables_in_myapp"
        echo "users"
        echo "orders"
        echo "sessions"
        exit 0
        ;;
    "select version()"|"select version();")
        echo "VERSION()"
        echo "8.0.33"
        exit 0
        ;;
    "select 1"|"select 1;")
        echo "1"
        echo "1"
        exit 0
        ;;
    "show databases"|"show databases;")
        echo "Database"
        echo "information_schema"
        echo "myapp"
        echo "performance_schema"
        exit 0
        ;;
    "show status"|"show status;")
        echo "Variable_name\tValue"
        echo "Uptime\t12345"
        exit 0
        ;;
    *"truncate table"*|*"drop table"*|*"drop database"*|*"delete from"*|*"alter table"*"drop column"*)
        echo "mock mysql: destructive operation would execute"
        exit 0
        ;;
    "")
        echo "Welcome to the MySQL monitor."
        echo "mysql  Ver 8.0.33"
        exit 0
        ;;
    *)
        echo "mock mysql: unrecognized query: $QUERY_NORM"
        exit 0
        ;;
esac
