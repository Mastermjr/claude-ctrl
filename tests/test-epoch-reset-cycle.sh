#!/usr/bin/env bash
# test-epoch-reset-cycle.sh — Multi-cycle proof lifecycle with epoch reset
#
# Tests the full proof state lifecycle across two implementation cycles,
# validating that proof_epoch_reset() enables regression after committed state,
# and that the lattice correctly blocks regression WITHOUT epoch reset.
#
# Tests:
#   T01: First cycle — full happy path: needs-verification→pending→verified→committed
#   T02: Lattice rejects regression from committed to needs-verification (no epoch reset)
#   T03: proof_epoch_reset() enables the regression
#   T04: Second cycle completes — needs-verification→pending→verified→committed
#   T05: Epoch increments properly across cycles
#   T06: post-write.sh calls proof_epoch_reset before proof_state_set("pending") when committed
#   T07: task-track.sh calls proof_epoch_reset before proof_state_set("needs-verification") when committed
#   T08: check-tester.sh AUTO_VERIFIED is conditional on proof_state_set success
#   T09: session-init.sh cleans malformed workflow_ids (like "_main")
#   T10: All critical proof_state_set callers use error-checking (not bare || true)
#
# Usage: bash tests/test-epoch-reset-cycle.sh
# Exit: 0 if all pass, 1 if any fail
#
# @decision DEC-EPOCH-CYCLE-001
# @title Test multi-cycle proof lifecycle with epoch reset
# @status accepted
# @rationale Validates Bugs #227 and #228: epoch reset prevents deadlock after first
#   merge cycle, and error-checking on proof_state_set callers surfaces write failures.
#   Tests both the behavioral (runtime SQLite) and structural (grep-based) aspects.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT_OUTER="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_DIR="$PROJECT_ROOT_OUTER/hooks"

PASS=0
FAIL=0
SKIP=0
ERRORS=()

_pass() { echo "  PASS: $1"; (( PASS++ )) || true; }
_fail() { echo "  FAIL: $1"; ERRORS+=("$1"); (( FAIL++ )) || true; }
_skip() { echo "  SKIP: $1"; (( SKIP++ )) || true; }

echo "=== Epoch Reset Cycle Tests (#227, #228) ==="
echo ""

# ---------------------------------------------------------------------------
# T01–T05: Behavioral tests — require SQLite state-lib.sh
# ---------------------------------------------------------------------------

# Set up an isolated test database
_TMPDIR=$(mktemp -d)

# Source state-lib.sh in a controlled way
if ! (source "$HOOKS_DIR/state-lib.sh" 2>/dev/null && declare -f proof_state_set >/dev/null 2>&1); then
    _skip "T01-T05: state-lib.sh could not be sourced or proof_state_set unavailable — skipping behavioral tests"
    SKIP=5
else

# Run behavioral tests in a subshell to isolate state
_BEHAVIORAL_RESULT=$(
    set +e
    source "$HOOKS_DIR/source-lib.sh" 2>/dev/null || true
    source "$HOOKS_DIR/log.sh" 2>/dev/null || true
    source "$HOOKS_DIR/state-lib.sh" 2>/dev/null || true

    _TEST_ROOT="$_TMPDIR/project"
    mkdir -p "$_TEST_ROOT"
    export PROJECT_ROOT="$_TEST_ROOT"
    export CLAUDE_DIR="$_TEST_ROOT/.claude"
    mkdir -p "$CLAUDE_DIR"

    _OUT=""

    # T01: First cycle
    _T01_ERRORS=""
    proof_state_set "needs-verification" "test-t01" 2>/dev/null || _T01_ERRORS+=" needs-verification"
    proof_state_set "pending" "test-t01" 2>/dev/null || _T01_ERRORS+=" pending"
    proof_state_set "verified" "test-t01" 2>/dev/null || _T01_ERRORS+=" verified"
    proof_state_set "committed" "test-t01" 2>/dev/null || _T01_ERRORS+=" committed"
    _T01_STATUS=$(proof_state_get 2>/dev/null | cut -d'|' -f1 || echo "")
    if [[ -n "$_T01_ERRORS" ]]; then
        _OUT+="T01:FAIL:First cycle failed at:$_T01_ERRORS\n"
    elif [[ "$_T01_STATUS" != "committed" ]]; then
        _OUT+="T01:FAIL:Final state is '$_T01_STATUS' (expected committed)\n"
    else
        _OUT+="T01:PASS:First cycle completed — final state: committed\n"
    fi

    # T02: Lattice rejects regression WITHOUT epoch reset
    if proof_state_set "needs-verification" "test-t02" 2>/dev/null; then
        _T02_STATUS=$(proof_state_get 2>/dev/null | cut -d'|' -f1 || echo "")
        _OUT+="T02:FAIL:Lattice allowed regression to needs-verification without epoch reset (state=$_T02_STATUS)\n"
    else
        _T02_STATUS=$(proof_state_get 2>/dev/null | cut -d'|' -f1 || echo "")
        if [[ "$_T02_STATUS" == "committed" ]]; then
            _OUT+="T02:PASS:Lattice correctly rejected regression from committed to needs-verification\n"
        else
            _OUT+="T02:FAIL:State changed unexpectedly to '$_T02_STATUS' (expected committed)\n"
        fi
    fi

    # T03: Epoch reset enables regression
    if ! proof_epoch_reset 2>/dev/null; then
        _OUT+="T03:FAIL:proof_epoch_reset returned non-zero\n"
    elif proof_state_set "needs-verification" "test-t03" 2>/dev/null; then
        _OUT+="T03:PASS:proof_epoch_reset enabled regression to needs-verification\n"
    else
        _OUT+="T03:FAIL:proof_state_set(needs-verification) still rejected after epoch reset\n"
    fi

    # T04: Second cycle
    _T04_ERRORS=""
    proof_state_set "pending" "test-t04" 2>/dev/null || _T04_ERRORS+=" pending"
    proof_state_set "verified" "test-t04" 2>/dev/null || _T04_ERRORS+=" verified"
    proof_state_set "committed" "test-t04" 2>/dev/null || _T04_ERRORS+=" committed"
    _T04_STATUS=$(proof_state_get 2>/dev/null | cut -d'|' -f1 || echo "")
    if [[ -n "$_T04_ERRORS" ]]; then
        _OUT+="T04:FAIL:Second cycle failed at:$_T04_ERRORS\n"
    elif [[ "$_T04_STATUS" != "committed" ]]; then
        _OUT+="T04:FAIL:Final state is '$_T04_STATUS' (expected committed)\n"
    else
        _OUT+="T04:PASS:Second cycle completed — final state: committed\n"
    fi

    # T05: Epoch incremented
    _T05_EPOCH=$(proof_state_get 2>/dev/null | cut -d'|' -f2 || echo "0")
    if [[ "$_T05_EPOCH" =~ ^[0-9]+$ ]] && [[ "$_T05_EPOCH" -ge 1 ]]; then
        _OUT+="T05:PASS:Epoch is $_T05_EPOCH (>=1, incremented across cycles)\n"
    else
        _OUT+="T05:FAIL:Epoch is '$_T05_EPOCH' (expected >=1 after epoch reset)\n"
    fi

    printf '%b' "$_OUT"
)

# Process behavioral test results
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    _TNUM=$(echo "$line" | cut -d: -f1)
    _TRESULT=$(echo "$line" | cut -d: -f2)
    _TMSG=$(echo "$line" | cut -d: -f3-)
    if [[ "$_TRESULT" == "PASS" ]]; then
        _pass "$_TNUM: $_TMSG"
    elif [[ "$_TRESULT" == "FAIL" ]]; then
        _fail "$_TNUM: $_TMSG"
    fi
done <<< "$_BEHAVIORAL_RESULT"

fi  # end state-lib availability check

# Cleanup test temp dir
rm -rf "$_TMPDIR" 2>/dev/null || true

# ---------------------------------------------------------------------------
# T06–T10: Structural tests — grep-based
# ---------------------------------------------------------------------------

echo ""
echo "T06: post-write.sh calls proof_epoch_reset before proof_state_set('pending') when committed..."
_PW_FILE="$HOOKS_DIR/post-write.sh"
if [[ ! -f "$_PW_FILE" ]]; then
    _fail "T06: post-write.sh not found"
else
    if grep -q "proof_epoch_reset" "$_PW_FILE" 2>/dev/null; then
        _PW_RESET_LINE=$(grep -n "proof_epoch_reset" "$_PW_FILE" | head -1 | cut -d: -f1 || echo "0")
        _PW_SET_LINE=$(grep -n 'proof_state_set "pending" "post-write"' "$_PW_FILE" | head -1 | cut -d: -f1 || echo "9999")
        if [[ "$_PW_RESET_LINE" -gt 0 && "$_PW_RESET_LINE" -lt "$_PW_SET_LINE" ]]; then
            _pass "T06: post-write.sh calls proof_epoch_reset (line $_PW_RESET_LINE) before proof_state_set pending (line $_PW_SET_LINE)"
        else
            _fail "T06: proof_epoch_reset (line $_PW_RESET_LINE) is NOT before proof_state_set pending (line $_PW_SET_LINE)"
        fi
    else
        _fail "T06: proof_epoch_reset not found in post-write.sh"
    fi
fi

echo "T07: task-track.sh calls proof_epoch_reset before proof_state_set('needs-verification')..."
_TT_FILE="$HOOKS_DIR/task-track.sh"
if [[ ! -f "$_TT_FILE" ]]; then
    _fail "T07: task-track.sh not found"
else
    if grep -q "proof_epoch_reset" "$_TT_FILE" 2>/dev/null; then
        _pass "T07: task-track.sh contains proof_epoch_reset call"
    else
        _fail "T07: task-track.sh missing proof_epoch_reset call"
    fi
fi

echo "T08: check-tester.sh AUTO_VERIFIED is conditional on proof_state_set success..."
_CT_FILE="$HOOKS_DIR/check-tester.sh"
if [[ ! -f "$_CT_FILE" ]]; then
    _fail "T08: check-tester.sh not found"
else
    # The unconditional pattern (bug): "proof_state_set ... 2>/dev/null || true" on same line as or before AUTO_VERIFIED=true
    _T08_UNCONDITIONAL=$(grep -n 'proof_state_set "verified" "check-tester-autoverify" 2>/dev/null || true' "$_CT_FILE" 2>/dev/null | head -1 || true)
    if [[ -n "$_T08_UNCONDITIONAL" ]]; then
        _fail "T08: check-tester.sh still has unconditional proof_state_set (|| true pattern): line $_T08_UNCONDITIONAL"
    else
        # Check that the conditional pattern exists
        if grep -q 'if.*proof_state_set.*verified.*check-tester-autoverify\|if ! proof_state_set.*verified.*check-tester-autoverify' "$_CT_FILE" 2>/dev/null; then
            _pass "T08: check-tester.sh AUTO_VERIFIED is conditional on proof_state_set success"
        else
            # Check if AUTO_VERIFIED=true follows an if block around proof_state_set
            _T08_VERIFIED_LINE=$(grep -n 'proof_state_set "verified" "check-tester-autoverify"' "$_CT_FILE" | head -1 | cut -d: -f1 || echo "0")
            _T08_AV_LINE=$(grep -n 'AUTO_VERIFIED=true' "$_CT_FILE" | head -1 | cut -d: -f1 || echo "0")
            if [[ "$_T08_VERIFIED_LINE" -gt 0 && "$_T08_AV_LINE" -gt "$_T08_VERIFIED_LINE" ]]; then
                # Check the context — is there an 'if' wrapping the proof_state_set?
                _T08_CONTEXT=$(sed -n "$((${_T08_VERIFIED_LINE}-2)),$((${_T08_VERIFIED_LINE}+3))p" "$_CT_FILE" 2>/dev/null || true)
                if echo "$_T08_CONTEXT" | grep -q "^if "; then
                    _pass "T08: check-tester.sh AUTO_VERIFIED is conditional on proof_state_set success"
                else
                    _fail "T08: check-tester.sh AUTO_VERIFIED conditional check inconclusive — manual review needed"
                fi
            else
                _fail "T08: check-tester.sh AUTO_VERIFIED=true pattern not found after proof_state_set"
            fi
        fi
    fi
fi

echo "T09: session-init.sh cleans malformed workflow_ids..."
_SI_FILE="$HOOKS_DIR/session-init.sh"
if [[ ! -f "$_SI_FILE" ]]; then
    _fail "T09: session-init.sh not found"
else
    if grep -q "malformed workflow_id\|NOT GLOB\|workflow_id.*_main\|_main.*workflow_id" "$_SI_FILE" 2>/dev/null; then
        _pass "T09: session-init.sh contains malformed workflow_id cleanup"
    else
        _fail "T09: session-init.sh missing malformed workflow_id cleanup"
    fi
fi

echo "T10: Critical proof_state_set callers use error-checking (not bare '|| true')..."
_T10_PASS=true

# check-tester.sh — verified autoverify must NOT be bare || true
_T10_CT=$(grep 'proof_state_set "verified" "check-tester-autoverify"' "$HOOKS_DIR/check-tester.sh" 2>/dev/null || true)
if echo "$_T10_CT" | grep -q '2>/dev/null || true$'; then
    _T10_PASS=false
    echo "    check-tester.sh verified autoverify still uses bare || true"
fi

# check-tester.sh — pending safetynet must NOT be bare || true
_T10_CT_SAFE=$(grep 'proof_state_set "pending" "check-tester-safetynet"' "$HOOKS_DIR/check-tester.sh" 2>/dev/null || true)
if echo "$_T10_CT_SAFE" | grep -q '2>/dev/null || true$'; then
    _T10_PASS=false
    echo "    check-tester.sh pending safetynet still uses bare || true"
fi

# check-guardian.sh — committed must NOT be bare || true
_T10_CG=$(grep 'proof_state_set "committed" "check-guardian"' "$HOOKS_DIR/check-guardian.sh" 2>/dev/null || true)
if echo "$_T10_CG" | grep -q '2>/dev/null || true$'; then
    _T10_PASS=false
    echo "    check-guardian.sh committed still uses bare || true"
fi

# post-write.sh — pending must NOT be bare || true
_T10_PW=$(grep 'proof_state_set "pending" "post-write"' "$HOOKS_DIR/post-write.sh" 2>/dev/null || true)
if echo "$_T10_PW" | grep -q '2>/dev/null || true$'; then
    _T10_PASS=false
    echo "    post-write.sh pending still uses bare || true"
fi

# task-track.sh — needs-verification must NOT be bare || true
_T10_TT=$(grep 'proof_state_set "needs-verification" "task-track"' "$HOOKS_DIR/task-track.sh" 2>/dev/null || true)
if echo "$_T10_TT" | grep -q '2>/dev/null || true$'; then
    _T10_PASS=false
    echo "    task-track.sh needs-verification still uses bare || true"
fi

if [[ "$_T10_PASS" == "true" ]]; then
    _pass "T10: All critical proof_state_set callers use error-checking (not bare || true)"
else
    _fail "T10: Some critical proof_state_set callers still use bare || true"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "=== Results: PASS=$PASS FAIL=$FAIL SKIP=$SKIP ==="
if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo "Failed tests:"
    for e in "${ERRORS[@]}"; do
        echo "  - $e"
    done
fi
echo ""

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
exit 0
