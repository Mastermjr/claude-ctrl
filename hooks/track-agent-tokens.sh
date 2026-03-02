#!/usr/bin/env bash
set -euo pipefail

# track-agent-tokens.sh — Universal SubagentStop hook for token accumulation.
#
# SubagentStop hook — matcher: (all agent types, no matcher = universal)
#
# Fired after every subagent completes. Parses the agent's transcript JSONL
# to sum token usage, appends a record to the session-scoped state file, and
# updates .statusline-cache with the running subagent token total so the status
# bar can display combined session + subagent tokens as "tokens: 145k (Σ240k)".
#
# @decision DEC-SUBAGENT-TOKENS-002
# @title Universal SubagentStop hook for token accumulation via transcript parsing
# @status accepted
# @rationale The SubagentStop payload includes agent_transcript_path — the JSONL
# file written by Claude Code for the completed agent's run. By parsing it in a
# universal (no-matcher) SubagentStop hook, we capture token costs for ALL agent
# types without adding per-agent boilerplate. The hook exits 0 silently when no
# transcript is available (Bash/Explore agents may not produce one), making it
# safe to run universally. Token data is appended to a session-scoped state file
# (.subagent-tokens-<session_id>) using pipe-delimited format for grep-able reads.
# The statusline reads subagent_tokens from .statusline-cache (written by this hook
# via jq merge) without needing to re-parse the transcript on every render cycle.
#
# @decision DEC-SUBAGENT-TOKENS-003
# @title Pipe-delimited state file with epoch|agent_type|input|output|cache_read|cache_create|total
# @status accepted
# @rationale JSONL would require jq -s to aggregate, adding per-render cost. A
# pipe-delimited text file lets the hook use awk to sum the total column in a
# single pass with no external dependencies beyond awk and cut — both are in the
# Bash allow list. The format is grep-friendly for debugging and audit: each line
# is one subagent run, total field is pre-computed at write time to avoid parsing
# all four fields on every accumulation.
#
# State file: $CLAUDE_DIR/.subagent-tokens-<session_id>
#   Line format: epoch|agent_type|input|output|cache_read|cache_create|total
#
# Cache update: merges subagent_tokens field into .statusline-cache via jq
#   so statusline.sh can read it without re-parsing the state file.
#
# Output: {"additionalContext": "Subagent tokens tracked: Nk total"}
#   The message is informational; hooks do not block on token tracking.
#
# Depends on: source-lib.sh → core-lib.sh (read_input, get_field, get_claude_dir)
#             session-lib.sh (sum_transcript_tokens) via require_session

source "$(dirname "$0")/source-lib.sh"
require_session

# --- Read SubagentStop payload ---
HOOK_INPUT=$(read_input)
AGENT_TYPE=$(get_field '.agent_type' <<< "$HOOK_INPUT")
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.agent_transcript_path // empty' 2>/dev/null || true)

# Exit silently if no transcript path provided (Bash/Explore agents, or missing field)
if [[ -z "$TRANSCRIPT_PATH" ]]; then
    exit 0
fi

# Exit silently if transcript file does not exist
if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
    exit 0
fi

# --- Parse transcript for token usage ---
TOKEN_JSON=$(sum_transcript_tokens "$TRANSCRIPT_PATH" 2>/dev/null) || {
    # Transcript exists but is unparseable — exit silently, never block
    exit 0
}

# Extract individual fields (default 0 if missing)
INPUT_TOKENS=$(echo "$TOKEN_JSON" | jq -r '.input // 0' 2>/dev/null || echo 0)
OUTPUT_TOKENS=$(echo "$TOKEN_JSON" | jq -r '.output // 0' 2>/dev/null || echo 0)
CACHE_READ=$(echo "$TOKEN_JSON" | jq -r '.cache_read // 0' 2>/dev/null || echo 0)
CACHE_CREATE=$(echo "$TOKEN_JSON" | jq -r '.cache_create // 0' 2>/dev/null || echo 0)

# Pre-compute total (all four fields contribute to actual token cost)
TOTAL_TOKENS=$(( INPUT_TOKENS + OUTPUT_TOKENS + CACHE_READ + CACHE_CREATE ))

# Skip if all zeros (empty transcript or model returned no usage data)
if [[ "$TOTAL_TOKENS" -eq 0 ]]; then
    exit 0
fi

# --- Append to session-scoped state file ---
CLAUDE_DIR=$(get_claude_dir)
STATE_FILE="${CLAUDE_DIR}/.subagent-tokens-${CLAUDE_SESSION_ID:-$$}"
EPOCH=$(date +%s)

# Pipe-delimited: epoch|agent_type|input|output|cache_read|cache_create|total
printf '%d|%s|%d|%d|%d|%d|%d\n' \
    "$EPOCH" \
    "${AGENT_TYPE:-unknown}" \
    "$INPUT_TOKENS" \
    "$OUTPUT_TOKENS" \
    "$CACHE_READ" \
    "$CACHE_CREATE" \
    "$TOTAL_TOKENS" >> "$STATE_FILE"

# --- Update .statusline-cache with cumulative subagent_tokens ---
CACHE_FILE="${CLAUDE_DIR}/.statusline-cache"

# Sum all total fields from the state file (column 7, 1-indexed)
CUMULATIVE_TOTAL=0
if [[ -f "$STATE_FILE" ]]; then
    # awk sums column 7 (total) across all lines
    CUMULATIVE_TOTAL=$(awk -F'|' '{s += $7} END {print s+0}' "$STATE_FILE" 2>/dev/null || echo 0)
fi

# Merge subagent_tokens into existing cache (create cache if missing)
if [[ -f "$CACHE_FILE" ]]; then
    TMP_CACHE="${CACHE_FILE}.tmp.$$"
    if jq --argjson st "$CUMULATIVE_TOTAL" '. + {subagent_tokens: $st}' "$CACHE_FILE" \
        > "$TMP_CACHE" 2>/dev/null; then
        mv "$TMP_CACHE" "$CACHE_FILE"
    else
        rm -f "$TMP_CACHE"
    fi
else
    # No existing cache — write minimal object so statusline.sh can read it
    jq -n --argjson st "$CUMULATIVE_TOTAL" '{subagent_tokens: $st}' \
        > "$CACHE_FILE" 2>/dev/null || true
fi

# --- Emit informational output ---
TOTAL_K=$(( CUMULATIVE_TOTAL / 1000 ))
printf '{"additionalContext": "Subagent tokens tracked: %dk total (%s: +%dk)"}\n' \
    "$TOTAL_K" \
    "${AGENT_TYPE:-unknown}" \
    "$(( TOTAL_TOKENS / 1000 ))"

exit 0
