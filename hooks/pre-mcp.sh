#!/usr/bin/env bash
# pre-mcp.sh -- PreToolUse hook for MCP tool governance (Wave 4: Task E, Wave 5: E6)
#
# Intercepts database ops via MCP servers that bypass pre-bash.sh.
# MCP tools use JSON-RPC over stdio; the Bash hook never fires for them.
#
# @decision DEC-MCP-001
# @title PreToolUse hook for MCP database tool governance
# @status accepted
# @rationale MCP tools bypass pre-bash.sh. CVE-2025-53109: COMMIT;DROP SCHEMA
#   bypasses Postgres MCP read-only mode. This hook closes the gap via
#   mcp__.* matcher in settings.json PreToolUse array.
#
# @decision DEC-MCP-002
# @title Early-exit for non-database MCP tools (zero overhead)
# @status accepted
# @rationale Fires on all mcp__* calls. Non-db tools exit after one grep.
#
# @decision DEC-MCP-003
# @title Capability-first: tool suffix determines allowed SQL class
# @status accepted
# @rationale Read-only: always allowed. DDL/DROP TABLE/admin: always denied.
#   Write/unknown: proceeds to SQL content inspection.
#
# @decision DEC-MCP-E6-001
# @title Credential partitioning advisory fires once per session via sentinel file
# @status accepted
# @rationale MCP database servers with write access should use separate read-only
#   and read-write credentials to limit blast radius. A per-session advisory (not
#   per-call) avoids noise — the sentinel file is created on first DB MCP call and
#   prevents repeat emissions. Server names with _read/_readonly suffix already have
#   partitioned credentials and are exempt from the advisory.

set -euo pipefail

_HOOK_COMPLETED=false
_hook_preload_crash() {
    if [[ "$_HOOK_COMPLETED" != "true" ]]; then
        printf '%s\n' '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"SAFETY: pre-mcp.sh crashed. MCP tool denied."}}'
    fi
}
trap '_hook_preload_crash' EXIT

_HOOK_NAME="pre-mcp"
_HOOK_EVENT_TYPE="PreToolUse:mcp"

source "$(dirname "$0")/source-lib.sh"
enable_fail_closed "pre-mcp"

if [[ "${HOOK_GATE_SCAN:-}" == "1" ]]; then
    declare_gate "mcp-db-tool-identify" "Identify database MCP tools; early-exit for non-db" "side-effect"
    declare_gate "mcp-credential-advisory" "Credential partitioning advisory (once per session)" "advisory"
    declare_gate "mcp-capability-filter" "Per-tool capability filtering (read-only/DDL/admin)" "deny"
    declare_gate "mcp-sql-injection" "SQL injection detection (semicolon stacking, CVE-2025-53109)" "deny"
    declare_gate "mcp-sql-risk" "SQL risk classification via _db_classify_risk()" "deny"
    declare_gate "mcp-rate-limit" "Rate limiting advisory (non-blocking)" "advisory"
    _HOOK_COMPLETED=true
    exit 0
    # MCP tools bypass normal approval flow -- any DELETE is denied regardless of WHERE clause.
    # Even WHERE 1=1 is a full-table delete. Require explicit guardian approval for all deletes.
    _DELETE_PAT='^[[:space:]]*DELETE[[:space:]]'
    if printf '%s' "$SQL_UPPER" | grep -qE "$_DELETE_PAT"; then
        _mcp_deny "MCP governance: DELETE statement requires explicit approval. Tool: ${TOOL_NAME}. SQL: ${SQL}" "data_mutation" "$SQL"
    fi
    # MCP tools bypass normal approval flow -- any DELETE is denied regardless of WHERE clause.
    # Even WHERE 1=1 is a full-table delete. Require explicit guardian approval for all deletes.
    _DELETE_PAT='^[[:space:]]*DELETE[[:space:]]'
    if printf '%s' "$SQL_UPPER" | grep -qE "$_DELETE_PAT"; then
        _mcp_deny "MCP governance: DELETE statement requires explicit approval. Tool: ${TOOL_NAME}. SQL: ${SQL}" "data_mutation" "$SQL"
    fi
fi

HOOK_INPUT=$(read_input)
TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)

if [[ -z "$TOOL_NAME" ]]; then
    _HOOK_COMPLETED=true; exit 0
fi

_mcp_is_db_tool() {
    local tn="$1"
    if echo "$tn" | grep -qiE '^mcp__(postgres|postgresql|mysql|mariadb|sqlite|mongodb|mongo|redis)__'; then
        return 0
    fi
    if echo "$tn" | grep -qiE '^mcp__[^_]+__(execute_query|run_query|execute_sql|execute_command|execute_ddl)$'; then
        return 0
    fi
    return 1
}

_mcp_get_capability() {
    local suffix="${1##*__}"
    case "$suffix" in
        list_tables|list_schemas|describe_table|get_schema|read_query|select_query|find|info|status|ping)
            echo "readonly" ;;
        execute_query|run_query|execute_sql|execute_command|insert|update|upsert|custom_operation)
            echo "write" ;;
        create_table|alter_table|execute_ddl|create_index|drop_index)
            echo "ddl" ;;
        drop_table|drop_database|create_database|grant|revoke|drop_schema|drop_column)
            echo "admin" ;;
        *) echo "write" ;;
    esac
}

_mcp_extract_sql() {
    local json="$1" sql=""
    for field in query sql statement command; do
        sql=$(echo "$json" | jq -r --arg f "$field" '.[$f] // empty' 2>/dev/null || true)
        if [[ -n "$sql" && "$sql" != "null" ]]; then
            printf '%s' "$sql"; return 0
        fi
    done
    return 0
}

_mcp_deny() {
    local reason="$1" op_type="${2:-data_mutation}" sql="${3:-}"
    require_db_guardian
    local sig
    sig=$(_dbg_emit_guardian_required "$op_type" "$TOOL_NAME: $sql" "$reason" "unknown")
    # Wave 5 B11: count every MCP deny (require_db_safety loaded above when db tool detected)
    _db_increment_stat "blocked" 2>/dev/null || true
    emit_deny "${reason}${sig}"
}

declare_gate "mcp-db-tool-identify" "Identify database MCP tools; early-exit for non-db" "side-effect"
if ! _mcp_is_db_tool "$TOOL_NAME"; then
    _HOOK_COMPLETED=true; exit 0
fi

# Wave 5 B11: count every DB MCP tool detection
require_db_safety
_db_increment_stat "checked"

TOOL_INPUT_JSON=$(echo "$HOOK_INPUT" | jq -r '.tool_input // {}' 2>/dev/null || echo '{}')
CAPABILITY=$(_mcp_get_capability "$TOOL_NAME")
SQL=$(_mcp_extract_sql "$TOOL_INPUT_JSON")

# Wave 5 E6: credential partitioning advisory (once per session).
# Fires on first DB MCP call when the server has no _read/_readonly suffix,
# suggesting the server may have unrestricted write access. A sentinel file
# prevents repeat emissions so the advisory appears exactly once.
declare_gate "mcp-credential-advisory" "Credential partitioning advisory (once per session)" "advisory"
# @decision DEC-V4-KV-001
# @title Migrate .mcp-credential-advisory-emitted sentinel to SQLite KV
# @status accepted
# @rationale Sentinel file persists past session-end with no cleanup.
#   KV key mcp_credential_advisory="1" is session-scoped (deleted by session-end.sh).
#   Dual-write: KV primary (state_update) + flat-file (touch) for fallback.
#   Read: KV check first, then flat-file check. Either non-empty = already emitted.
require_state
_MCP_CRED_SENTINEL="${CLAUDE_DIR:-$HOME/.claude}/.mcp-credential-advisory-emitted"
_MCP_CRED_KV=$(state_read "mcp_credential_advisory" 2>/dev/null || echo "")
if [[ -z "$_MCP_CRED_KV" && ! -f "$_MCP_CRED_SENTINEL" ]]; then
    # Extract server name from mcp__SERVER_NAME__tool_name format
    _MCP_SERVER_PART="${TOOL_NAME#mcp__}"
    _MCP_SERVER_NAME="${_MCP_SERVER_PART%%__*}"
    # Only emit if server name does NOT already have a read-only suffix
    if ! printf '%s' "$_MCP_SERVER_NAME" | grep -qiE '(_read|_readonly)$'; then
        # Dual-write: KV primary + flat-file fallback
        state_update "mcp_credential_advisory" "1" "pre-mcp" 2>/dev/null || true
        touch "$_MCP_CRED_SENTINEL" 2>/dev/null || true
        emit_advisory "MCP credential advisory: Consider configuring separate read-only and read-write MCP servers for credential isolation (e.g., postgres_read and postgres_write). Server: ${_MCP_SERVER_NAME}"
        _db_increment_stat "warned"
    fi
fi

declare_gate "mcp-capability-filter" "Per-tool capability filtering (read-only/DDL/admin)" "deny"
case "$CAPABILITY" in
    readonly)
        _HOOK_COMPLETED=true; exit 0 ;;
    ddl)
        _mcp_deny "MCP governance: DDL tool ${TOOL_NAME} requires explicit approval (DROP TABLE/DATABASE/index changes are irreversible)." "schema_alter" "$SQL" ;;
    admin)
        _mcp_deny "MCP governance: Admin tool ${TOOL_NAME} denied. DROP DATABASE/grant/revoke must not execute via MCP server." "data_mutation" "$SQL" ;;
    *) ;;
esac

declare_gate "mcp-sql-injection" "SQL injection detection (semicolon stacking, CVE-2025-53109)" "deny"
if [[ -n "$SQL" ]]; then
    SQL_UPPER=$(printf '%s' "$SQL" | tr '[:lower:]' '[:upper:]')
    _CVE_PAT='COMMIT[[:space:]]*;[[:space:]]*(DROP[[:space:]]+(SCHEMA|DATABASE|TABLE)|TRUNCATE[[:space:]]+TABLE)'
    if printf '%s' "$SQL_UPPER" | grep -qiE "$_CVE_PAT"; then
        _mcp_deny "MCP SQL injection (CVE-2025-53109): COMMIT;DROP SCHEMA detected. SQL: ${SQL}" "schema_alter" "$SQL"
    fi
    _INJ_PAT=';[[:space:]]*(DROP|TRUNCATE[[:space:]]+TABLE)'
    if printf '%s' "$SQL_UPPER" | grep -qiE "$_INJ_PAT"; then
        _mcp_deny "MCP SQL injection: semicolon-stacked destructive SQL. Tool: ${TOOL_NAME}. SQL: ${SQL}" "data_mutation" "$SQL"
    fi
    # MCP tools bypass normal approval flow -- any DELETE is denied regardless of WHERE clause.
    # Even WHERE 1=1 is a full-table delete. Require explicit guardian approval.
    _DELETE_PAT='^[[:space:]]*DELETE[[:space:]]'
    if printf '%s' "$SQL_UPPER" | grep -qE "$_DELETE_PAT"; then
        _mcp_deny "MCP governance: DELETE statement requires explicit approval. Tool: ${TOOL_NAME}. SQL: ${SQL}" "data_mutation" "$SQL"
    fi
fi

declare_gate "mcp-sql-risk" "SQL risk classification via _db_classify_risk()" "deny"
if [[ -n "$SQL" ]]; then
    require_db_safety
    RISK_RESULT=$(_db_classify_risk "$SQL" "psql")
    RISK_LEVEL="${RISK_RESULT%%:*}"
    RISK_REASON="${RISK_RESULT#*:}"
    case "$RISK_LEVEL" in
        deny)
            _mcp_deny "MCP governance: ${RISK_REASON}. Tool: ${TOOL_NAME}" "data_mutation" "$SQL" ;;
        advisory)
            _db_increment_stat "warned" 2>/dev/null || true
            emit_advisory "MCP advisory: ${RISK_REASON}. Tool: ${TOOL_NAME}" ;;
        *) ;;
    esac
fi

declare_gate "mcp-rate-limit" "Rate limiting advisory (non-blocking)" "advisory"
# @decision DEC-V4-KV-001
# @title Migrate .mcp-rate-state to SQLite KV (mcp_rate_count, mcp_rate_start)
# @status accepted
# @rationale .mcp-rate-state is a session-scoped rate limiter (count|timestamp).
#   Flat-file has no session-end cleanup — it lingers across sessions.
#   KV keys mcp_rate_count and mcp_rate_start are deleted by session-end.sh.
#   Dual-write: KV primary (state_update) + flat-file for backward compat.
#   Read: KV first, flat-file fallback. require_state already called above.
_RATE_STATE="${CLAUDE_DIR:-$HOME/.claude}/.mcp-rate-state"
_RATE_LIMIT=100; _RATE_WINDOW=60; _NOW=$(date +%s)
_RATE_COUNT=0; _RATE_START=0
# KV primary read (DEC-V4-KV-001)
_RATE_KV_COUNT=$(state_read "mcp_rate_count" 2>/dev/null || echo "")
_RATE_KV_START=$(state_read "mcp_rate_start" 2>/dev/null || echo "")
if [[ "$_RATE_KV_COUNT" =~ ^[0-9]+$ && "$_RATE_KV_START" =~ ^[0-9]+$ ]]; then
    _RATE_COUNT="$_RATE_KV_COUNT"; _RATE_START="$_RATE_KV_START"
elif [[ -f "$_RATE_STATE" ]]; then
    # Flat-file fallback
    _RATE_DATA=$(cat "$_RATE_STATE" 2>/dev/null || echo '0|0')
    _RATE_COUNT="${_RATE_DATA%%|*}"; _RATE_START="${_RATE_DATA##*|}"
fi
if [[ $(( _NOW - _RATE_START )) -ge $_RATE_WINDOW ]]; then
    _RATE_COUNT=0; _RATE_START=$_NOW
fi
_RATE_COUNT=$(( _RATE_COUNT + 1 ))
# Dual-write: KV primary + flat-file fallback
state_update "mcp_rate_count" "$_RATE_COUNT" "pre-mcp" 2>/dev/null || true
state_update "mcp_rate_start" "$_RATE_START" "pre-mcp" 2>/dev/null || true
printf '%s|%s\n' "$_RATE_COUNT" "$_RATE_START" > "$_RATE_STATE" 2>/dev/null || true
if [[ "$_RATE_COUNT" -gt "$_RATE_LIMIT" ]]; then
    emit_advisory "MCP rate limit: ${_RATE_COUNT} DB calls in ${_RATE_WINDOW}s (limit: ${_RATE_LIMIT}). Tool: ${TOOL_NAME}"
fi

emit_flush
