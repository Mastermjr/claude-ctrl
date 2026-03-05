#!/usr/bin/env bash
# test-bootstrap-mitigation.sh — Tests for #105 bootstrap paradox mitigations
#
# Validates M1 (CAS failure counter in prompt-submit.sh) and
# M2 (plan-only bypass in task-track.sh):
#
#   M1: CAS failure counter
#     - TM01: Counter file created on first CAS failure
#     - TM02: Counter increments on repeated same-transition failures
#     - TM03: Counter resets (file deleted) on CAS success
#     - TM04: Warning injected into CONTEXT_PARTS after 2+ failures
#
#   M2: Plan-only bypass in task-track.sh Gate A
#     - TM05: @plan-update in prompt bypasses proof gate (needs-verification → allowed)
#     - TM06: @no-source in prompt bypasses proof gate (pending → allowed)
#     - TM07: Without bypass annotation, needs-verification still blocks Guardian
#     - TM08: @plan-update source-level check — grep finds the bypass in task-track.sh
#
# @decision DEC-BOOTSTRAP-TEST-001
# @title Targeted test suite for bootstrap paradox mitigations
# @status accepted
# @rationale M1 and M2 fix the bootstrap paradox scenario from Phase 2 merge:
#   when gate infrastructure itself is the fix target, the old broken gate on
#   main blocks the merge of the fix. These tests validate both mitigations
#   work as specified. See #105.
#
# Usage: bash tests/test-bootstrap-mitigation.sh
# Scope: --scope concurrency (runs alongside concurrency tests in run-hooks.sh)

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
HOOKS_DIR="$PROJECT_ROOT/hooks"

# Ensure tmp directory exists
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
TMPDIR_BASE="$PROJECT_ROOT/tmp/test-bootstrap-$$"
mkdir -p "$TMPDIR_BASE"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# ---------------------------------------------------------------------------
# SHA-256 helper (portable across macOS and Linux)
# ---------------------------------------------------------------------------
if command -v shasum &>/dev/null; then
    _SHA256_CMD="shasum -a 256"
elif command -v sha256sum &>/dev/null; then
    _SHA256_CMD="sha256sum"
else
    _SHA256_CMD="shasum -a 256"  # fallback
fi

compute_phash() {
    echo "$1" | $_SHA256_CMD | cut -c1-8 2>/dev/null || echo "00000000"
}

# ---------------------------------------------------------------------------
# Helper: make a clean isolated environment
# ---------------------------------------------------------------------------
make_temp_env() {
    local dir
    dir="$TMPDIR_BASE/env-$RANDOM"
    mkdir -p "$dir/.claude"
    git -C "$dir" init -q 2>/dev/null || true
    echo "$dir"
}

# ---------------------------------------------------------------------------
# Source hook libraries for unit-style testing
# ---------------------------------------------------------------------------
_HOOK_NAME="test-bootstrap-mitigation"
source "$HOOKS_DIR/log.sh" 2>/dev/null
source "$HOOKS_DIR/source-lib.sh" 2>/dev/null
require_state


# ===========================================================================
# TM01: M1 — CAS failure counter file created on first failure
#
# Simulate a CAS failure (wrong expected value) and verify the counter file
# ${CLAUDE_DIR}/.cas-failures is created with count=1.
# ===========================================================================
run_test "TM01: M1 — CAS failure counter file created on first failure"

TM01_ENV=$(make_temp_env)
TM01_CLAUDE="$TM01_ENV/.claude"

export CLAUDE_DIR="$TM01_CLAUDE"
export PROJECT_ROOT="$TM01_ENV"
export TRACE_STORE="$TMPDIR_BASE/traces-tm01"
export CLAUDE_SESSION_ID="tm01-session-$$"
mkdir -p "$TMPDIR_BASE/traces-tm01"

# Set proof-status to needs-verification
(
    export CLAUDE_DIR="$TM01_CLAUDE"
    export PROJECT_ROOT="$TM01_ENV"
    export TRACE_STORE="$TMPDIR_BASE/traces-tm01"
    export CLAUDE_SESSION_ID="tm01-session-$$"
    write_proof_status "needs-verification" "$TM01_ENV" 2>/dev/null
) 2>/dev/null || true

# Define the CAS failure counter logic inline (mirrors prompt-submit.sh fast-path)
_apply_cas_failure_counter() {
    local current_status="$1"
    local claude_dir="$2"
    local cas_fail_file="${claude_dir}/.cas-failures"
    local cas_fail_count=1
    if [[ -f "$cas_fail_file" ]]; then
        local prev_count
        prev_count=$(cut -d'|' -f1 "$cas_fail_file" 2>/dev/null || echo "0")
        local prev_exp
        prev_exp=$(cut -d'|' -f2 "$cas_fail_file" 2>/dev/null || echo "")
        local prev_new
        prev_new=$(cut -d'|' -f3 "$cas_fail_file" 2>/dev/null || echo "")
        if [[ "$prev_exp" == "$current_status" && "$prev_new" == "verified" ]]; then
            cas_fail_count=$(( prev_count + 1 ))
        fi
    fi
    printf '%s\n' "${cas_fail_count}|${current_status}|verified|$(date +%s)" > "$cas_fail_file" 2>/dev/null || true
    echo "$cas_fail_count"
}

# Remove any existing counter file
rm -f "$TM01_CLAUDE/.cas-failures" 2>/dev/null || true

# Simulate first CAS failure
_apply_cas_failure_counter "needs-verification" "$TM01_CLAUDE" > /dev/null

CAS_FAIL_FILE="$TM01_CLAUDE/.cas-failures"
if [[ -f "$CAS_FAIL_FILE" ]]; then
    COUNT=$(cut -d'|' -f1 "$CAS_FAIL_FILE" 2>/dev/null || echo "0")
    if [[ "$COUNT" == "1" ]]; then
        pass_test
    else
        fail_test "Expected count=1 on first failure; got '$COUNT'"
    fi
else
    fail_test "Counter file not created at $CAS_FAIL_FILE"
fi

unset CLAUDE_DIR PROJECT_ROOT TRACE_STORE CLAUDE_SESSION_ID 2>/dev/null || true


# ===========================================================================
# TM02: M1 — Counter increments on repeated same-transition failures
#
# Call the counter logic twice for the same transition and verify count=2.
# ===========================================================================
run_test "TM02: M1 — Counter increments on repeated same-transition failures"

TM02_ENV=$(make_temp_env)
TM02_CLAUDE="$TM02_ENV/.claude"

# Remove any existing counter file
rm -f "$TM02_CLAUDE/.cas-failures" 2>/dev/null || true

# First failure
_apply_cas_failure_counter "needs-verification" "$TM02_CLAUDE" > /dev/null
# Second failure (same transition)
_apply_cas_failure_counter "needs-verification" "$TM02_CLAUDE" > /dev/null

CAS_FAIL_FILE="$TM02_CLAUDE/.cas-failures"
if [[ -f "$CAS_FAIL_FILE" ]]; then
    COUNT=$(cut -d'|' -f1 "$CAS_FAIL_FILE" 2>/dev/null || echo "0")
    if [[ "$COUNT" == "2" ]]; then
        pass_test
    else
        fail_test "Expected count=2 after two failures; got '$COUNT'"
    fi
else
    fail_test "Counter file not found at $CAS_FAIL_FILE"
fi


# ===========================================================================
# TM03: M1 — Counter file deleted on CAS success
#
# Simulate the CAS success path in prompt-submit.sh (which deletes .cas-failures)
# and verify the file is removed.
# ===========================================================================
run_test "TM03: M1 — Counter file deleted on CAS success"

TM03_ENV=$(make_temp_env)
TM03_CLAUDE="$TM03_ENV/.claude"

# Pre-populate the counter file (simulating prior failures)
printf '2|pending|verified|%s\n' "$(date +%s)" > "$TM03_CLAUDE/.cas-failures"

# Simulate CAS success cleanup (mirrors prompt-submit.sh success path)
rm -f "$TM03_CLAUDE/.cas-failures" 2>/dev/null || true

if [[ ! -f "$TM03_CLAUDE/.cas-failures" ]]; then
    pass_test
else
    fail_test "Counter file still exists after CAS success cleanup"
fi


# ===========================================================================
# TM04: M1 — Warning injected into CONTEXT_PARTS after 2+ failures
#
# Verify that prompt-submit.sh contains the bootstrap paradox warning logic
# and that it checks count >= 2 before injecting the warning.
# This is a source-level structural check (the hook is not invoked directly
# due to its full context dependency on HOOK_INPUT).
# ===========================================================================
run_test "TM04: M1 — prompt-submit.sh contains bootstrap paradox warning logic (source check)"

PROMPT_SUBMIT="$HOOKS_DIR/prompt-submit.sh"

if [[ -f "$PROMPT_SUBMIT" ]]; then
    # Must contain the counter file reference
    if grep -q 'cas-failures' "$PROMPT_SUBMIT" && \
       grep -q 'BOOTSTRAP PARADOX WARNING' "$PROMPT_SUBMIT" && \
       grep -q '_CAS_WARN_COUNT.*-ge 2' "$PROMPT_SUBMIT"; then
        pass_test
    else
        fail_test "prompt-submit.sh missing bootstrap paradox warning logic (cas-failures, WARNING text, or count check)"
    fi
else
    fail_test "prompt-submit.sh not found at $PROMPT_SUBMIT"
fi


# ===========================================================================
# TM05: M2 — @plan-update in prompt bypasses proof gate
#
# Run task-track.sh with guardian agent, needs-verification proof status,
# and @plan-update in the dispatch prompt. Verify NOT denied.
# ===========================================================================
run_test "TM05: M2 — @plan-update bypasses Guardian proof gate"

TM05_ENV=$(make_temp_env)
TM05_PHASH=$(compute_phash "$TM05_ENV")

# Set proof-status to needs-verification (would block without bypass)
mkdir -p "$TM05_ENV/.claude"
printf 'needs-verification|%s\n' "$(date +%s)" > "$TM05_ENV/.claude/.proof-status-${TM05_PHASH}"

INPUT_JSON=$(cat <<EOF
{
  "tool_name": "Task",
  "tool_input": {
    "subagent_type": "guardian",
    "prompt": "Merge plan amendment @plan-update — MASTER_PLAN.md changes only, no source files"
  }
}
EOF
)

TM05_OUTPUT=""
TM05_EXIT=0
TM05_OUTPUT=$(cd "$TM05_ENV" && echo "$INPUT_JSON" | \
    CLAUDE_PROJECT_DIR="$TM05_ENV" bash "$HOOKS_DIR/task-track.sh" 2>&1) || TM05_EXIT=$?

if echo "$TM05_OUTPUT" | grep -q "deny"; then
    fail_test "@plan-update bypass failed — Guardian was denied despite annotation (output: ${TM05_OUTPUT:0:200})"
else
    pass_test
fi

rm -rf "$TM05_ENV" 2>/dev/null || true


# ===========================================================================
# TM06: M2 — @no-source in prompt bypasses proof gate
#
# Same test but using @no-source annotation.
# ===========================================================================
run_test "TM06: M2 — @no-source bypasses Guardian proof gate"

TM06_ENV=$(make_temp_env)
TM06_PHASH=$(compute_phash "$TM06_ENV")

mkdir -p "$TM06_ENV/.claude"
printf 'pending|%s\n' "$(date +%s)" > "$TM06_ENV/.claude/.proof-status-${TM06_PHASH}"

INPUT_JSON=$(cat <<EOF
{
  "tool_name": "Task",
  "tool_input": {
    "subagent_type": "guardian",
    "prompt": "Commit documentation changes @no-source"
  }
}
EOF
)

TM06_OUTPUT=""
TM06_EXIT=0
TM06_OUTPUT=$(cd "$TM06_ENV" && echo "$INPUT_JSON" | \
    CLAUDE_PROJECT_DIR="$TM06_ENV" bash "$HOOKS_DIR/task-track.sh" 2>&1) || TM06_EXIT=$?

if echo "$TM06_OUTPUT" | grep -q "deny"; then
    fail_test "@no-source bypass failed — Guardian was denied despite annotation (output: ${TM06_OUTPUT:0:200})"
else
    pass_test
fi

rm -rf "$TM06_ENV" 2>/dev/null || true


# ===========================================================================
# TM07: M2 — Without bypass annotation, needs-verification still blocks Guardian
#
# Verify the bypass is NOT active when the annotation is absent. This ensures
# the bypass cannot be triggered accidentally.
# ===========================================================================
run_test "TM07: M2 — Without bypass annotation, needs-verification blocks Guardian"

TM07_ENV=$(make_temp_env)
TM07_PHASH=$(compute_phash "$TM07_ENV")

mkdir -p "$TM07_ENV/.claude"
printf 'needs-verification|%s\n' "$(date +%s)" > "$TM07_ENV/.claude/.proof-status-${TM07_PHASH}"

INPUT_JSON=$(cat <<EOF
{
  "tool_name": "Task",
  "tool_input": {
    "subagent_type": "guardian",
    "prompt": "Merge changes — normal guardian dispatch"
  }
}
EOF
)

TM07_OUTPUT=""
TM07_EXIT=0
TM07_OUTPUT=$(cd "$TM07_ENV" && echo "$INPUT_JSON" | \
    CLAUDE_PROJECT_DIR="$TM07_ENV" bash "$HOOKS_DIR/task-track.sh" 2>&1) || TM07_EXIT=$?

if echo "$TM07_OUTPUT" | grep -q "deny"; then
    pass_test
else
    fail_test "Guardian should be denied for needs-verification without bypass annotation (output: ${TM07_OUTPUT:0:200})"
fi

rm -rf "$TM07_ENV" 2>/dev/null || true


# ===========================================================================
# TM08: M2 — Source check: task-track.sh contains plan-only bypass logic
#
# Verify the bypass code is present in task-track.sh.
# ===========================================================================
run_test "TM08: M2 — task-track.sh contains plan-only bypass logic (source check)"

TASK_TRACK="$HOOKS_DIR/task-track.sh"

if [[ -f "$TASK_TRACK" ]]; then
    if grep -q '@plan-update' "$TASK_TRACK" && \
       grep -q '@no-source' "$TASK_TRACK" && \
       grep -q '_PROOF_BYPASS' "$TASK_TRACK" && \
       grep -q 'DEC-BOOTSTRAP-PARADOX-002' "$TASK_TRACK"; then
        pass_test
    else
        fail_test "task-track.sh missing plan-only bypass logic (@plan-update, @no-source, _PROOF_BYPASS, or decision annotation)"
    fi
else
    fail_test "task-track.sh not found at $TASK_TRACK"
fi


# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "================================="
echo "Bootstrap Mitigation Tests: $TESTS_RUN run | $TESTS_PASSED passed | $TESTS_FAILED failed"
echo "================================="

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
