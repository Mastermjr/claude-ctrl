#!/usr/bin/env bash
# tests/fixtures/db-safety/mock-mongosh.sh — Mock mongosh CLI for database safety testing.
#
# Intercepts mongosh invocations during tests to:
#   1. Log the full command line to $MOCK_LOG_DIR/mongosh.log
#   2. Return canned output for well-known --eval expressions
#   3. Exit 0 for recognized operations
#
# Usage: Place this script on PATH before the real mongosh when running tests.
#   Setup is handled by setup-test-env.sh.
#
# @decision DEC-DBSAFE-MOCK-001 (shared — see mock-psql.sh for rationale)

set -euo pipefail

LOG_DIR="${MOCK_LOG_DIR:-${TMPDIR:-/tmp}/mock-db-logs}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/mongosh.log"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) mongosh $*" >> "$LOG_FILE"

# Parse --eval "expression"
EVAL_EXPR=""
ARGS=("$@")
i=0
while [[ $i -lt ${#ARGS[@]} ]]; do
    case "${ARGS[$i]}" in
        --eval)
            i=$((i + 1))
            EVAL_EXPR="${ARGS[$i]:-}"
            ;;
    esac
    i=$((i + 1))
done

EVAL_NORM=$(echo "$EVAL_EXPR" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]//g')

case "$EVAL_NORM" in
    "db.version()"|"db.version();")
        echo "7.0.2"
        exit 0
        ;;
    "db.runcommand({ping:1})"|"db.runcommand({'ping':1})")
        echo '{ ok: 1 }'
        exit 0
        ;;
    "db.users.find({})"*|"db.users.find({}).limit"*)
        echo '[ { _id: ObjectId("..."), name: "Alice", email: "alice@example.com" } ]'
        exit 0
        ;;
    "db.getCollectionNames()"|"show collections")
        echo "[ 'users', 'orders', 'sessions' ]"
        exit 0
        ;;
    "db.stats()"|"db.stats();")
        echo '{ db: "myapp", collections: 3, objects: 150, avgObjSize: 128, dataSize: 19200, ok: 1 }'
        exit 0
        ;;
    *"db.users.drop()"*|*"db.dropdatabase()"*|*"db.collection.drop()"*|*".drop()")
        echo "mock mongosh: destructive drop operation would execute"
        exit 0
        ;;
    "")
        echo "Current Mongosh Log ID: 64a1b2c3d4e5f6g7h8i9j0k1"
        echo "Connecting to:          mongodb://127.0.0.1:27017/?directConnection=true"
        echo "Using MongoDB:          7.0.2"
        echo "Using Mongosh:          2.0.2"
        exit 0
        ;;
    *)
        echo "mock mongosh: unrecognized eval: $EVAL_NORM"
        exit 0
        ;;
esac
