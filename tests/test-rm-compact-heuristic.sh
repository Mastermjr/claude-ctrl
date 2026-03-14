#!/usr/bin/env bash
# test-rm-compact-heuristic.sh — Validates removal of compaction heuristic from prompt-submit.sh
#
# Purpose: Verify that DEC-COMPACT-001 compaction heuristic block has been removed
# from hooks/prompt-submit.sh. With a 1M context window, the fixed thresholds (35/60
# prompts, 45/90 minutes) fired at ~17% usage, creating unnecessary cache_read overhead.
#
# @decision DEC-PERF-007
# @title Remove prompt-submit.sh compaction heuristic
# @status accepted
# @rationale Fixed thresholds (35/60 prompts, 45/90 minutes) were designed for 200K
#   context. With 1M context, they fire at ~17% usage. Claude Code handles
#   auto-compaction natively. The suggestion injection itself adds to cache_read overhead.
#
# Coverage:
#   RCH-01: DEC-COMPACT-001 annotation is NOT present in prompt-submit.sh
#   RCH-02: SUGGEST_COMPACT variable is NOT present
#   RCH-03: Prompt count threshold check (35 || 60) is NOT present
#   RCH-04: Session duration threshold (45..47 / 90..92) is NOT present
#   RCH-05: "Context management:" injection string is NOT present
#   RCH-06: prompt_count increment logic IS still present (not removed)
#   RCH-07: prompt-submit.sh passes bash -n syntax check
#   RCH-08: At prompt count 35, no "Context management" appears in output
#   RCH-09: At prompt count 60, no "Context management" appears in output
#   RCH-10: prompt-submit.sh still runs without error after removal
#
# Usage: bash tests/test-rm-compact-heuristic.sh
# Returns: 0 if all tests pass, 1 if any fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/hooks"
PS_HOOK="$HOOKS_DIR/prompt-submit.sh"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1 — ${2:-}"; FAIL=$((FAIL + 1)); }

_CLEANUP_DIRS=()
trap '[[ ${#_CLEANUP_DIRS[@]} -gt 0 ]] && rm -rf "${_CLEANUP_DIRS[@]}" 2>/dev/null; true' EXIT

echo "=== test-rm-compact-heuristic.sh ==="
echo ""

# ============================================================
# Static checks: verify the heuristic code is gone
# ============================================================

echo "--- RCH-01 through RCH-06: static source checks ---"

# RCH-01: DEC-COMPACT-001 annotation removed
if grep -q "DEC-COMPACT-001" "$PS_HOOK" 2>/dev/null; then
    fail "RCH-01: DEC-COMPACT-001 annotation removed" "still present in prompt-submit.sh"
else
    pass "RCH-01: DEC-COMPACT-001 annotation removed"
fi

# RCH-02: SUGGEST_COMPACT variable removed
if grep -q "SUGGEST_COMPACT" "$PS_HOOK" 2>/dev/null; then
    fail "RCH-02: SUGGEST_COMPACT variable removed" "still present in prompt-submit.sh"
else
    pass "RCH-02: SUGGEST_COMPACT variable removed"
fi

# RCH-03: Prompt count threshold check (35 || 60) removed
if grep -qE '"\-eq 35|\-eq 60' "$PS_HOOK" 2>/dev/null; then
    fail "RCH-03: prompt count threshold (35/60) removed" "still present in prompt-submit.sh"
else
    pass "RCH-03: prompt count threshold (35/60) removed"
fi

# RCH-04: Session duration threshold (45..47 / 90..92) removed
if grep -qE 'ELAPSED_MIN.*-ge 45|ELAPSED_MIN.*-ge 90' "$PS_HOOK" 2>/dev/null; then
    fail "RCH-04: session duration threshold removed" "still present in prompt-submit.sh"
else
    pass "RCH-04: session duration threshold removed"
fi

# RCH-05: "Context management:" injection string removed
if grep -q "Context management:" "$PS_HOOK" 2>/dev/null; then
    fail "RCH-05: 'Context management:' injection string removed" "still present in prompt-submit.sh"
else
    pass "RCH-05: 'Context management:' injection string removed"
fi

# RCH-06: prompt_count increment logic still present (must NOT be removed)
if grep -q "_PC_NEXT" "$PS_HOOK" 2>/dev/null; then
    pass "RCH-06: prompt_count increment logic still present"
else
    fail "RCH-06: prompt_count increment logic still present" "_PC_NEXT not found — increment was accidentally removed"
fi

echo ""

# ============================================================
# RCH-07: Syntax check
# ============================================================

echo "--- RCH-07: syntax check ---"

if bash -n "$PS_HOOK" 2>/dev/null; then
    pass "RCH-07: prompt-submit.sh passes bash -n syntax check"
else
    fail "RCH-07: prompt-submit.sh passes bash -n syntax check" "syntax error in prompt-submit.sh"
fi

echo ""

# ============================================================
# RCH-08/09: Behavioral checks — no compaction injection at thresholds
# ============================================================

echo "--- RCH-08/09: behavioral output checks ---"

_make_test_dir() {
    local d
    d=$(mktemp -d)
    _CLEANUP_DIRS+=("$d")
    mkdir -p "$d/.claude"
    git init "$d" >/dev/null 2>&1
    echo "$d"
}

_run_prompt_submit() {
    local project_dir="$1" prompt_count="$2"
    local state_dir
    state_dir=$(mktemp -d)
    _CLEANUP_DIRS+=("$state_dir")

    # Write a minimal SQLite DB with the given prompt_count via state_update
    # Use subshell to avoid sourcing libs into our shell
    (
        export CLAUDE_PROJECT_DIR="$project_dir"
        export CLAUDE_DIR="$state_dir"
        export CLAUDE_SESSION_ID="test-rch-$$"
        export _HOOK_NAME="test-rm-compact-heuristic"

        # Prime the state DB with the given prompt count
        if [[ -f "$HOOKS_DIR/source-lib.sh" ]]; then
            # shellcheck disable=SC1090
            source "$HOOKS_DIR/source-lib.sh" 2>/dev/null
            init_hook 2>/dev/null || true
            state_update "prompt_count" "$prompt_count" "test" 2>/dev/null || true
        fi

        # Now run prompt-submit.sh — it should NOT inject "Context management:"
        printf '{"prompt":"What is 2+2?"}' \
            | CLAUDE_PROJECT_DIR="$project_dir" \
              CLAUDE_DIR="$state_dir" \
              CLAUDE_SESSION_ID="test-rch-$$" \
              bash "$HOOKS_DIR/prompt-submit.sh" 2>/dev/null || true
    )
}

# Helper: check output does NOT contain "Context management:"
_assert_no_compact_injection() {
    local test_name="$1" output="$2"
    if echo "$output" | grep -q "Context management:"; then
        fail "$test_name" "found unexpected 'Context management:' in output"
    else
        pass "$test_name"
    fi
}

PS_DIR=$(_make_test_dir)

# RCH-08: At prompt count 35, no "Context management" injection
output_35=$(_run_prompt_submit "$PS_DIR" 35)
_assert_no_compact_injection "RCH-08: no 'Context management:' injection at prompt 35" "$output_35"

# RCH-09: At prompt count 60, no "Context management" injection
output_60=$(_run_prompt_submit "$PS_DIR" 60)
_assert_no_compact_injection "RCH-09: no 'Context management:' injection at prompt 60" "$output_60"

echo ""

# ============================================================
# RCH-10: prompt-submit.sh runs without error on a normal prompt
# ============================================================

echo "--- RCH-10: smoke test ---"

PS_DIR2=$(_make_test_dir)
smoke_output=$(
    printf '{"prompt":"Hello world"}' \
        | CLAUDE_PROJECT_DIR="$PS_DIR2" \
          CLAUDE_DIR="$(mktemp -d)" \
          CLAUDE_SESSION_ID="test-rch-smoke-$$" \
          bash "$PS_HOOK" 2>/dev/null
) || true
# Empty output or valid JSON are both acceptable
if [[ -z "$smoke_output" ]] || echo "$smoke_output" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    pass "RCH-10: prompt-submit.sh runs without error on normal prompt"
else
    fail "RCH-10: prompt-submit.sh runs without error on normal prompt" "unexpected output: ${smoke_output:0:100}"
fi

echo ""

# ============================================================
# Summary
# ============================================================

TOTAL=$((PASS + FAIL))
echo "Results: $PASS/$TOTAL passed"
if [[ "$FAIL" -gt 0 ]]; then
    echo "FAIL: $FAIL test(s) failed"
    exit 1
fi
echo "All tests passed."
exit 0
