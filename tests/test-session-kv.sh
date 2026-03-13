#!/usr/bin/env bash
# test-session-kv.sh — Unit tests for session KV migrations (DEC-STATE-KV-002, DEC-STATE-KV-005)
#
# Validates:
#   DEC-STATE-KV-002: migrating .session-start-epoch and .prompt-count-{SESSION_ID}
#     from flat files to SQLite KV store (state_update/state_read/state_delete).
#   DEC-STATE-KV-005: migrating .test-status (and state/{phash}/test-status) to SQLite
#     KV store via test_status key.
#
# Tests:
#   T01: state_update/state_read cycle for session_start_epoch
#   T02: state_update/state_read cycle for prompt_count
#   T03: state_delete cleans both keys
#   T04: First-prompt detection — key absent → first prompt; key present → not first
#   T05: state_update/state_read cycle for test_status (DEC-STATE-KV-005)
#   T06: state_delete removes test_status key
#   T07: test_status KV takes priority over flat-file fallback (readers prefer KV)
#   T08: test_status KV absent falls back to flat-file gracefully
#
# NOTE: All tests share one DB environment (ENV1) to avoid the _STATE_SCHEMA_INITIALIZED
# module-level guard blocking schema init on a second fresh DB within the same process.
# state-lib.sh initializes the schema once per process; switching CLAUDE_DIR mid-run
# would point to a new DB without a schema, causing state_update to fail silently.
# ENV1 is established in T01 and reused through T08.
#
# @decision DEC-STATE-KV-002
# @title Migrate session_start_epoch and prompt_count to SQLite KV store
# @status accepted
# @rationale These two dotfiles are written together in the first-prompt block of
#   prompt-submit.sh and cleaned together in session-init.sh and session-end.sh.
#   Migrating them to SQLite provides atomic writes and eliminates race conditions
#   between concurrent processes. Flat-file dual-write retained during migration
#   window for backward compatibility.
#
# @decision DEC-STATE-KV-005
# @title Migrate test_status to SQLite KV store
# @status accepted
# @rationale .test-status (and state/{phash}/test-status) is written by test-runner.sh
#   and read by guard.sh, check-implementer.sh, check-guardian.sh, subagent-start.sh,
#   session-init.sh, stop.sh, and compact-preserve.sh. Migrating to SQLite eliminates
#   the multi-path lookup (CLAUDE_DIR/.test-status, PROJECT_ROOT/.test-status,
#   PROJECT_ROOT/.claude/.test-status) and provides atomic writes. Dual-write retained
#   during migration window for backward compatibility with existing readers.
#
# Usage: bash tests/test-session-kv.sh
# Scope: --scope session-kv in run-hooks.sh

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
HOOKS_DIR="$PROJECT_ROOT/hooks"

mkdir -p "$PROJECT_ROOT/tmp"

# ---------------------------------------------------------------------------
# Test tracking
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Setup: isolated temp dir, cleaned up on EXIT
# ---------------------------------------------------------------------------
TMPDIR_BASE="$PROJECT_ROOT/tmp/test-session-kv-$$"
mkdir -p "$TMPDIR_BASE"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# ---------------------------------------------------------------------------
# Helper: isolated env with git repo + .claude dir
# ---------------------------------------------------------------------------
make_temp_env() {
    local dir
    dir="$TMPDIR_BASE/env-$RANDOM"
    mkdir -p "$dir/.claude"
    git -C "$dir" init -q 2>/dev/null || true
    echo "$dir"
}

# ---------------------------------------------------------------------------
# Source hook libraries
# ---------------------------------------------------------------------------
_HOOK_NAME="test-session-kv"
source "$HOOKS_DIR/log.sh" 2>/dev/null
source "$HOOKS_DIR/source-lib.sh" 2>/dev/null
require_state

# ---------------------------------------------------------------------------
# Establish shared ENV1 (single DB for entire test run)
# All tests T01-T08 share this environment. state-lib.sh's _STATE_SCHEMA_INITIALIZED
# guard prevents re-running schema init within one process; switching CLAUDE_DIR to
# a second fresh DB would cause state_update to fail on the uninitialised schema.
# ---------------------------------------------------------------------------
ENV1=$(make_temp_env)
export HOME="$ENV1"
export CLAUDE_DIR="$ENV1/.claude"
export PROJECT_ROOT_OVERRIDE="$ENV1"

# ===========================================================================
# T01: state_update/state_read cycle for session_start_epoch
# ===========================================================================
run_test "T01: state_update/state_read for session_start_epoch"

EPOCH_VAL="$(date +%s)"
state_update "session_start_epoch" "$EPOCH_VAL" "test-session-kv" 2>/dev/null || true

RESULT=$(state_read "session_start_epoch" 2>/dev/null || echo "")
if [[ "$RESULT" == "$EPOCH_VAL" ]]; then
    pass_test
else
    fail_test "Expected '$EPOCH_VAL', got '$RESULT'"
fi

# ===========================================================================
# T02: state_update/state_read cycle for prompt_count
# ===========================================================================
run_test "T02: state_update/state_read for prompt_count"

# Writing "1" simulates first prompt initialization
state_update "prompt_count" "1" "test-session-kv" 2>/dev/null || true

RESULT=$(state_read "prompt_count" 2>/dev/null || echo "")
if [[ "$RESULT" == "1" ]]; then
    pass_test
else
    fail_test "Expected '1', got '$RESULT'"
fi

# Also verify increment: write "2" and read it back
state_update "prompt_count" "2" "test-session-kv" 2>/dev/null || true
RESULT=$(state_read "prompt_count" 2>/dev/null || echo "")
if [[ "$RESULT" == "2" ]]; then
    pass_test
else
    fail_test "After increment: Expected '2', got '$RESULT'"
    TESTS_RUN=$((TESTS_RUN + 1))  # extra assertion counted
fi

# ===========================================================================
# T03: state_delete cleans both keys
# ===========================================================================
run_test "T03: state_delete cleans session_start_epoch and prompt_count"

# Ensure both keys are present before delete
state_update "session_start_epoch" "$(date +%s)" "test-session-kv" 2>/dev/null || true
state_update "prompt_count" "5" "test-session-kv" 2>/dev/null || true

# Delete both
state_delete "session_start_epoch" 2>/dev/null || true
state_delete "prompt_count" 2>/dev/null || true

EPOCH_AFTER=$(state_read "session_start_epoch" 2>/dev/null || echo "")
COUNT_AFTER=$(state_read "prompt_count" 2>/dev/null || echo "")

if [[ -z "$EPOCH_AFTER" && -z "$COUNT_AFTER" ]]; then
    pass_test
else
    fail_test "After delete: session_start_epoch='$EPOCH_AFTER', prompt_count='$COUNT_AFTER' (both should be empty)"
fi

# ===========================================================================
# T04: First-prompt detection — key absent -> first prompt; key present -> not first
#
# After T03 deleted prompt_count, the key is absent. We verify:
#   (a) state_read returns empty -> first-prompt path would fire
#   (b) After state_update, state_read returns the value -> subsequent prompts skip first-prompt
# ===========================================================================
run_test "T04: first-prompt detection via prompt_count key presence"

# (a) T03 already deleted prompt_count -- verify key is absent
ABSENT=$(state_read "prompt_count" 2>/dev/null || echo "")
if [[ -z "$ABSENT" ]]; then
    # Simulate first-prompt: write prompt_count=1
    state_update "prompt_count" "1" "test-session-kv" 2>/dev/null || true
    # (b) Now key is present -- subsequent prompts should NOT enter first-prompt block
    PRESENT=$(state_read "prompt_count" 2>/dev/null || echo "")
    if [[ -n "$PRESENT" ]]; then
        pass_test
    else
        fail_test "After state_update prompt_count=1, state_read returned empty (not-first-prompt detection broken)"
    fi
else
    fail_test "Expected absent prompt_count after T03 cleanup, got '$ABSENT'"
fi

# ===========================================================================
# T05: state_update/state_read cycle for test_status (DEC-STATE-KV-005)
#
# test-runner.sh writes: state_update "test_status" "$result|$fails|$ts" "test-runner"
# Readers call:          state_read "test_status" 2>/dev/null
# ===========================================================================
run_test "T05: state_update/state_read for test_status (DEC-STATE-KV-005)"

# Clean any residual test_status
state_delete "test_status" 2>/dev/null || true

TS_NOW="$(date +%s)"
TS_VAL="pass|0|${TS_NOW}"
state_update "test_status" "$TS_VAL" "test-session-kv" 2>/dev/null || true

TS_READ=$(state_read "test_status" 2>/dev/null || echo "")
if [[ "$TS_READ" == "$TS_VAL" ]]; then
    pass_test
else
    fail_test "Expected '$TS_VAL', got '$TS_READ'"
fi

# Also verify fail variant (test-runner.sh writes both pass and fail)
TS_FAIL="fail|3|${TS_NOW}"
state_update "test_status" "$TS_FAIL" "test-session-kv" 2>/dev/null || true
TS_READ2=$(state_read "test_status" 2>/dev/null || echo "")
if [[ "$TS_READ2" == "$TS_FAIL" ]]; then
    pass_test
else
    fail_test "Fail variant: Expected '$TS_FAIL', got '$TS_READ2'"
    TESTS_RUN=$((TESTS_RUN + 1))
fi

# ===========================================================================
# T06: state_delete removes test_status key
# ===========================================================================
run_test "T06: state_delete removes test_status key"

# test_status from T05 should still exist (fail|3|...)
state_delete "test_status" 2>/dev/null || true

TS_AFTER=$(state_read "test_status" 2>/dev/null || echo "")
if [[ -z "$TS_AFTER" ]]; then
    pass_test
else
    fail_test "After delete: test_status='$TS_AFTER' (should be empty)"
fi

# ===========================================================================
# T07: KV value takes priority -- reader prefers state_read over flat-file
#
# When both the KV store AND the flat-file exist with DIFFERENT values, readers
# following the migration pattern (KV first, flat-file fallback) must return
# the KV value, not the stale flat-file value.
# ===========================================================================
run_test "T07: test_status KV takes priority over flat-file (migration priority)"

TS7_NOW="$(date +%s)"
# Write KV with "pass"
state_update "test_status" "pass|0|${TS7_NOW}" "test-session-kv" 2>/dev/null || true
# Write flat-file with "fail" (stale/different value -- as if old test-runner wrote it)
printf 'fail|99|%s\n' "$TS7_NOW" > "${ENV1}/.claude/.test-status"

# Reader simulation: try KV first, fall back to flat-file
TS7_KV=$(state_read "test_status" 2>/dev/null || echo "")
TS7_RESULT=""
if [[ -n "$TS7_KV" ]]; then
    TS7_RESULT=$(printf '%s' "$TS7_KV" | cut -d'|' -f1)
else
    # Flat-file fallback
    TS7_RESULT=$(cut -d'|' -f1 "${ENV1}/.claude/.test-status" 2>/dev/null || echo "")
fi

if [[ "$TS7_RESULT" == "pass" ]]; then
    pass_test
else
    fail_test "KV priority: expected 'pass' from KV, got '$TS7_RESULT' (flat-file 'fail' should not win)"
fi

# Clean up for T08
state_delete "test_status" 2>/dev/null || true
rm -f "${ENV1}/.claude/.test-status"

# ===========================================================================
# T08: test_status KV absent falls back to flat-file gracefully
#
# When the KV store has no test_status entry but the flat-file exists,
# readers fall back to the flat-file. Validates backward compatibility
# during the dual-write migration window.
# ===========================================================================
run_test "T08: test_status absent from KV falls back to flat-file"

TS8_NOW="$(date +%s)"
# NO KV entry -- only flat-file (simulating legacy test-runner.sh before migration)
printf 'pass|0|%s\n' "$TS8_NOW" > "${ENV1}/.claude/.test-status"

# Reader simulation: try KV first (returns empty), fall back to flat-file
TS8_KV=$(state_read "test_status" 2>/dev/null || echo "")
TS8_RESULT=""
if [[ -n "$TS8_KV" ]]; then
    TS8_RESULT=$(printf '%s' "$TS8_KV" | cut -d'|' -f1)
else
    # Flat-file fallback -- this is the expected path for T08
    TS8_RESULT=$(cut -d'|' -f1 "${ENV1}/.claude/.test-status" 2>/dev/null || echo "")
fi

if [[ "$TS8_RESULT" == "pass" ]]; then
    pass_test
else
    fail_test "Fallback: expected 'pass' from flat-file when KV absent, got '$TS8_RESULT'"
fi

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
exit 0
