#!/usr/bin/env bash
# test-lifetime-persistence.sh — Tests for write_statusline_cache() lifetime token/cost persistence.
#
# Purpose: Verifies the fix for issue #160 — that write_statusline_cache() reads the
# existing cache's lifetime_tokens/lifetime_cost as fallback defaults so that callers
# that don't set LIFETIME_TOKENS/LIFETIME_COST don't overwrite the values with 0.
#
# @decision DEC-LIFETIME-PERSIST-001
# @title Test that write_statusline_cache preserves lifetime fields from previous cache
# @status accepted
# @rationale Bug: only session-init.sh sets LIFETIME_TOKENS before calling
# write_statusline_cache(). All other callers (prompt-submit.sh, check-*.sh) run in
# fresh processes where LIFETIME_TOKENS is unset, defaulting to 0 and overwriting the
# previously-good cache value. The fix reads the existing cache as a fallback — tested here.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_LIB="${SCRIPT_DIR}/../hooks/session-lib.sh"
SOURCE_LIB="${SCRIPT_DIR}/../hooks/source-lib.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

pass_test() { TESTS_PASSED=$(( TESTS_PASSED + 1 )); echo -e "${GREEN}✓${NC} $1"; }
fail_test() { TESTS_FAILED=$(( TESTS_FAILED + 1 )); echo -e "${RED}✗${NC} $1"; echo -e "  ${YELLOW}Details:${NC} $2"; }
run_test()  { TESTS_RUN=$(( TESTS_RUN + 1 )); }

# Cleanup trap
_CLEANUP_DIRS=()
trap '[[ ${#_CLEANUP_DIRS[@]} -gt 0 ]] && rm -rf "${_CLEANUP_DIRS[@]}" 2>/dev/null; true' EXIT

# Helper: invoke write_statusline_cache in a subprocess with controlled env
# Args: root_dir [KEY=VALUE ...] — additional KEY=VALUE pairs are exported into the subprocess
# When no KEY=VALUE pairs are given, LIFETIME_TOKENS and LIFETIME_COST are intentionally NOT set,
# simulating the behavior of prompt-submit.sh and other callers that don't set these globals.
run_write_cache() {
    local root="$1"
    shift
    # Build export lines from remaining args (may be empty)
    local export_lines=""
    while [[ $# -gt 0 ]]; do
        export_lines="${export_lines}export $1"$'\n'
        shift
    done

    # Run in a subshell with the session-lib sourced
    bash -c "
        export CLAUDE_SESSION_ID='test-persist-\$\$'
        ${export_lines}
        # Source the full hook chain: source-lib bootstraps core-lib, which loads session-lib
        source '${SOURCE_LIB}' 2>/dev/null || true
        require_session 2>/dev/null || true
        # Fallback: source directly if require_session didn't load it
        [[ \"\$(type -t write_statusline_cache)\" == 'function' ]] || source '${SESSION_LIB}'
        write_statusline_cache '${root}'
    " 2>/dev/null
    return $?
}

# Helper: read a field from the cache file
read_cache_field() {
    local root="$1" field="$2"
    local cache_file
    cache_file=$(ls "${root}/.claude/.statusline-cache-"* 2>/dev/null | head -1)
    [[ -z "$cache_file" || ! -f "$cache_file" ]] && echo "0" && return
    jq -r ".${field} // 0" "$cache_file" 2>/dev/null || echo "0"
}

# ============================================================================
# Test group 1: Lifetime token persistence
# ============================================================================

test_lifetime_tokens_preserved_when_caller_unset() {
    run_test
    # Write an initial cache WITH lifetime_tokens=1000000
    # Then call write_statusline_cache WITHOUT LIFETIME_TOKENS set
    # The cache should still have lifetime_tokens=1000000
    local tmpdir
    tmpdir=$(mktemp -d)
    _CLEANUP_DIRS+=("$tmpdir")
    mkdir -p "$tmpdir/.claude"

    # Step 1: write initial cache with LIFETIME_TOKENS=1000000
    run_write_cache "$tmpdir" "LIFETIME_TOKENS=1000000" "LIFETIME_COST=5.00"

    local before
    before=$(read_cache_field "$tmpdir" "lifetime_tokens")

    # Step 2: overwrite WITHOUT LIFETIME_TOKENS (simulates prompt-submit.sh call)
    run_write_cache "$tmpdir"  # no LIFETIME_TOKENS

    local after
    after=$(read_cache_field "$tmpdir" "lifetime_tokens")

    if [[ "$before" == "1000000" && "$after" == "1000000" ]]; then
        pass_test "lifetime_tokens preserved: cache retains 1000000 when caller doesn't set LIFETIME_TOKENS"
    else
        fail_test "lifetime_tokens NOT preserved" "before=$before after=$after (expected both=1000000)"
    fi
}

test_lifetime_tokens_overridden_when_caller_sets() {
    run_test
    # Write initial cache with lifetime_tokens=1000000
    # Then call write_statusline_cache WITH LIFETIME_TOKENS=2000000
    # Cache should update to 2000000
    local tmpdir
    tmpdir=$(mktemp -d)
    _CLEANUP_DIRS+=("$tmpdir")
    mkdir -p "$tmpdir/.claude"

    # Step 1: write initial cache
    run_write_cache "$tmpdir" "LIFETIME_TOKENS=1000000"

    # Step 2: write with explicit new value
    run_write_cache "$tmpdir" "LIFETIME_TOKENS=2000000"

    local after
    after=$(read_cache_field "$tmpdir" "lifetime_tokens")

    if [[ "$after" == "2000000" ]]; then
        pass_test "lifetime_tokens updated: caller-set LIFETIME_TOKENS=2000000 takes effect"
    else
        fail_test "lifetime_tokens NOT updated by caller" "after=$after (expected 2000000)"
    fi
}

test_lifetime_tokens_starts_at_zero_when_no_cache() {
    run_test
    # No existing cache → LIFETIME_TOKENS unset → defaults to 0
    local tmpdir
    tmpdir=$(mktemp -d)
    _CLEANUP_DIRS+=("$tmpdir")
    mkdir -p "$tmpdir/.claude"

    run_write_cache "$tmpdir"  # no LIFETIME_TOKENS, no existing cache

    local val
    val=$(read_cache_field "$tmpdir" "lifetime_tokens")

    if [[ "$val" == "0" ]]; then
        pass_test "lifetime_tokens=0 when no cache exists and LIFETIME_TOKENS unset"
    else
        fail_test "lifetime_tokens not 0 on fresh cache" "val=$val"
    fi
}

test_lifetime_cost_preserved_when_caller_unset() {
    run_test
    local tmpdir
    tmpdir=$(mktemp -d)
    _CLEANUP_DIRS+=("$tmpdir")
    mkdir -p "$tmpdir/.claude"

    # Step 1: write initial cache with LIFETIME_COST=12.50
    run_write_cache "$tmpdir" "LIFETIME_COST=12.50" "LIFETIME_TOKENS=500000"

    local before
    before=$(read_cache_field "$tmpdir" "lifetime_cost")

    # Step 2: overwrite WITHOUT LIFETIME_COST
    run_write_cache "$tmpdir"  # no LIFETIME_COST

    local after
    after=$(read_cache_field "$tmpdir" "lifetime_cost")

    if [[ "$before" == "12.5" || "$before" == "12.50" ]] && [[ "$after" == "12.5" || "$after" == "12.50" ]]; then
        pass_test "lifetime_cost preserved: cache retains 12.50 when caller doesn't set LIFETIME_COST"
    else
        fail_test "lifetime_cost NOT preserved" "before=$before after=$after (expected both=12.5)"
    fi
}

test_lifetime_cost_overridden_when_caller_sets() {
    run_test
    local tmpdir
    tmpdir=$(mktemp -d)
    _CLEANUP_DIRS+=("$tmpdir")
    mkdir -p "$tmpdir/.claude"

    run_write_cache "$tmpdir" "LIFETIME_COST=5.00"
    run_write_cache "$tmpdir" "LIFETIME_COST=25.00"

    local after
    after=$(read_cache_field "$tmpdir" "lifetime_cost")

    if [[ "$after" == "25" || "$after" == "25.0" || "$after" == "25.00" ]]; then
        pass_test "lifetime_cost updated: caller-set LIFETIME_COST=25.00 takes effect"
    else
        fail_test "lifetime_cost NOT updated by caller" "after=$after (expected 25.00)"
    fi
}

test_multiple_overwrites_preserve_tokens() {
    run_test
    # Simulate the real scenario: session-init sets it, then 5 prompt-submit calls overwrite
    local tmpdir
    tmpdir=$(mktemp -d)
    _CLEANUP_DIRS+=("$tmpdir")
    mkdir -p "$tmpdir/.claude"

    # session-init sets lifetime_tokens
    run_write_cache "$tmpdir" "LIFETIME_TOKENS=3000000" "LIFETIME_COST=15.00"

    # 5 subsequent prompt-submit calls without LIFETIME_TOKENS
    run_write_cache "$tmpdir"
    run_write_cache "$tmpdir"
    run_write_cache "$tmpdir"
    run_write_cache "$tmpdir"
    run_write_cache "$tmpdir"

    local final
    final=$(read_cache_field "$tmpdir" "lifetime_tokens")

    if [[ "$final" == "3000000" ]]; then
        pass_test "lifetime_tokens survives 5 subsequent overwrites without LIFETIME_TOKENS set"
    else
        fail_test "lifetime_tokens overwritten by subsequent callers" "final=$final (expected 3000000)"
    fi
}

# ============================================================================
# Run all tests
# ============================================================================

echo "Running write_statusline_cache lifetime persistence tests..."
echo ""

echo "--- Lifetime token preservation (issue #160) ---"
test_lifetime_tokens_preserved_when_caller_unset
test_lifetime_tokens_overridden_when_caller_sets
test_lifetime_tokens_starts_at_zero_when_no_cache
test_lifetime_cost_preserved_when_caller_unset
test_lifetime_cost_overridden_when_caller_sets
test_multiple_overwrites_preserve_tokens

echo ""
echo "========================================="
echo "Test Results:"
echo "  Total:  $TESTS_RUN"
echo -e "  ${GREEN}Passed: $TESTS_PASSED${NC}"
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "  ${RED}Failed: $TESTS_FAILED${NC}"
else
    echo "  Failed: 0"
fi
echo "========================================="

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi
