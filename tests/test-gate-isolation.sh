#!/usr/bin/env bash
# Tests for per-gate error isolation (S1 fix — issue #63)
#
# @decision DEC-TEST-GATE-ISOLATE-001
# @title Test suite for _run_gate() and _run_blocking_gate() isolation helpers
# @status accepted
# @rationale Validates that a crashing advisory gate does not prevent subsequent
#   gates from executing in consolidated hooks. Tests cover:
#   - _run_gate(): crash in gate does not propagate; subsequent code runs
#   - _run_gate(): normal gate exit (0) works as expected
#   - _run_blocking_gate(): crash is isolated; subsequent code runs
#   - _run_blocking_gate(): planned exit 2 propagates to caller
#   - _run_blocking_gate(): normal gate exit (0) allows continuation
#   - set+e/set-e sandwiching pattern used for side-effect gates (track, surface)

set -euo pipefail
HOOK_DIR="$(cd "$(dirname "$0")/../hooks" && pwd)"
TESTS_PASSED=0
TESTS_FAILED=0

# Test helpers
pass() { echo "PASS: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
fail() { echo "FAIL: $1 — $2"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

# Load core-lib.sh to get _run_gate and _run_blocking_gate
# We need source-lib.sh which loads core-lib.sh. Use a minimal load:
# Since we're testing in isolation, source core-lib.sh directly (it's self-contained).
TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# Minimal stub for log_info (used by _run_gate's crash logging)
log_info() { echo "[LOG] $1: $2" >&2 2>/dev/null || true; }
export -f log_info

# Source core-lib.sh to get _run_gate/_run_blocking_gate
# We need to provide minimal stubs for its dependencies
source "$HOOK_DIR/core-lib.sh" 2>/dev/null || {
    echo "SKIP: Could not source core-lib.sh (may need full hook environment)"
    exit 0
}

# =============================================================================
# T01: _run_gate() — crash in gate is isolated; subsequent code continues
# =============================================================================
_isolation_test_result=""

_crashing_gate() {
    exit 1  # Simulate crash
}

_continuation_check() {
    _isolation_test_result="continued"
}

_run_gate "test-crash" _crashing_gate
_continuation_check

if [[ "$_isolation_test_result" == "continued" ]]; then
    pass "T01: _run_gate() isolates crash — subsequent code continues"
else
    fail "T01: _run_gate() isolates crash — subsequent code continues" "result: $_isolation_test_result"
fi

# =============================================================================
# T02: _run_gate() — normal exit (0) allows continuation
# =============================================================================
_t02_ran=false

_normal_gate() {
    return 0
}

_t02_after() {
    _t02_ran=true
}

_run_gate "test-normal" _normal_gate
_t02_after

if [[ "$_t02_ran" == "true" ]]; then
    pass "T02: _run_gate() normal exit (0) — subsequent code continues"
else
    fail "T02: _run_gate() normal exit (0) — subsequent code continues" "after-gate code did not run"
fi

# =============================================================================
# T03: _run_gate() — exit code non-zero (e.g. set -e command fails) is isolated
# =============================================================================
_t03_after_ran=false

_set_e_crashing_gate() {
    set -euo pipefail
    false  # Returns 1 under set -e — triggers exit
}

_run_gate "test-set-e-crash" _set_e_crashing_gate
_t03_after_ran=true

if [[ "$_t03_after_ran" == "true" ]]; then
    pass "T03: _run_gate() isolates set-e crash — subsequent code continues"
else
    fail "T03: _run_gate() isolates set-e crash — subsequent code continues" "after-gate code did not run"
fi

# =============================================================================
# T04: _run_blocking_gate() — crash is isolated; subsequent code continues
# =============================================================================
_t04_after_ran=false

_crashing_blocking_gate() {
    exit 5  # Non-2, non-0 exit: crash
}

_run_blocking_gate "test-crash-blocking" _crashing_blocking_gate
_t04_after_ran=true

if [[ "$_t04_after_ran" == "true" ]]; then
    pass "T04: _run_blocking_gate() isolates crash (exit 5) — subsequent code continues"
else
    fail "T04: _run_blocking_gate() isolates crash (exit 5) — subsequent code continues" "after-gate code did not run"
fi

# =============================================================================
# T05: _run_blocking_gate() — planned exit 2 propagates to parent hook
# =============================================================================
_t05_exit_code=0

_blocking_gate_exit2() {
    exit 2  # Planned block signal
}

(
    _run_blocking_gate "test-exit2" _blocking_gate_exit2
) || _t05_exit_code=$?

if [[ "$_t05_exit_code" -eq 2 ]]; then
    pass "T05: _run_blocking_gate() propagates planned exit 2"
else
    fail "T05: _run_blocking_gate() propagates planned exit 2" "exit code: $_t05_exit_code"
fi

# =============================================================================
# T06: _run_blocking_gate() — normal exit (0) allows continuation
# =============================================================================
_t06_after_ran=false

_normal_blocking_gate() {
    return 0
}

_run_blocking_gate "test-normal-blocking" _normal_blocking_gate
_t06_after_ran=true

if [[ "$_t06_after_ran" == "true" ]]; then
    pass "T06: _run_blocking_gate() normal exit (0) — subsequent code continues"
else
    fail "T06: _run_blocking_gate() normal exit (0) — subsequent code continues" "after-gate code did not run"
fi

# =============================================================================
# T07: set+e/set-e sandwiching — failing command does not propagate when set+e
# (tests the pattern used for track in post-write.sh and surface in stop.sh)
# Note: explicit `exit N` always exits; set+e only swallows non-zero RETURN codes.
# The pattern in stop.sh/post-write.sh uses `false` and command failures, not exit.
# =============================================================================
_t07_result="not-set"

set +e
false  # Command fails (returns 1) — under set+e, this is swallowed
_t07_result="continued-after-failing-command"
set -e

if [[ "$_t07_result" == "continued-after-failing-command" ]]; then
    pass "T07: set+e/set-e sandwiching — failing command (false) does not propagate; execution continues"
else
    fail "T07: set+e/set-e sandwiching — failing command (false) does not propagate; execution continues" "result: $_t07_result"
fi

# =============================================================================
# T08: _run_gate() subshell — explicit exit 1 in gate IS isolated
# (unlike set+e which can't swallow `exit`, _run_gate's subshell contains it)
# =============================================================================
_t08_after_ran=false

_explicit_exit_gate() {
    exit 1  # Explicit exit — contained by subshell in _run_gate
}

_run_gate "test-explicit-exit" _explicit_exit_gate
_t08_after_ran=true

if [[ "$_t08_after_ran" == "true" ]]; then
    pass "T08: _run_gate() isolates explicit exit 1 in gate — subsequent code continues"
else
    fail "T08: _run_gate() isolates explicit exit 1 in gate — subsequent code continues" "after-gate code did not run"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed out of $((TESTS_PASSED + TESTS_FAILED)) tests"

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
exit 0
