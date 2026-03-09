#!/usr/bin/env bash
# tests/fixtures/db-safety/mock-redis-cli.sh — Mock redis-cli for database safety testing.
#
# Intercepts redis-cli invocations during tests to:
#   1. Log the full command line to $MOCK_LOG_DIR/redis-cli.log
#   2. Return canned output for well-known commands (PING, GET, SET, INFO, etc.)
#   3. Exit 0 for recognized commands
#
# Usage: Place this script on PATH before the real redis-cli when running tests.
#   Setup is handled by setup-test-env.sh.
#
# @decision DEC-DBSAFE-MOCK-001 (shared — see mock-psql.sh for rationale)

set -euo pipefail

LOG_DIR="${MOCK_LOG_DIR:-${TMPDIR:-/tmp}/mock-db-logs}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/redis-cli.log"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) redis-cli $*" >> "$LOG_FILE"

# Redis-cli takes the command as positional args after connection flags.
# Normalize: skip -h, -p, -n, -a flags and their values.
CMD_ARGS=()
ARGS=("$@")
i=0
while [[ $i -lt ${#ARGS[@]} ]]; do
    case "${ARGS[$i]}" in
        -h|-p|-n|-a|--pass|--user|--tls|--cacert|--cert|--key)
            i=$((i + 1))  # skip the value too
            ;;
        -*)
            # Other flags (no value) — skip
            ;;
        *)
            CMD_ARGS+=("${ARGS[$i]}")
            ;;
    esac
    i=$((i + 1))
done

# Normalize command to uppercase for matching
CMD_UPPER=$(echo "${CMD_ARGS[*]:-}" | tr '[:lower:]' '[:upper:]' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
CMD_FIRST="${CMD_ARGS[0]:-}"
CMD_FIRST_UPPER=$(echo "$CMD_FIRST" | tr '[:lower:]' '[:upper:]')

case "$CMD_FIRST_UPPER" in
    "PING")
        echo "PONG"
        exit 0
        ;;
    "GET")
        KEY="${CMD_ARGS[1]:-}"
        # Return mock value for any key
        echo "mock-value-for-${KEY}"
        exit 0
        ;;
    "SET")
        echo "OK"
        exit 0
        ;;
    "DEL")
        echo "(integer) 1"
        exit 0
        ;;
    "EXISTS")
        echo "(integer) 1"
        exit 0
        ;;
    "KEYS")
        echo "1) \"session:123\""
        echo "2) \"session:456\""
        echo "3) \"cache:user:1\""
        exit 0
        ;;
    "INFO")
        echo "# Server"
        echo "redis_version:7.0.12"
        echo "redis_mode:standalone"
        echo ""
        echo "# Clients"
        echo "connected_clients:1"
        exit 0
        ;;
    "DBSIZE")
        echo "(integer) 42"
        exit 0
        ;;
    "FLUSHALL"|"FLUSHDB")
        # Destructive — mock returns OK but logs for inspection
        echo "OK"
        exit 0
        ;;
    "CONFIG")
        echo "# mock redis config"
        exit 0
        ;;
    "")
        # No command — interactive mode
        echo "redis-cli 7.0.12"
        echo "Connected to 127.0.0.1:6379"
        exit 0
        ;;
    *)
        echo "(error) MOCK: unrecognized command: ${CMD_ARGS[*]:-}"
        exit 0
        ;;
esac
