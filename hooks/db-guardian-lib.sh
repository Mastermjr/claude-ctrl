#!/usr/bin/env bash
# db-guardian-lib.sh — Database Guardian agent library: JSON handoff protocol (D1/D2),
#                      deterministic policy engine (D3), simulation helpers (D4),
#                      and approval gate (D5)
#
# This is the unified library for the DB Guardian agent. It combines:
#   Wave 3a (D1/D2): JSON handoff protocol — request/response serialization for
#     the DB-GUARDIAN-REQUIRED handoff flow between pre-bash.sh and the agent.
#   Wave 3b (D3/D4/D5): Policy engine, simulation helpers, approval gate —
#     deterministic rule evaluation, CLI-specific simulation command builders,
#     and approval token management via state store.
#
# Architecture:
#   pre-bash.sh (deny) → emit DB-GUARDIAN-REQUIRED JSON → orchestrator →
#   _dbg_format_request() → Database Guardian agent → _dbg_evaluate_policy() →
#   _dbg_simulate_*() → _dbg_request_approval() → _dbg_format_response()
#
# This library has no external dependencies beyond bash builtins and jq.
# It is loaded lazily via require_db_guardian() in source-lib.sh.
# state-lib.sh must be loaded separately if D5 approval functions are needed.
#
# Request schema (JSON):
#   operation_type       — schema_alter|query|data_mutation|migration
#   description          — human-readable explanation of intent
#   query                — SQL statement to execute
#   target_database      — database name or connection identifier
#   target_environment   — production|staging|development|local
#   context_snapshot     — affected_tables[], estimated_row_count, cascade_risk
#   requires_approval    — bool: whether user approval is required before execution
#   reversibility_info   — reversible, rollback_method, recovery_checkpoint
#
# Response schema (JSON):
#   status               — executed|denied|approval_required
#   execution_id         — unique identifier for this operation
#   result               — rows_affected, data[]
#   policy_decision      — rule_matched, action, reason
#   simulation_result    — explain_output, estimated_impact, cascade_effects[]
#
# @decision DEC-DBGUARD-001
# @title Separate db-guardian-lib.sh from db-safety-lib.sh for agent-layer concerns
# @status accepted
# @rationale db-safety-lib.sh handles pre-bash.sh hook concerns (CLI detection,
#   environment classification, risk scoring for the deterministic gate). The DB
#   Guardian agent needs a higher-level policy engine, simulation command builders,
#   and an approval gate that integrate with the state store. Mixing these in
#   db-safety-lib.sh would couple the lightweight hook layer to the agent layer
#   (approval state, simulation, structured JSON output). Keeping them separate:
#   (1) preserves zero-overhead loading for the hook path (db-safety-lib.sh never
#       imports state-lib.sh), (2) makes the agent's decision logic independently
#       testable, (3) follows the separation established by DEC-DBSAFE-001.
#
# @decision DEC-DBGUARD-002
# @title db-guardian-lib.sh as pure bash JSON marshalling layer
# @status accepted
# @rationale The Database Guardian agent needs a machine-readable handoff format
#   that pre-bash.sh can emit inline (in the deny message) without spawning a
#   subprocess. Using jq for generation would add a subprocess call to every
#   denied database command — significant overhead in the hot path. Instead,
#   this library provides bash functions that produce JSON via printf/heredoc
#   with minimal escaping. The consumer (the agent) uses jq to parse the JSON,
#   which is acceptable since agents run outside the hook hot path.
#   The separation of formatting (lib) from agent logic (db-guardian.md) makes
#   the schema testable in isolation without an agent session.
#
# @decision DEC-DBGUARD-003
# @title Pipe-delimited return format for _dbg_parse_response()
# @status accepted
# @rationale Bash functions cannot return structured data — they can only print
#   to stdout. The caller needs multiple fields (status, rule_matched, reason,
#   rows_affected). Options: (1) global variables (set side effects, breaks
#   subshells), (2) JSON stdout + jq parse at call site (adds jq subprocess),
#   (3) delimited string (no subprocess, no side effects). We chose (3):
#   "status|rule_matched|reason|rows_affected". The caller uses IFS='|' read
#   to split. Documented in the function header so callers know the format.
#
# @decision DEC-DBGUARD-004
# @title Deterministic policy engine: rules evaluated in priority order, no LLM
# @status accepted
# @rationale The policy engine must be auditable, deterministic, and fast. LLM
#   reasoning is not appropriate for safety-critical allow/deny decisions — it can
#   hallucinate, be slow, or fail. Instead, rules are evaluated in a fixed priority
#   order with explicit IDs and structured output. The DB Guardian agent uses the
#   engine output as input to its reasoning, but the deny/escalate decisions are
#   final and cannot be overridden by the agent without explicit user approval.
#   Each rule returns "allow|deny|escalate:<rule_id>:<reason>" for auditability.

# Guard: prevent re-sourcing
[[ -n "${_DB_GUARDIAN_LIB_LOADED:-}" ]] && return 0
_DB_GUARDIAN_LIB_LOADED=1
_DB_GUARDIAN_LIB_VERSION=1

# =============================================================================
# D1/D2: JSON Handoff Protocol (Wave 3a)
#
# Functions for request/response serialization between pre-bash.sh and the
# Database Guardian agent. These handle schema validation, JSON formatting,
# response parsing, and signal emission.
# =============================================================================

# Valid values for schema enforcement
_DBG_VALID_OP_TYPES="schema_alter query data_mutation migration"
_DBG_VALID_ENVIRONMENTS="production staging development local"
_DBG_VALID_STATUSES="executed denied approval_required"
_DBG_VALID_ACTIONS="deny allow escalate"
_DBG_VALID_ROLLBACK_METHODS="transaction rollback|backup restore|none"

# ---------------------------------------------------------------------------
# _dbg_validate_request JSON_STRING
#
# Validates a Database Guardian request JSON against the required schema.
# Checks: all required fields present, operation_type valid, target_environment
# valid, query non-empty, reversibility_info complete.
#
# Returns: "valid" on success, "invalid:<reason>" on failure.
# Exit code: 0 on valid, 1 on invalid.
#
# Usage:
#   result=$(_dbg_validate_request "$request_json")
#   if [[ "$result" != "valid" ]]; then
#     echo "Validation failed: ${result#invalid:}"
#   fi
# ---------------------------------------------------------------------------
_dbg_validate_request() {
    local json_string="$1"

    # Empty input check
    if [[ -z "$json_string" ]]; then
        echo "invalid:empty request"
        return 1
    fi

    # Verify jq is available for JSON parsing
    if ! command -v jq >/dev/null 2>&1; then
        # Fallback: basic string checks when jq is unavailable
        if ! echo "$json_string" | grep -q '"operation_type"'; then
            echo "invalid:missing required field: operation_type"
            return 1
        fi
        if ! echo "$json_string" | grep -q '"query"'; then
            echo "invalid:missing required field: query"
            return 1
        fi
        if ! echo "$json_string" | grep -q '"target_environment"'; then
            echo "invalid:missing required field: target_environment"
            return 1
        fi
        echo "valid"
        return 0
    fi

    # Validate JSON is parseable
    if ! echo "$json_string" | jq empty 2>/dev/null; then
        echo "invalid:malformed JSON"
        return 1
    fi

    # Required field: operation_type
    local op_type
    op_type=$(echo "$json_string" | jq -r '.operation_type // empty' 2>/dev/null)
    if [[ -z "$op_type" ]]; then
        echo "invalid:missing required field: operation_type"
        return 1
    fi
    # Validate operation_type value
    local valid_op=false
    for _valid in $_DBG_VALID_OP_TYPES; do
        [[ "$op_type" == "$_valid" ]] && valid_op=true && break
    done
    if [[ "$valid_op" == "false" ]]; then
        echo "invalid:unknown operation_type '$op_type'; must be one of: $_DBG_VALID_OP_TYPES"
        return 1
    fi

    # Required field: query
    local query
    query=$(echo "$json_string" | jq -r '.query // empty' 2>/dev/null)
    if [[ -z "$query" ]]; then
        echo "invalid:missing required field: query (cannot be empty)"
        return 1
    fi

    # Required field: target_environment
    local target_env
    target_env=$(echo "$json_string" | jq -r '.target_environment // empty' 2>/dev/null)
    if [[ -z "$target_env" ]]; then
        echo "invalid:missing required field: target_environment"
        return 1
    fi
    # Validate target_environment value
    local valid_env=false
    for _valid in $_DBG_VALID_ENVIRONMENTS; do
        [[ "$target_env" == "$_valid" ]] && valid_env=true && break
    done
    if [[ "$valid_env" == "false" ]]; then
        echo "invalid:unknown target_environment '$target_env'; must be one of: $_DBG_VALID_ENVIRONMENTS"
        return 1
    fi

    # Required field: description
    local description
    description=$(echo "$json_string" | jq -r '.description // empty' 2>/dev/null)
    if [[ -z "$description" ]]; then
        echo "invalid:missing required field: description"
        return 1
    fi

    # Required field: target_database
    local target_db
    target_db=$(echo "$json_string" | jq -r '.target_database // empty' 2>/dev/null)
    if [[ -z "$target_db" ]]; then
        echo "invalid:missing required field: target_database"
        return 1
    fi

    # Required field: reversibility_info
    local rev_info
    rev_info=$(echo "$json_string" | jq -r '.reversibility_info // empty' 2>/dev/null)
    if [[ -z "$rev_info" ]]; then
        echo "invalid:missing required field: reversibility_info"
        return 1
    fi
    # reversibility_info must have reversible field (use has() since false is a valid value)
    local reversible_exists
    reversible_exists=$(echo "$json_string" | jq -r 'if .reversibility_info | has("reversible") then "yes" else "no" end' 2>/dev/null || echo "no")
    if [[ "$reversible_exists" != "yes" ]]; then
        echo "invalid:reversibility_info missing required field: reversible"
        return 1
    fi
    # reversibility_info must have rollback_method field
    local rollback_method
    rollback_method=$(echo "$json_string" | jq -r '.reversibility_info.rollback_method // empty' 2>/dev/null)
    if [[ -z "$rollback_method" ]]; then
        echo "invalid:reversibility_info missing required field: rollback_method"
        return 1
    fi

    echo "valid"
    return 0
}

# ---------------------------------------------------------------------------
# _dbg_format_request OPERATION_TYPE DESCRIPTION QUERY TARGET_DB TARGET_ENV
#                     [AFFECTED_TABLES] [EST_ROW_COUNT] [CASCADE_RISK]
#                     [REQUIRES_APPROVAL] [REVERSIBLE] [ROLLBACK_METHOD]
#                     [RECOVERY_CHECKPOINT]
#
# Constructs a properly formatted Database Guardian request JSON.
# All required fields must be provided. Optional context_snapshot and
# reversibility_info fields use safe defaults when omitted.
#
# Positional arguments:
#   $1  operation_type       — schema_alter|query|data_mutation|migration
#   $2  description          — human-readable intent
#   $3  query                — SQL statement
#   $4  target_database      — database name
#   $5  target_environment   — production|staging|development|local
#   $6  affected_tables      — comma-separated table names (default: "")
#   $7  estimated_row_count  — integer (default: 0)
#   $8  cascade_risk         — true|false (default: false)
#   $9  requires_approval    — true|false (default: true for production, false otherwise)
#   $10 reversible           — true|false (default: false)
#   $11 rollback_method      — transaction rollback|backup restore|none (default: none)
#   $12 recovery_checkpoint  — snapshot ID or timestamp (default: "")
#
# Returns: JSON string on stdout
# ---------------------------------------------------------------------------
_dbg_format_request() {
    local op_type="${1:-}"
    local description="${2:-}"
    local query="${3:-}"
    local target_db="${4:-}"
    local target_env="${5:-}"
    local affected_tables="${6:-}"
    local est_row_count="${7:-0}"
    local cascade_risk="${8:-false}"
    local requires_approval="${9:-true}"
    local reversible="${10:-false}"
    local rollback_method="${11:-none}"
    local recovery_checkpoint="${12:-}"

    # Normalize cascade_risk to valid JSON boolean
    case "$cascade_risk" in
        true|1|yes)  cascade_risk="true"  ;;
        false|0|no|"") cascade_risk="false" ;;
        *)           cascade_risk="false" ;;
    esac

    # Normalize reversible to valid JSON boolean
    case "$reversible" in
        true|1|yes)  reversible="true"  ;;
        false|0|no|"") reversible="false" ;;
        *)           reversible="false" ;;
    esac

    # Normalize requires_approval to valid JSON boolean
    case "$requires_approval" in
        true|1|yes)  requires_approval="true"  ;;
        false|0|no)  requires_approval="false" ;;
        *)           requires_approval="true"  ;;
    esac

    # Normalize est_row_count to integer
    if ! [[ "$est_row_count" =~ ^[0-9]+$ ]]; then
        est_row_count=0
    fi

    # Build affected_tables JSON array
    local tables_json="[]"
    if [[ -n "$affected_tables" ]]; then
        # Convert comma-separated string to JSON array using jq or manual construction
        if command -v jq >/dev/null 2>&1; then
            tables_json=$(echo "$affected_tables" | tr ',' '\n' | jq -R . | jq -s . 2>/dev/null || echo "[]")
        else
            # Manual construction for environments without jq
            tables_json="["
            local first=true
            while IFS= read -r -d',' table; do
                table="${table## }"
                table="${table%% }"
                [[ -z "$table" ]] && continue
                [[ "$first" == "false" ]] && tables_json+=","
                tables_json+="\"${table}\""
                first=false
            done <<< "${affected_tables},"
            tables_json+="]"
        fi
    fi

    # Escape string fields for safe JSON embedding
    local _escape_json
    _escape_json() {
        # Escape backslash, double-quote, newline, tab, carriage return
        printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | tr -d '\r' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//'
    }

    local esc_description esc_query esc_target_db esc_recovery
    if command -v jq >/dev/null 2>&1; then
        esc_description=$(jq -Rr '.' <<< "$description" 2>/dev/null || printf '%s' "$description")
        esc_query=$(jq -Rr '.' <<< "$query" 2>/dev/null || printf '%s' "$query")
        esc_target_db=$(jq -Rr '.' <<< "$target_db" 2>/dev/null || printf '%s' "$target_db")
        esc_recovery=$(jq -Rr '.' <<< "$recovery_checkpoint" 2>/dev/null || printf '%s' "$recovery_checkpoint")
    else
        esc_description=$(_escape_json "$description")
        esc_query=$(_escape_json "$query")
        esc_target_db=$(_escape_json "$target_db")
        esc_recovery=$(_escape_json "$recovery_checkpoint")
    fi

    printf '{
  "operation_type": "%s",
  "description": "%s",
  "query": "%s",
  "target_database": "%s",
  "target_environment": "%s",
  "context_snapshot": {
    "affected_tables": %s,
    "estimated_row_count": %s,
    "cascade_risk": %s
  },
  "requires_approval": %s,
  "reversibility_info": {
    "reversible": %s,
    "rollback_method": "%s",
    "recovery_checkpoint": "%s"
  }
}' \
        "$op_type" \
        "$esc_description" \
        "$esc_query" \
        "$esc_target_db" \
        "$target_env" \
        "$tables_json" \
        "$est_row_count" \
        "$cascade_risk" \
        "$requires_approval" \
        "$reversible" \
        "$rollback_method" \
        "$esc_recovery"
}

# ---------------------------------------------------------------------------
# _dbg_parse_response JSON_STRING
#
# Extracts key fields from a Database Guardian response JSON.
# Returns a pipe-delimited string for easy bash consumption.
#
# Returns: "status|rule_matched|reason|rows_affected"
#   - status       — executed|denied|approval_required (empty if missing)
#   - rule_matched — policy rule ID (empty if missing)
#   - reason       — policy decision reason (empty if missing)
#   - rows_affected — integer (0 if missing or non-integer)
#
# Usage:
#   IFS='|' read -r status rule reason rows <<< "$(_dbg_parse_response "$response_json")"
#
# Exit code: 0 on success, 1 if JSON is malformed or empty
# ---------------------------------------------------------------------------
_dbg_parse_response() {
    local json_string="$1"

    if [[ -z "$json_string" ]]; then
        echo "|||0"
        return 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        # Fallback: regex extraction when jq unavailable
        local status rule reason rows_affected
        status=$(echo "$json_string" | grep -oE '"status"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -oE '"[^"]*"$' | tr -d '"' || echo "")
        rule=$(echo "$json_string" | grep -oE '"rule_matched"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -oE '"[^"]*"$' | tr -d '"' || echo "")
        reason=$(echo "$json_string" | grep -oE '"reason"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -oE '"[^"]*"$' | tr -d '"' || echo "")
        rows_affected=$(echo "$json_string" | grep -oE '"rows_affected"[[:space:]]*:[[:space:]]*[0-9]+' | grep -oE '[0-9]+$' || echo "0")
        printf '%s|%s|%s|%s\n' "$status" "$rule" "$reason" "$rows_affected"
        return 0
    fi

    # Validate JSON is parseable
    if ! echo "$json_string" | jq empty 2>/dev/null; then
        echo "|||0"
        return 1
    fi

    local status rule_matched reason rows_affected

    status=$(echo "$json_string" | jq -r '.status // empty' 2>/dev/null || echo "")
    rule_matched=$(echo "$json_string" | jq -r '.policy_decision.rule_matched // empty' 2>/dev/null || echo "")
    reason=$(echo "$json_string" | jq -r '.policy_decision.reason // empty' 2>/dev/null || echo "")
    rows_affected=$(echo "$json_string" | jq -r '.result.rows_affected // 0' 2>/dev/null || echo "0")

    # Ensure rows_affected is a valid integer
    if ! [[ "$rows_affected" =~ ^[0-9]+$ ]]; then
        rows_affected=0
    fi

    printf '%s|%s|%s|%s\n' "$status" "$rule_matched" "$reason" "$rows_affected"
    return 0
}

# ---------------------------------------------------------------------------
# _dbg_format_response STATUS EXECUTION_ID RULE_MATCHED ACTION REASON
#                       [ROWS_AFFECTED] [EXPLAIN_OUTPUT] [ESTIMATED_IMPACT]
#
# Constructs a properly formatted Database Guardian response JSON.
#
# Positional arguments:
#   $1  status           — executed|denied|approval_required
#   $2  execution_id     — unique identifier for this operation
#   $3  rule_matched     — policy rule ID that was applied
#   $4  action           — deny|allow|escalate
#   $5  reason           — human-readable explanation of the decision
#   $6  rows_affected    — integer (default: 0)
#   $7  explain_output   — raw EXPLAIN output (default: "")
#   $8  estimated_impact — human-readable impact estimate (default: "")
#
# Returns: JSON string on stdout
# ---------------------------------------------------------------------------
_dbg_format_response() {
    local status="${1:-denied}"
    local execution_id="${2:-}"
    local rule_matched="${3:-}"
    local action="${4:-deny}"
    local reason="${5:-}"
    local rows_affected="${6:-0}"
    local explain_output="${7:-}"
    local estimated_impact="${8:-}"

    # Normalize rows_affected to integer
    if ! [[ "$rows_affected" =~ ^[0-9]+$ ]]; then
        rows_affected=0
    fi

    # Generate execution_id if not provided
    if [[ -z "$execution_id" ]]; then
        execution_id="dbg-$(date +%s)-$$"
    fi

    # Escape string fields
    local esc_rule esc_reason esc_explain esc_impact
    if command -v jq >/dev/null 2>&1; then
        esc_rule=$(jq -Rr '.' <<< "$rule_matched" 2>/dev/null || printf '%s' "$rule_matched")
        esc_reason=$(jq -Rr '.' <<< "$reason" 2>/dev/null || printf '%s' "$reason")
        esc_explain=$(jq -Rr '.' <<< "$explain_output" 2>/dev/null || printf '%s' "$explain_output")
        esc_impact=$(jq -Rr '.' <<< "$estimated_impact" 2>/dev/null || printf '%s' "$estimated_impact")
    else
        esc_rule="$rule_matched"
        esc_reason="$reason"
        esc_explain="$explain_output"
        esc_impact="$estimated_impact"
    fi

    printf '{
  "status": "%s",
  "execution_id": "%s",
  "result": {
    "rows_affected": %s,
    "data": []
  },
  "policy_decision": {
    "rule_matched": "%s",
    "action": "%s",
    "reason": "%s"
  },
  "simulation_result": {
    "explain_output": "%s",
    "estimated_impact": "%s",
    "cascade_effects": []
  }
}' \
        "$status" \
        "$execution_id" \
        "$rows_affected" \
        "$esc_rule" \
        "$action" \
        "$esc_reason" \
        "$esc_explain" \
        "$esc_impact"
}

# ---------------------------------------------------------------------------
# _dbg_emit_guardian_required OPERATION_TYPE DENIED_COMMAND DENY_REASON TARGET_ENV
#
# Emits a DB-GUARDIAN-REQUIRED signal for inclusion in pre-bash.sh deny messages.
# This is the machine-readable trigger that causes the orchestrator to dispatch
# the Database Guardian agent.
#
# The caller (pre-bash.sh) appends this to the human-readable deny message so that
# the orchestrator can parse the JSON and construct a full request.
#
# Returns: formatted signal string on stdout
# ---------------------------------------------------------------------------
_dbg_emit_guardian_required() {
    local op_type="${1:-data_mutation}"
    local denied_cmd="${2:-}"
    local deny_reason="${3:-}"
    local target_env="${4:-unknown}"

    # Truncate long commands for the signal (full command is in the deny context)
    local cmd_preview
    if [[ ${#denied_cmd} -gt 200 ]]; then
        cmd_preview="${denied_cmd:0:200}..."
    else
        cmd_preview="$denied_cmd"
    fi

    # Escape for JSON
    local esc_cmd esc_reason
    if command -v jq >/dev/null 2>&1; then
        esc_cmd=$(jq -Rr '.' <<< "$cmd_preview" 2>/dev/null || printf '%s' "$cmd_preview")
        esc_reason=$(jq -Rr '.' <<< "$deny_reason" 2>/dev/null || printf '%s' "$deny_reason")
    else
        esc_cmd=$(printf '%s' "$cmd_preview" | sed 's/"/\\"/g')
        esc_reason=$(printf '%s' "$deny_reason" | sed 's/"/\\"/g')
    fi

    printf '\nDB-GUARDIAN-REQUIRED: {"operation_type":"%s","denied_command":"%s","deny_reason":"%s","target_environment":"%s"}' \
        "$op_type" \
        "$esc_cmd" \
        "$esc_reason" \
        "$target_env"
}

# =============================================================================
# D3: Deterministic Policy Engine (Wave 3b)
#
# Functions for operation classification, risk detection, and policy evaluation.
# The policy engine evaluates rules in priority order and returns deterministic
# allow/deny/escalate decisions with rule IDs for auditability.
# =============================================================================

# ---------------------------------------------------------------------------
# _dbg_classify_operation QUERY
#
# Classifies a SQL/NoSQL query into one of four operation categories:
#   read      — SELECT, SHOW, DESCRIBE, EXPLAIN (no data modification)
#   write_dml — INSERT, UPDATE, DELETE, MERGE, UPSERT (data modification)
#   write_ddl — CREATE, DROP, ALTER, TRUNCATE, RENAME (schema modification)
#   admin     — GRANT, REVOKE, CREATE USER, DROP USER (privilege/admin ops)
#
# Classification is case-insensitive and matches on the first keyword.
# TRUNCATE is classified as write_ddl because it is DDL in most databases
# (auto-commits, schema-level operation) even though it modifies data.
#
# Returns: "read|write_dml|write_ddl|admin"
# ---------------------------------------------------------------------------
_dbg_classify_operation() {
    local query="$1"

    # Normalize: trim leading whitespace and extract first keyword
    local first_keyword
    first_keyword=$(printf '%s' "$query" | sed 's/^[[:space:]]*//' | awk '{print toupper($1)}')

    case "$first_keyword" in
        SELECT|SHOW|DESCRIBE|DESC|EXPLAIN|WITH|CALL|EXEC|EXECUTE)
            printf 'read'
            ;;
        INSERT|UPDATE|DELETE|MERGE|UPSERT|REPLACE)
            printf 'write_dml'
            ;;
        CREATE|DROP|ALTER|TRUNCATE|RENAME|COMMENT|INDEX|REINDEX)
            printf 'write_ddl'
            ;;
        GRANT|REVOKE|DENY|CREATE\ USER|DROP\ USER|ALTER\ USER|CREATE\ ROLE|DROP\ ROLE)
            printf 'admin'
            ;;
        *)
            # Check multi-word DDL patterns not caught by first keyword
            local upper_query
            upper_query=$(printf '%s' "$query" | tr '[:lower:]' '[:upper:]')
            if printf '%s' "$upper_query" | grep -qE '^[[:space:]]*(CREATE|DROP|ALTER)[[:space:]]+'; then
                printf 'write_ddl'
            elif printf '%s' "$upper_query" | grep -qE '^[[:space:]]*(GRANT|REVOKE)[[:space:]]+'; then
                printf 'admin'
            else
                # Unknown — treat conservatively as write_dml
                printf 'write_dml'
            fi
            ;;
    esac
    return 0
}

# ---------------------------------------------------------------------------
# _dbg_detect_cascade_risk QUERY
#
# Heuristically checks whether a query involves foreign key cascades or
# explicit CASCADE clauses that could propagate destruction beyond the
# immediate target table.
#
# Detection patterns:
#   - Explicit CASCADE keyword (DROP TABLE x CASCADE, DELETE ... CASCADE)
#   - ON DELETE CASCADE or ON UPDATE CASCADE in ALTER statements
#   - FOREIGN KEY / REFERENCES mentions (structural cascade relationships)
#   - JOIN in DELETE statements (multi-table delete with relationships)
#
# Returns: "true" or "false"
#
# @decision DEC-DBGUARD-005
# @title Heuristic cascade detection using keyword patterns, not schema introspection
# @status accepted
# @rationale True cascade risk detection requires schema introspection (querying
#   information_schema or pg_constraint). This is not possible at policy evaluation
#   time without a database connection. Instead, we use conservative keyword
#   heuristics: if the query text contains cascade-related keywords, we flag it.
#   False positives (flagging a query that mentions CASCADE in a comment) are
#   acceptable — the cost is an escalation that a human resolves. False negatives
#   (missing a cascade) are unacceptable. Conservative heuristics serve the
#   safety goal even at the cost of occasional over-escalation.
# ---------------------------------------------------------------------------
_dbg_detect_cascade_risk() {
    local query="$1"

    # Check for cascade-related patterns (case insensitive)
    local upper_query
    upper_query=$(printf '%s' "$query" | tr '[:lower:]' '[:upper:]')

    # Explicit CASCADE keyword
    if printf '%s' "$upper_query" | grep -qE '\bCASCADE\b'; then
        printf 'true'
        return 0
    fi

    # FOREIGN KEY or REFERENCES (structural cascade relationships)
    if printf '%s' "$upper_query" | grep -qE '\b(FOREIGN[[:space:]]+KEY|REFERENCES)\b'; then
        printf 'true'
        return 0
    fi

    # ON DELETE / ON UPDATE cascade pattern in DDL
    if printf '%s' "$upper_query" | grep -qE '\bON[[:space:]]+(DELETE|UPDATE)\b'; then
        printf 'true'
        return 0
    fi

    printf 'false'
    return 0
}

# ---------------------------------------------------------------------------
# _dbg_detect_unbounded QUERY
#
# Checks for DELETE or UPDATE statements that lack a WHERE clause.
# An unbounded DELETE/UPDATE affects every row in the table — one of the
# most common causes of catastrophic data loss.
#
# Detection strategy:
#   1. Must be a DELETE or UPDATE statement
#   2. Must NOT contain a WHERE, LIMIT, or subquery that bounds the scope
#
# Returns: "true" (unbounded) or "false" (bounded or not a DML write)
#
# @decision DEC-DBGUARD-006
# @title Detect unbounded DML via absence-of-WHERE pattern, not SQL parsing
# @status accepted
# @rationale Full SQL parsing to detect the absence of a WHERE clause would
#   require a proper parser. Instead, we normalize the query to uppercase and
#   check: (1) the query starts with DELETE or UPDATE, (2) no WHERE keyword
#   appears after the table reference. This works for all common patterns.
#   Edge cases (CTEs, subqueries) are handled by checking for SELECT inside
#   the query — if a subquery is present, it likely provides bounded scope.
#   The heuristic errs toward false positives (safe) over false negatives.
# ---------------------------------------------------------------------------
_dbg_detect_unbounded() {
    local query="$1"

    local upper_query
    upper_query=$(printf '%s' "$query" | tr '[:lower:]' '[:upper:]')

    # Must be DELETE or UPDATE
    if ! printf '%s' "$upper_query" | grep -qE '^[[:space:]]*(DELETE|UPDATE)\b'; then
        printf 'false'
        return 0
    fi

    # Check for WHERE clause
    if printf '%s' "$upper_query" | grep -qE '\bWHERE\b'; then
        printf 'false'
        return 0
    fi

    # Check for LIMIT clause (bounded by row count)
    if printf '%s' "$upper_query" | grep -qE '\bLIMIT\b'; then
        printf 'false'
        return 0
    fi

    # Check for IN subquery (bounded by subquery result)
    if printf '%s' "$upper_query" | grep -qE '\bIN[[:space:]]*\('; then
        printf 'false'
        return 0
    fi

    # No WHERE, LIMIT, or bounding clause found — unbounded
    printf 'true'
    return 0
}

# ---------------------------------------------------------------------------
# _dbg_evaluate_policy OPERATION_TYPE TARGET_ENV QUERY [HAS_APPROVAL_TOKEN] [HAS_BACKUP]
#
# Evaluates the operation against the policy rule set in priority order.
# Rules are evaluated highest-priority-first; the first matching rule wins.
#
# Arguments:
#   OPERATION_TYPE    — one of: read, write_dml, write_ddl, admin
#   TARGET_ENV        — one of: production, staging, development, local, unknown
#   QUERY             — the SQL/command string
#   HAS_APPROVAL_TOKEN — "approved" if an approval token exists, "" otherwise
#   HAS_BACKUP        — "true" if verified backup exists, "false" or "" otherwise
#
# Returns: "<decision>|<rule_id>:<reason>"
#   decision: "allow", "deny", or "escalate"
#   rule_id:  identifies which rule matched
#   reason:   human-readable explanation
#
# Policy Rules (evaluated in priority order):
#   Priority 1: cascade-check     — FK cascade risk, all envs → escalate
#   Priority 2: unbounded-delete  — DELETE/UPDATE without WHERE → deny (prod/staging), warn (dev)
#   Priority 3: backup-required   — DDL in prod/staging without backup → deny
#   Priority 4: prod-no-ddl       — DDL in production → deny
#   Priority 5: prod-readonly     — Write in production → deny (unless approved)
#   Priority 6: staging-approval  — Destructive DML in staging → escalate
#   Priority 7: dev-permissive    — Any op in development → allow
#   Priority 8: local-permissive  — Any op against localhost → allow
#   Priority 9: unknown-conservative — Write in unknown env → deny
#   Default:    allow             — All reads and unmatched ops → allow
#
# @decision DEC-DBGUARD-007
# @title Rule priority: structural safety > env-specific policy > permissive defaults
# @status accepted
# @rationale Cascade and unbounded checks are evaluated first because they represent
#   structural risk that is environment-independent (an unbounded DELETE in development
#   that gets accidentally run in production is still catastrophic). Environment-specific
#   rules come next. Permissive defaults (dev, local) are low-priority so structural
#   checks always fire first even in development environments.
# ---------------------------------------------------------------------------
_dbg_evaluate_policy() {
    local op_type="${1:-write_dml}"
    local target_env="${2:-unknown}"
    local query="${3:-}"
    local has_approval="${4:-}"
    local has_backup="${5:-false}"

    # --- Priority 1: cascade-check (all environments) ---
    # Cascade risk escalates regardless of environment — human must review.
    if [[ "$op_type" == "write_dml" || "$op_type" == "write_ddl" ]]; then
        local cascade_risk
        cascade_risk="$(_dbg_detect_cascade_risk "$query")"
        if [[ "$cascade_risk" == "true" ]]; then
            printf 'escalate|cascade-check:Query involves potential FK cascade; human review required'
            return 0
        fi
    fi

    # --- Priority 2: unbounded-delete (deny in prod/staging, warn in dev) ---
    local is_unbounded
    is_unbounded="$(_dbg_detect_unbounded "$query")"
    if [[ "$is_unbounded" == "true" ]]; then
        case "$target_env" in
            production|staging|unknown)
                printf 'deny|unbounded-delete:DELETE/UPDATE without WHERE clause; all rows would be affected'
                return 0
                ;;
            development|local)
                # In dev/local we warn but do not deny — logged separately
                printf 'allow|unbounded-delete-warning:Unbounded DML in non-production; proceeding with audit log'
                return 0
                ;;
        esac
    fi

    # --- Priority 3: backup-required (DDL in prod/staging without verified backup) ---
    if [[ "$op_type" == "write_ddl" ]]; then
        case "$target_env" in
            production|staging)
                if [[ "$has_backup" != "true" ]]; then
                    printf 'deny|backup-required:DDL in %s requires verified backup before proceeding' "$target_env"
                    return 0
                fi
                ;;
        esac
    fi

    # --- Priority 4: prod-no-ddl (any DDL in production denied; DBA approval required) ---
    if [[ "$op_type" == "write_ddl" && "$target_env" == "production" ]]; then
        printf 'deny|prod-no-ddl:DDL in production requires DBA approval; use change management process'
        return 0
    fi

    # --- Priority 5: prod-readonly (writes in production) ---
    if [[ "$target_env" == "production" ]]; then
        case "$op_type" in
            write_dml|write_ddl|admin)
                if [[ "$has_approval" == "approved" ]]; then
                    printf 'allow|prod-readonly-approved:Write in production allowed with explicit approval token'
                    return 0
                fi
                printf 'deny|prod-readonly:Write operation in production requires explicit approval token'
                return 0
                ;;
        esac
    fi

    # --- Priority 6: staging-approval (destructive DML in staging) ---
    if [[ "$target_env" == "staging" ]]; then
        case "$op_type" in
            write_dml)
                # DELETE is inherently destructive; INSERT/UPDATE are lower risk
                local upper_query
                upper_query=$(printf '%s' "$query" | tr '[:lower:]' '[:upper:]')
                if printf '%s' "$upper_query" | grep -qE '^[[:space:]]*DELETE\b'; then
                    printf 'escalate|staging-approval:Destructive DML (DELETE) in staging requires user approval'
                    return 0
                fi
                # Non-DELETE DML in staging: allow with audit
                printf 'allow|staging-dml:Non-destructive DML in staging allowed with audit log'
                return 0
                ;;
        esac
    fi

    # --- Priority 7: dev-permissive (all operations in development) ---
    if [[ "$target_env" == "development" ]]; then
        printf 'allow|dev-permissive:All operations allowed in development environment; audit logged'
        return 0
    fi

    # --- Priority 8: local-permissive (all operations against localhost) ---
    if [[ "$target_env" == "local" ]]; then
        printf 'allow|local-permissive:All operations allowed against local database'
        return 0
    fi

    # --- Priority 9: unknown-conservative (writes in unknown environment) ---
    if [[ "$target_env" == "unknown" ]]; then
        case "$op_type" in
            write_dml|write_ddl|admin)
                printf 'deny|unknown-conservative:Write operation in unknown environment denied; classify environment first'
                return 0
                ;;
        esac
    fi

    # --- Default: allow (reads, and any remaining unmatched patterns) ---
    printf 'allow|default:Operation permitted by default policy'
    return 0
}

# =============================================================================
# D4: Simulation Helpers
#
# These functions build the COMMAND strings used to simulate operations before
# executing. The DB Guardian agent passes these commands to its Bash tool calls.
# The functions do NOT execute the commands themselves — they generate the
# correct CLI invocation for each database type.
#
# @decision DEC-DBGUARD-008
# @title Simulation functions generate command strings, not execute them
# @status accepted
# @rationale The DB Guardian agent must be able to inspect and approve the
#   simulation command before execution. If functions executed commands directly,
#   the agent would have no visibility into what was run. Returning command strings
#   allows the agent to display the simulation command to the user, execute it
#   through the Bash tool (with full audit trail), and parse the output.
#   This separation also makes unit testing straightforward — no database required.
# =============================================================================

# ---------------------------------------------------------------------------
# _dbg_simulate_explain CLI_TYPE QUERY CONNECTION_ARGS
#
# Builds an EXPLAIN command to estimate rows affected without executing.
#
# CLI-specific behavior:
#   psql     — EXPLAIN (ANALYZE false) <query>  (via -c flag)
#   mysql    — EXPLAIN <query>                  (via -e flag)
#   sqlite3  — EXPLAIN <query>                  (outputs opcodes)
#   mongosh  — db.collection.find({}).explain() (wraps find/aggregate)
#   redis-cli — "unsupported" (no preview mode)
#   cockroach — same as psql (CockroachDB supports EXPLAIN)
#
# Returns: the command string to execute, or "unsupported"
# ---------------------------------------------------------------------------
_dbg_simulate_explain() {
    local cli_type="${1:-}"
    local query="${2:-}"
    local connection_args="${3:-}"

    case "$cli_type" in
        psql|cockroach)
            # Wrap in EXPLAIN (ANALYZE false) to get the query plan without execution
            printf '%s %s -c "EXPLAIN (ANALYZE false) %s"' "$cli_type" "$connection_args" "$query"
            ;;
        mysql)
            # MySQL EXPLAIN shows optimizer's execution plan
            printf 'mysql %s -e "EXPLAIN %s"' "$connection_args" "$query"
            ;;
        sqlite3)
            # SQLite EXPLAIN outputs virtual machine opcodes; useful for understanding query plan
            printf 'sqlite3 %s "EXPLAIN %s"' "$connection_args" "$query"
            ;;
        mongosh)
            # mongosh explain() wraps the operation
            # Strip trailing semicolons/parens to inject .explain()
            local wrapped_query
            wrapped_query=$(printf '%s' "$query" | sed 's/[;[:space:]]*$//')
            printf 'mongosh %s --eval "%s.explain()"' "$connection_args" "$wrapped_query"
            ;;
        redis-cli)
            # Redis has no EXPLAIN or preview mode
            printf 'unsupported'
            ;;
        *)
            printf 'unsupported'
            ;;
    esac
    return 0
}

# ---------------------------------------------------------------------------
# _dbg_simulate_rollback CLI_TYPE QUERY CONNECTION_ARGS
#
# Wraps a DML query in a transaction that is always rolled back, allowing
# the agent to observe actual row counts and effects without committing.
#
# CLI-specific behavior:
#   psql     — BEGIN; <query>; ROLLBACK; (via -c, shows rows affected)
#   mysql    — BEGIN; <query>; ROLLBACK; NOTE: DDL auto-commits in MySQL
#   sqlite3  — BEGIN; <query>; ROLLBACK; (SQLite supports full transactions)
#   mongosh  — session.withTransaction() with abort (Mongo 4.0+ multi-doc txn)
#   redis-cli — "unsupported" (MULTI/EXEC has no preview/abort-after-preview mode)
#   cockroach — same as psql
#
# Returns: the command string to execute, or "unsupported"
# ---------------------------------------------------------------------------
_dbg_simulate_rollback() {
    local cli_type="${1:-}"
    local query="${2:-}"
    local connection_args="${3:-}"

    case "$cli_type" in
        psql|cockroach)
            printf '%s %s -c "BEGIN; %s; ROLLBACK;"' "$cli_type" "$connection_args" "$query"
            ;;
        mysql)
            # MySQL DDL (CREATE/DROP/ALTER/TRUNCATE) auto-commits and cannot be rolled back
            local upper_query
            upper_query=$(printf '%s' "$query" | tr '[:lower:]' '[:upper:]')
            if printf '%s' "$upper_query" | grep -qE '^[[:space:]]*(CREATE|DROP|ALTER|TRUNCATE|RENAME)\b'; then
                printf 'mysql %s -e "-- NOTE: DDL auto-commit in MySQL; rollback simulation unavailable. Query: %s"' \
                    "$connection_args" "$query"
            else
                printf 'mysql %s -e "BEGIN; %s; ROLLBACK;"' "$connection_args" "$query"
            fi
            ;;
        sqlite3)
            printf 'sqlite3 %s "BEGIN; %s; ROLLBACK;"' "$connection_args" "$query"
            ;;
        mongosh)
            # MongoDB 4.0+ supports multi-document transactions with abort
            printf 'mongosh %s --eval "const s=db.getMongo().startSession(); s.startTransaction(); %s; s.abortTransaction();"' \
                "$connection_args" "$query"
            ;;
        redis-cli)
            printf 'unsupported'
            ;;
        *)
            printf 'unsupported'
            ;;
    esac
    return 0
}

# ---------------------------------------------------------------------------
# _dbg_simulate_dryrun CLI_TYPE QUERY
#
# For DDL operations: generates a human-readable description of what would
# happen if the DDL were executed, without actually executing it.
#
# This is a textual analysis function — it parses the query and generates
# a structured description. For psql/cockroach, it also generates a BEGIN/ROLLBACK
# simulation command that the agent can execute to see actual DDL effects.
#
# Returns: description of what would happen
# ---------------------------------------------------------------------------
_dbg_simulate_dryrun() {
    local cli_type="${1:-}"
    local query="${2:-}"

    local upper_query
    upper_query=$(printf '%s' "$query" | tr '[:lower:]' '[:upper:]')

    # Extract the primary DDL verb and target
    local ddl_verb table_name
    ddl_verb=$(printf '%s' "$upper_query" | awk '{print $1}')
    table_name=$(printf '%s' "$upper_query" | sed -E 's/^[[:space:]]*(CREATE|DROP|ALTER|TRUNCATE|RENAME)[[:space:]]+(TABLE[[:space:]]+|INDEX[[:space:]]+|VIEW[[:space:]]+)?([[:alnum:]_."]+).*/\3/')

    case "$ddl_verb" in
        DROP)
            printf 'DRY-RUN: DROP TABLE %s — would permanently delete the table structure and ALL data. CLI: %s' \
                "$table_name" "$cli_type"
            ;;
        CREATE)
            printf 'DRY-RUN: CREATE operation on %s — would create new schema object. CLI: %s' \
                "$table_name" "$cli_type"
            ;;
        ALTER)
            printf 'DRY-RUN: ALTER TABLE %s — would modify table structure. MySQL auto-commits DDL (no rollback). CLI: %s' \
                "$table_name" "$cli_type"
            ;;
        TRUNCATE)
            printf 'DRY-RUN: TRUNCATE %s — would delete ALL rows instantly (faster than DELETE, may not fire triggers). CLI: %s' \
                "$table_name" "$cli_type"
            ;;
        RENAME)
            printf 'DRY-RUN: RENAME operation on %s — would rename schema object. CLI: %s' \
                "$table_name" "$cli_type"
            ;;
        *)
            printf 'DRY-RUN: DDL operation on %s — would modify database schema. CLI: %s. Query: %s' \
                "$table_name" "$cli_type" "$query"
            ;;
    esac
    return 0
}

# =============================================================================
# D5: Approval Gate
#
# The approval gate integrates with the existing state store (state-lib.sh) to
# create a persistent approval token mechanism. When a high-risk operation
# requires approval, the DB Guardian agent:
#   1. Calls _dbg_request_approval() to register the request and get a JSON payload
#   2. Presents the JSON payload to the orchestrator/user
#   3. The user grants approval (orchestrator writes state token)
#   4. Calls _dbg_check_approval() to verify the token before executing
#
# State keys: "dbg.approval.<execution_id>" → "pending" | "approved" | "denied"
#
# @decision DEC-DBGUARD-009
# @title Use state store (state-lib.sh) for approval token persistence
# @status accepted
# @rationale Approval tokens must survive agent restarts and be readable by
#   both the agent and the orchestrator. The state store (SQLite WAL via
#   state-lib.sh) is the established mechanism for this kind of cross-agent
#   coordination (see DEC-SQLITE-001). Writing to state.db ensures tokens are
#   durable, isolated by workflow_id, and auditable via the state history log.
#   File-based tokens in /tmp would not survive cleanup or be workflow-isolated.
# =============================================================================

# ---------------------------------------------------------------------------
# _dbg_request_approval OPERATION_DESCRIPTION SIMULATION_RESULT [EXECUTION_ID]
#
# Registers an approval request in the state store and returns a structured
# JSON approval request for the orchestrator to present to the user.
#
# Arguments:
#   OPERATION_DESCRIPTION — human-readable description of the operation
#   SIMULATION_RESULT     — output from simulation (EXPLAIN or rollback preview)
#   EXECUTION_ID          — optional; generated deterministically if omitted
#
# Side effects:
#   Writes "dbg.approval.<execution_id>" = "pending" to state store
#
# Returns: JSON approval request object on stdout
# ---------------------------------------------------------------------------
_dbg_request_approval() {
    local operation_desc="${1:-}"
    local simulation_result="${2:-}"
    local execution_id="${3:-}"

    # Generate execution ID if not provided
    if [[ -z "$execution_id" ]]; then
        execution_id="dbg-$(date +%s)-$$"
    fi

    # Register as pending in state store (if state functions are available)
    if type state_update &>/dev/null 2>&1; then
        state_update "dbg.approval.${execution_id}" "pending" "db-guardian"
    fi

    # Escape values for JSON (basic escaping — double quotes and backslashes)
    local escaped_desc escaped_sim
    escaped_desc=$(printf '%s' "$operation_desc" | sed 's/\\/\\\\/g; s/"/\\"/g')
    escaped_sim=$(printf '%s' "$simulation_result" | sed 's/\\/\\\\/g; s/"/\\"/g')

    # Return structured JSON approval request
    printf '{"type":"approval_request","execution_id":"%s","operation":"%s","simulation":"%s","status":"pending","instructions":"Set state key dbg.approval.%s to approved to authorize this operation"}' \
        "$execution_id" "$escaped_desc" "$escaped_sim" "$execution_id"
    return 0
}

# ---------------------------------------------------------------------------
# _dbg_check_approval EXECUTION_ID
#
# Checks whether an approval token exists for the given execution ID.
# Reads the state store key "dbg.approval.<execution_id>".
#
# Returns: "approved" if the token is approved, "pending" otherwise
#   (denied and missing both return "pending" for safe-default behavior)
# ---------------------------------------------------------------------------
_dbg_check_approval() {
    local execution_id="${1:-}"

    if [[ -z "$execution_id" ]]; then
        printf 'pending'
        return 0
    fi

    # Check state store if available
    if type state_read &>/dev/null 2>&1; then
        local token
        token=$(state_read "dbg.approval.${execution_id}" 2>/dev/null || printf '')
        if [[ "$token" == "approved" ]]; then
            printf 'approved'
            return 0
        fi
    fi

    # Default: pending (safe)
    printf 'pending'
    return 0
}
