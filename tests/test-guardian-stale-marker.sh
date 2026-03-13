#!/usr/bin/env bash
# Test Gate A.0 stale-marker fix for guardian duplicate-dispatch detection.
#
# Validates that Gate A.0 in task-track.sh checks trace status before denying
# dispatch — not just marker age. Follows the pattern established for Gate B
# (DEC-STALE-MARKER-003) where completed/crashed traces get their markers cleaned
# and allow dispatch through.
#
# Design note: Markers are created with current mtime. After all files are written to
# TEMP_TRACE, we backdate the directory 5 seconds so find's -newer TRACE_STORE filter
# picks up the markers (file mtime > dir mtime). The staleness decision comes from
# marker content and manifest.status — not file mtime.
#
# Tests:
#   T01: Fresh marker + completed trace manifest → cleaned, dispatch allowed
#   T02: Fresh marker + active trace manifest   → dispatch denied
#   T03: Pre-dispatch marker with old timestamp (>120s ago)  → cleaned, dispatch allowed
#   T04: Pre-dispatch marker with recent timestamp (<120s)   → dispatch denied
#   T05: No marker exists → dispatch allowed (existing behavior preserved)
#   T06: Fresh marker + crashed trace manifest  → cleaned, dispatch allowed
#
# @decision DEC-TEST-GUARDIAN-STALE-001
# @title Guardian stale marker fix test suite
# @status accepted
# @rationale Gate A.0 was blocking Guardian dispatch when markers from completed or
#   crashed agents still existed (finalize_trace cleanup failed, session crash, or
#   pre-dispatch marker from agent that never started). This test suite validates
#   the fix that checks trace manifest status before blocking dispatch.

set -euo pipefail

# Portable SHA-256 (macOS: shasum, Ubuntu: sha256sum)
if command -v shasum >/dev/null 2>&1; then
    _SHA256_CMD="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
    _SHA256_CMD="sha256sum"
else
    _SHA256_CMD="cat"
fi

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
HOOKS_DIR="$PROJECT_ROOT/hooks"

# Ensure tmp directory exists
mkdir -p "$PROJECT_ROOT/tmp"

# Cleanup trap: collect temp dirs and remove on exit
_CLEANUP_DIRS=()
trap '[[ ${#_CLEANUP_DIRS[@]} -gt 0 ]] && rm -rf "${_CLEANUP_DIRS[@]}" 2>/dev/null; true' EXIT

# Track test results
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local test_name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Running: $test_name"
}

pass_test() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS"
}

fail_test() {
    local reason="$1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: $reason"
}

# Backdate a directory's mtime by N seconds so files created in it appear
# strictly newer (needed for find's -newer TRACE_STORE filter).
# Usage: _backdate_dir DIR [SECONDS]
_backdate_dir() {
    local dir="$1"
    local secs="${2:-5}"
    local target_epoch=$(( $(date +%s) - secs ))
    # macOS: date -r EPOCH; Linux: date -d @EPOCH
    local touch_fmt
    touch_fmt=$(date -r "$target_epoch" +%Y%m%d%H%M.%S 2>/dev/null \
                || date -d "@$target_epoch" +%Y%m%d%H%M.%S 2>/dev/null \
                || echo "")
    if [[ -n "$touch_fmt" ]]; then
        touch -t "$touch_fmt" "$dir" 2>/dev/null || true
    fi
}

# --- Syntax validation ---
run_test "Syntax: task-track.sh is valid bash"
if bash -n "$HOOKS_DIR/task-track.sh"; then
    pass_test
else
    fail_test "task-track.sh has syntax errors"
fi

# Helper: run task-track.sh as guardian with a controlled TRACE_STORE state.
#
# All markers are written to TEMP_TRACE with current mtime. After all files
# are written, _backdate_dir shifts TEMP_TRACE 5s into the past so find's
# -newer TRACE_STORE filter includes the fresh markers.
#
# Args:
#   $1 - marker_content: content to write to the marker file:
#          - a trace_id string (no |) → looks up TRACE_STORE/<trace_id>/manifest.json
#          - "pre-dispatch|<epoch>"   → pre-dispatch path; epoch in content is checked
#          - ""                        → no marker (T05 baseline)
#   $2 - manifest_status: status field for manifest.json ("active", "completed",
#                          "crashed") or "" to skip manifest creation
#
# Returns exit code; echoes hook OUTPUT.
run_guardian_task_track() {
    local marker_content="${1:-}"
    local manifest_status="${2:-}"

    # Isolated temp git repo
    local TEMP_REPO
    TEMP_REPO=$(mktemp -d "$PROJECT_ROOT/tmp/test-gsm-repo-XXXXXX")
    _CLEANUP_DIRS+=("$TEMP_REPO")
    git -C "$TEMP_REPO" init > /dev/null 2>&1
    mkdir -p "$TEMP_REPO/.claude"

    # Isolated TRACE_STORE (no cross-test interference with real traces)
    local TEMP_TRACE
    TEMP_TRACE=$(mktemp -d "$PROJECT_ROOT/tmp/test-gsm-traces-XXXXXX")
    _CLEANUP_DIRS+=("$TEMP_TRACE")

    # Compute project hash (must match what task-track.sh computes for TEMP_REPO)
    local PHASH
    PHASH=$(echo "$TEMP_REPO" | $_SHA256_CMD | cut -c1-8)

    # Write verified proof-status so Gate A (proof gate) passes.
    # We're testing Gate A.0 (duplicate detection), not Gate A (proof gate).
    mkdir -p "$TEMP_REPO/.claude/state/${PHASH}"
    echo "verified|$(date +%s)" > "$TEMP_REPO/.claude/state/${PHASH}/proof-status"

    # Create the guardian marker in TRACE_STORE with a stable fake session ID.
    local FAKE_SESSION="test-session-gsm-12345"
    if [[ -n "$marker_content" ]]; then
        local MARKER_FILE="${TEMP_TRACE}/.active-guardian-${FAKE_SESSION}-${PHASH}"
        echo "$marker_content" > "$MARKER_FILE"
    fi

    # Create trace directory + manifest when marker_content is a trace_id
    # (no | separator — distinguishes from "pre-dispatch|timestamp" format).
    if [[ -n "$manifest_status" && -n "$marker_content" && "$marker_content" != *"|"* ]]; then
        local TRACE_ID="$marker_content"
        local TRACE_DIR="${TEMP_TRACE}/${TRACE_ID}"
        mkdir -p "$TRACE_DIR/artifacts"
        cat > "$TRACE_DIR/manifest.json" <<MANIFEST
{
  "version": "1",
  "trace_id": "${TRACE_ID}",
  "agent_type": "guardian",
  "session_id": "${FAKE_SESSION}",
  "project": "${TEMP_REPO}",
  "project_name": "test-repo",
  "branch": "main",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "${manifest_status}"
}
MANIFEST
        # summary.md makes the state realistic (completed/crashed had an agent that ran)
        if [[ "$manifest_status" != "active" ]]; then
            echo "Guardian completed/crashed during test run." > "$TRACE_DIR/summary.md"
        fi
    fi

    # Backdate TEMP_TRACE directory so all files within appear strictly newer.
    # find's -newer TRACE_STORE requires file mtime > dir mtime.
    # Without this, files created in the dir update the dir's mtime to match,
    # so the files are never strictly newer and find returns empty.
    _backdate_dir "$TEMP_TRACE" 5

    # Mock input JSON for Guardian dispatch.
    # Using @plan-update so Gate A (proof gate) uses bypass path.
    # Gate A.0 runs before Gate A, so the @plan-update flag does NOT affect A.0.
    local INPUT_JSON
    INPUT_JSON=$(cat <<EOF
{
  "tool_name": "Agent",
  "tool_input": {
    "subagent_type": "guardian",
    "prompt": "@plan-update test dispatch for Gate A.0"
  }
}
EOF
)

    # Run hook with isolated environment.
    # TRACE_STORE override ensures Gate A.0's find scans our temp dir only.
    # CLAUDE_DIR ensures proof-status reads from our isolated dir.
    # Run from TEMP_REPO so detect_project_root() resolves to TEMP_REPO.
    local OUTPUT
    OUTPUT=$(CLAUDE_PROJECT_DIR="$TEMP_REPO" \
             CLAUDE_DIR="$TEMP_REPO/.claude" \
             TRACE_STORE="$TEMP_TRACE" \
             bash "$HOOKS_DIR/task-track.sh" <<< "$INPUT_JSON" 2>&1) || true

    echo "$OUTPUT"
}

# --- T01: Fresh marker + completed trace → cleaned, dispatch allowed ---
run_test "T01: Marker with completed trace → dispatch allowed (stale marker cleaned)"
FAKE_TRACE_T01="guardian-20260307-010101-aabbcc"
OUTPUT=$(run_guardian_task_track "$FAKE_TRACE_T01" "completed" 2>&1) || true
if echo "$OUTPUT" | grep -qi "deny"; then
    fail_test "Guardian blocked when trace manifest shows 'completed' — stale marker should be cleaned and dispatch allowed"
else
    pass_test
fi

# --- T02: Fresh marker + active trace → dispatch denied ---
run_test "T02: Marker with active trace → dispatch denied (genuine duplicate)"
FAKE_TRACE_T02="guardian-20260307-020202-bbccdd"
OUTPUT=$(run_guardian_task_track "$FAKE_TRACE_T02" "active" 2>&1) || true
if echo "$OUTPUT" | grep -qi "deny"; then
    pass_test
else
    fail_test "Guardian dispatch allowed when another Guardian trace is genuinely active (should deny)"
fi

# --- T03: Pre-dispatch marker with OLD embedded timestamp → cleaned, dispatch allowed ---
run_test "T03: Pre-dispatch marker with old timestamp (>120s) → dispatch allowed"
OLD_EPOCH=$(( $(date +%s) - 300 ))
OUTPUT=$(run_guardian_task_track "pre-dispatch|${OLD_EPOCH}" "" 2>&1) || true
if echo "$OUTPUT" | grep -qi "deny"; then
    fail_test "Guardian blocked on old pre-dispatch marker (>120s) — agent never started, should clean and allow"
else
    pass_test
fi

# --- T04: Pre-dispatch marker with RECENT embedded timestamp → dispatch denied ---
run_test "T04: Pre-dispatch marker with recent timestamp (<120s) → dispatch denied"
RECENT_EPOCH=$(( $(date +%s) - 30 ))
OUTPUT=$(run_guardian_task_track "pre-dispatch|${RECENT_EPOCH}" "" 2>&1) || true
if echo "$OUTPUT" | grep -qi "deny"; then
    pass_test
else
    fail_test "Guardian dispatch allowed when pre-dispatch marker is only 30s old (should deny — agent may be starting)"
fi

# --- T05: No marker → dispatch allowed ---
run_test "T05: No marker exists → dispatch allowed (baseline behavior)"
OUTPUT=$(run_guardian_task_track "" "" 2>&1) || true
if echo "$OUTPUT" | grep -qi "deny"; then
    fail_test "Guardian blocked when no active marker exists (should always allow)"
else
    pass_test
fi

# --- T06: Fresh marker + crashed trace → cleaned, dispatch allowed ---
run_test "T06: Marker with crashed trace → dispatch allowed (stale marker cleaned)"
FAKE_TRACE_T06="guardian-20260307-060606-ddeeff"
OUTPUT=$(run_guardian_task_track "$FAKE_TRACE_T06" "crashed" 2>&1) || true
if echo "$OUTPUT" | grep -qi "deny"; then
    fail_test "Guardian blocked when trace manifest shows 'crashed' — stale marker should be cleaned and dispatch allowed"
else
    pass_test
fi

# --- Summary ---
echo ""
echo "=========================================="
echo "Test Results: $TESTS_PASSED/$TESTS_RUN passed"
echo "=========================================="

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAILED: $TESTS_FAILED tests failed"
    exit 1
else
    echo "SUCCESS: All tests passed"
    exit 0
fi
