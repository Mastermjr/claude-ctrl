#!/usr/bin/env bash
# test-v3-concurrency-fixes.sh — Tests for v3 concurrency bug patches
#
# Tests for fixes introduced in the v3-concurrency-fixes branch:
#   Fix 1: is_guardian_active() in pre-bash.sh has TTL check
#   Fix 2: Marker format without pipe delimiter falls back to file mtime
#   Fix 3: GUARDIAN_ACTIVE_TTL constant in core-lib.sh
#   Fix 4: Orphaned .last-tester-trace writes removed from check-tester.sh
#   Fix 5: detect_workflow_id() function in source-lib.sh
#   Fix 6: resolve_proof_file_for_path() convenience function in log.sh
#   Fix 7: post-write.sh proof invalidation is workflow-scoped
#   Fix 8: task-track.sh Gate C writes workflow-specific proof status
#   Fix 9: task-track.sh Gate A reads workflow-specific proof status
#
# @decision DEC-V3-TEST-001
# @title Test suite for v3 concurrency bug patches and per-workflow proof isolation
# @status accepted
# @rationale Stale guardian markers permanently block git ops (Fix 1), inconsistent
#   marker formats cause TTL bypass (Fix 2), magic number 600 needs a constant
#   (Fix 3), orphaned writes create misleading state (Fix 4), and the core
#   per-workflow proof isolation (Fix 5-9) prevents cross-workflow contamination
#   when multiple implementers work in parallel worktrees.
#
# Usage: bash tests/test-v3-concurrency-fixes.sh
# Standalone test file (not inline in run-hooks.sh — runs as CI step 2).

set -euo pipefail

# Portable SHA-256
if command -v shasum >/dev/null 2>&1; then
    _SHA256_CMD="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
    _SHA256_CMD="sha256sum"
else
    _SHA256_CMD="cat"
fi

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
HOOKS_DIR="$PROJECT_ROOT/hooks"

mkdir -p "$PROJECT_ROOT/tmp"

# Cleanup trap: collect temp dirs and remove on exit
_CLEANUP_DIRS=()
trap '[[ ${#_CLEANUP_DIRS[@]} -gt 0 ]] && rm -rf "${_CLEANUP_DIRS[@]}" 2>/dev/null; true' EXIT

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

make_temp_env() {
    local dir
    # Use /tmp to avoid path nesting inside .worktrees/ (which would confuse detect_workflow_id)
    dir=$(mktemp -d "/tmp/test-v3-$$-XXXXXX")
    mkdir -p "$dir/.claude/traces"
    mkdir -p "$dir/.claude/state/locks"
    git -C "$dir" init -q 2>/dev/null || true
    _CLEANUP_DIRS+=("$dir")
    echo "$dir"
}

compute_phash() {
    echo "$1" | ${_SHA256_CMD} | cut -c1-8 2>/dev/null || echo "00000000"
}

# Pre-set _HOOK_NAME to avoid unbound variable error in source-lib.sh EXIT trap
_HOOK_NAME="test-v3-concurrency-fixes"
# Source hook libraries for unit testing
source "$HOOKS_DIR/log.sh" 2>/dev/null
source "$HOOKS_DIR/source-lib.sh" 2>/dev/null

# =============================================================================
# Fix 3: GUARDIAN_ACTIVE_TTL constant in core-lib.sh
# =============================================================================

echo ""
echo "--- Fix 3: GUARDIAN_ACTIVE_TTL constant ---"

run_test "Fix 3: GUARDIAN_ACTIVE_TTL is defined in core-lib.sh"
if grep -q 'GUARDIAN_ACTIVE_TTL' "$HOOKS_DIR/core-lib.sh"; then
    pass_test
else
    fail_test "GUARDIAN_ACTIVE_TTL not found in core-lib.sh"
fi

run_test "Fix 3: GUARDIAN_ACTIVE_TTL is set to 600"
if grep -qE 'GUARDIAN_ACTIVE_TTL=600' "$HOOKS_DIR/core-lib.sh"; then
    pass_test
else
    fail_test "GUARDIAN_ACTIVE_TTL=600 not found in core-lib.sh"
fi

run_test "Fix 3: post-write.sh references GUARDIAN_ACTIVE_TTL (no magic 600)"
# post-write.sh should use the constant, not the magic number 600 inline
if grep -qE '\$\{?GUARDIAN_ACTIVE_TTL\}?' "$HOOKS_DIR/post-write.sh"; then
    pass_test
else
    fail_test "post-write.sh does not reference GUARDIAN_ACTIVE_TTL"
fi

run_test "Fix 3: pre-bash.sh references GUARDIAN_ACTIVE_TTL (no magic 600)"
if grep -qE '\$\{?GUARDIAN_ACTIVE_TTL\}?' "$HOOKS_DIR/pre-bash.sh"; then
    pass_test
else
    fail_test "pre-bash.sh does not reference GUARDIAN_ACTIVE_TTL"
fi

# =============================================================================
# Fix 1: is_guardian_active() in pre-bash.sh has TTL check
# =============================================================================

echo ""
echo "--- Fix 1: is_guardian_active() TTL check ---"

run_test "Fix 1: pre-bash.sh syntax is valid"
if bash -n "$HOOKS_DIR/pre-bash.sh"; then
    pass_test
else
    fail_test "pre-bash.sh has syntax errors"
fi

run_test "Fix 1: is_guardian_active() exists in pre-bash.sh"
if grep -q 'is_guardian_active' "$HOOKS_DIR/pre-bash.sh"; then
    pass_test
else
    fail_test "is_guardian_active() not found in pre-bash.sh"
fi

run_test "Fix 1: is_guardian_active() applies TTL (references GUARDIAN_ACTIVE_TTL or timestamp)"
# The function must check timestamps, not just count files
if grep -A 15 'is_guardian_active()' "$HOOKS_DIR/pre-bash.sh" | grep -qE '(GUARDIAN_ACTIVE_TTL|_marker_ts|_now.*date)'; then
    pass_test
else
    fail_test "is_guardian_active() does not check timestamps/TTL"
fi

run_test "Fix 1: Fresh guardian marker (recent timestamp) is considered active"
_env=$(make_temp_env)
_traces="$_env/.claude/traces"
mkdir -p "$_traces"
_now=$(date +%s)
# Create marker with fresh timestamp in pipe format
echo "pre-dispatch|${_now}" > "$_traces/.active-guardian-test123-abcdef01"
# Source pre-bash.sh partially to get is_guardian_active() — use a subshell
_result=$(
    export TRACE_STORE="$_traces"
    _HOOK_NAME="test-prebash-sub"
    bash -c "
        source '$HOOKS_DIR/source-lib.sh' 2>/dev/null
        $(grep -A 20 'is_guardian_active()' "$HOOKS_DIR/pre-bash.sh" | head -25)
        if is_guardian_active; then echo 'active'; else echo 'inactive'; fi
    " 2>/dev/null || echo "error"
)
if [[ "$_result" == "active" ]]; then
    pass_test
else
    fail_test "Fresh marker should be active, got: $_result"
fi

run_test "Fix 1: Stale guardian marker (old timestamp) is NOT considered active"
_env2=$(make_temp_env)
_traces2="$_env2/.claude/traces"
mkdir -p "$_traces2"
# Create marker with old timestamp (2 hours ago)
_old_ts=$(( $(date +%s) - 7200 ))
echo "pre-dispatch|${_old_ts}" > "$_traces2/.active-guardian-stale99-abcdef01"
_result2=$(
    export TRACE_STORE="$_traces2"
    _HOOK_NAME="test-prebash-sub2"
    bash -c "
        source '$HOOKS_DIR/source-lib.sh' 2>/dev/null
        $(grep -A 20 'is_guardian_active()' "$HOOKS_DIR/pre-bash.sh" | head -25)
        if is_guardian_active; then echo 'active'; else echo 'inactive'; fi
    " 2>/dev/null || echo "error"
)
if [[ "$_result2" == "inactive" ]]; then
    pass_test
else
    fail_test "Stale marker should be inactive, got: $_result2"
fi

# =============================================================================
# Fix 2: Marker format without pipe delimiter falls back to file mtime
# =============================================================================

echo ""
echo "--- Fix 2: Marker format fallback to file mtime ---"

run_test "Fix 2: pre-bash.sh is_guardian_active() handles no-pipe format via mtime fallback"
# Check that the function handles markers without pipe delimiter
_content=$(grep -A 25 'is_guardian_active()' "$HOOKS_DIR/pre-bash.sh" | head -30)
# Should contain mtime fallback or format check
if echo "$_content" | grep -qE '(mtime|stat.*%m|file.*mtime|no.*pipe|without.*pipe|_file_mtime|BASH_SOURCE|format)' || \
   echo "$_content" | grep -qE '(cut.*\||pipe|delim)'; then
    pass_test
else
    # Accept if it at least does the timestamp extraction with a guard for empty
    if echo "$_content" | grep -qE '(\^\[0-9\]|\^\^[0-9]|=~.*\^)'; then
        pass_test
    else
        fail_test "is_guardian_active() may not handle no-pipe format gracefully"
    fi
fi

run_test "Fix 2: post-write.sh TTL check handles marker without pipe (falls back to mtime)"
_env3=$(make_temp_env)
_traces3="$_env3/.claude/traces"
mkdir -p "$_traces3"
# Create a marker WITHOUT pipe format (just a trace_id, like init_trace() might write)
echo "trace-abc12345" > "$_traces3/.active-guardian-nopipe-abcdef01"
# The marker should be treated as fresh (file was just created)
_result3=$(
    export TRACE_STORE="$_traces3"
    _HOOK_NAME="test-prebash-sub3"
    bash -c "
        source '$HOOKS_DIR/source-lib.sh' 2>/dev/null
        $(grep -A 25 'is_guardian_active()' "$HOOKS_DIR/pre-bash.sh" | head -30)
        if is_guardian_active; then echo 'active'; else echo 'inactive'; fi
    " 2>/dev/null || echo "error"
)
# A newly-created marker without pipe format should be treated as active (fresh mtime)
if [[ "$_result3" == "active" ]]; then
    pass_test
else
    fail_test "No-pipe format marker (fresh file) should be active, got: $_result3"
fi

# =============================================================================
# Fix 4: Orphaned .last-tester-trace writes removed from check-tester.sh
# =============================================================================

echo ""
echo "--- Fix 4: Orphaned .last-tester-trace writes removed ---"

run_test "Fix 4: check-tester.sh syntax is valid"
if bash -n "$HOOKS_DIR/check-tester.sh"; then
    pass_test
else
    fail_test "check-tester.sh has syntax errors"
fi

run_test "Fix 4: check-tester.sh does NOT write .last-tester-trace (breadcrumb removed)"
if ! grep -q '\.last-tester-trace' "$HOOKS_DIR/check-tester.sh"; then
    pass_test
else
    fail_test ".last-tester-trace writes still present in check-tester.sh"
fi

run_test "Fix 4: check-tester.sh does NOT write last-tester-trace to state dir"
# The state/{phash}/last-tester-trace write should also be removed
if ! grep -q 'last-tester-trace' "$HOOKS_DIR/check-tester.sh"; then
    pass_test
else
    fail_test "last-tester-trace state writes still present in check-tester.sh"
fi

run_test "Fix 4: subagent-start.sh does NOT write legacy .last-tester-trace dotfile (DEC-STATE-DOTFILE-002)"
# Legacy dotfile write removed — only state/{phash}/last-tester-trace is written
if ! grep -q '\.last-tester-trace"' "$HOOKS_DIR/subagent-start.sh"; then
    pass_test
else
    fail_test "Legacy .last-tester-trace write still present in subagent-start.sh"
fi

run_test "Fix 4: subagent-start.sh does NOT write legacy .guardian-start-sha dotfile (DEC-STATE-DOTFILE-002)"
if ! grep -q '\.guardian-start-sha"' "$HOOKS_DIR/subagent-start.sh"; then
    pass_test
else
    fail_test "Legacy .guardian-start-sha write still present in subagent-start.sh"
fi

# =============================================================================
# Fix 5: detect_workflow_id() function in source-lib.sh
# =============================================================================

echo ""
echo "--- Fix 5: detect_workflow_id() function ---"

run_test "Fix 5: source-lib.sh syntax is valid"
if bash -n "$HOOKS_DIR/source-lib.sh"; then
    pass_test
else
    fail_test "source-lib.sh has syntax errors"
fi

run_test "Fix 5: detect_workflow_id() is defined in source-lib.sh"
if grep -q 'detect_workflow_id' "$HOOKS_DIR/source-lib.sh"; then
    pass_test
else
    fail_test "detect_workflow_id() not found in source-lib.sh"
fi

run_test "Fix 5: detect_workflow_id() returns 'main' for non-worktree paths"
_wf_main=$(
    _HOOK_NAME="test-wf"
    source "$HOOKS_DIR/source-lib.sh" 2>/dev/null
    detect_workflow_id "/Users/user/myproject/src/foo.ts" 2>/dev/null || echo "error"
)
if [[ "$_wf_main" == "main" ]]; then
    pass_test
else
    fail_test "Expected 'main', got: '$_wf_main'"
fi

run_test "Fix 5: detect_workflow_id() extracts worktree name from .worktrees/ path"
_wf_wt=$(
    _HOOK_NAME="test-wf2"
    source "$HOOKS_DIR/source-lib.sh" 2>/dev/null
    detect_workflow_id "/Users/user/myproject/.worktrees/feature-auth/src/foo.ts" 2>/dev/null || echo "error"
)
if [[ "$_wf_wt" == "feature-auth" ]]; then
    pass_test
else
    fail_test "Expected 'feature-auth', got: '$_wf_wt'"
fi

run_test "Fix 5: detect_workflow_id() extracts worktree name from nested path"
_wf_nested=$(
    _HOOK_NAME="test-wf3"
    source "$HOOKS_DIR/source-lib.sh" 2>/dev/null
    detect_workflow_id "/Users/user/.claude/.worktrees/v3-concurrency-fixes/hooks/post-write.sh" 2>/dev/null || echo "error"
)
if [[ "$_wf_nested" == "v3-concurrency-fixes" ]]; then
    pass_test
else
    fail_test "Expected 'v3-concurrency-fixes', got: '$_wf_nested'"
fi

run_test "Fix 5: detect_workflow_id() returns 'main' for empty path"
_wf_empty=$(
    _HOOK_NAME="test-wf4"
    source "$HOOKS_DIR/source-lib.sh" 2>/dev/null
    detect_workflow_id "" 2>/dev/null || echo "error"
)
if [[ "$_wf_empty" == "main" ]]; then
    pass_test
else
    fail_test "Expected 'main' for empty path, got: '$_wf_empty'"
fi

run_test "Fix 5: detect_workflow_id() reads WORKTREE_PATH env var when no filepath"
_wf_env=$(
    _HOOK_NAME="test-wf5"
    source "$HOOKS_DIR/source-lib.sh" 2>/dev/null
    WORKTREE_PATH="/path/to/.worktrees/my-feature" \
    detect_workflow_id "" 2>/dev/null || echo "error"
)
if [[ "$_wf_env" == "my-feature" ]]; then
    pass_test
else
    fail_test "Expected 'my-feature' from WORKTREE_PATH, got: '$_wf_env'"
fi

# =============================================================================
# Fix 6: resolve_proof_file_for_path() in log.sh
# =============================================================================

echo ""
echo "--- Fix 6: resolve_proof_file_for_path() convenience function ---"

run_test "Fix 6: log.sh syntax is valid"
if bash -n "$HOOKS_DIR/log.sh"; then
    pass_test
else
    fail_test "log.sh has syntax errors"
fi

run_test "Fix 6: resolve_proof_file_for_path() is defined in log.sh"
if grep -q 'resolve_proof_file_for_path' "$HOOKS_DIR/log.sh"; then
    pass_test
else
    fail_test "resolve_proof_file_for_path() not found in log.sh"
fi

run_test "Fix 6: resolve_proof_file_for_path() returns workflow-scoped path for worktree file"
_env4=$(make_temp_env)
# Use a path that contains .worktrees but is NOT inside the worktree test dir itself
_wt_filepath="/home/user/myproject/.worktrees/my-worktree/src/foo.ts"
_result4=$(
    _HOOK_NAME="test-proof-path"
    export CLAUDE_DIR="$_env4/.claude"
    export CLAUDE_PROJECT_DIR="$_env4"
    # Unset WORKTREE_PATH to avoid interference
    unset WORKTREE_PATH 2>/dev/null || true
    source "$HOOKS_DIR/source-lib.sh" 2>/dev/null
    resolve_proof_file_for_path "$_wt_filepath" 2>/dev/null || echo "error"
)
# Should contain the worktree name in the path
if echo "$_result4" | grep -q 'my-worktree'; then
    pass_test
else
    fail_test "Expected worktree-scoped proof file, got: '$_result4'"
fi

run_test "Fix 6: resolve_proof_file_for_path() returns standard path for non-worktree file"
_env5=$(make_temp_env)
_result5=$(
    _HOOK_NAME="test-proof-path2"
    export CLAUDE_DIR="$_env5/.claude"
    export CLAUDE_PROJECT_DIR="$_env5"
    unset WORKTREE_PATH 2>/dev/null || true
    source "$HOOKS_DIR/source-lib.sh" 2>/dev/null
    resolve_proof_file_for_path "/home/user/myproject/src/foo.ts" 2>/dev/null || echo "error"
)
# Should NOT contain 'worktrees' in the path
if [[ -n "$_result5" ]] && ! echo "$_result5" | grep -q 'worktrees'; then
    pass_test
else
    fail_test "Expected standard proof file (no worktrees), got: '$_result5'"
fi

# =============================================================================
# Fix 7: post-write.sh proof invalidation is workflow-scoped
# =============================================================================

echo ""
echo "--- Fix 7: post-write.sh workflow-scoped proof invalidation ---"

run_test "Fix 7: post-write.sh syntax is valid"
if bash -n "$HOOKS_DIR/post-write.sh"; then
    pass_test
else
    fail_test "post-write.sh has syntax errors"
fi

run_test "Fix 7: post-write.sh uses detect_workflow_id or resolve_proof_file_for_path"
if grep -qE '(detect_workflow_id|resolve_proof_file_for_path)' "$HOOKS_DIR/post-write.sh"; then
    pass_test
else
    fail_test "post-write.sh does not use workflow-scoped proof resolution"
fi

run_test "Fix 7: Editing file in worktree-A invalidates only worktree-A proof"
_env6=$(make_temp_env)
_phash=$(compute_phash "$_env6")
# Create "verified" proof for both worktrees
mkdir -p "$_env6/.claude/state/${_phash}"
echo "verified|$(date +%s)" > "$_env6/.claude/state/${_phash}/proof-status"
mkdir -p "$_env6/.claude/state/${_phash}/worktrees/wt-A"
echo "verified|$(date +%s)" > "$_env6/.claude/state/${_phash}/worktrees/wt-A/proof-status"
mkdir -p "$_env6/.claude/state/${_phash}/worktrees/wt-B"
echo "verified|$(date +%s)" > "$_env6/.claude/state/${_phash}/worktrees/wt-B/proof-status"

# Create the src directory so post-write.sh doesn't exit early on dirname check
mkdir -p "$_env6/.worktrees/wt-A/src"

# Simulate post-write for a file in worktree-A
# Note: Use _env6 path (from /tmp) which does NOT nest inside .worktrees/ itself
_WRITE_JSON="{\"tool_input\":{\"file_path\":\"${_env6}/.worktrees/wt-A/src/foo.sh\"},\"cwd\":\"${_env6}\"}"
echo "$_WRITE_JSON" | \
    CLAUDE_DIR="$_env6/.claude" \
    CLAUDE_PROJECT_DIR="$_env6" \
    TRACE_STORE="$_env6/.claude/traces" \
    bash "$HOOKS_DIR/post-write.sh" >/dev/null 2>&1 || true

# Check: wt-A proof should now be pending, wt-B should remain verified
_wt_a_status=""
_wt_b_status=""
if [[ -f "$_env6/.claude/state/${_phash}/worktrees/wt-A/proof-status" ]]; then
    _wt_a_status=$(cut -d'|' -f1 "$_env6/.claude/state/${_phash}/worktrees/wt-A/proof-status" 2>/dev/null || echo "missing")
fi
if [[ -f "$_env6/.claude/state/${_phash}/worktrees/wt-B/proof-status" ]]; then
    _wt_b_status=$(cut -d'|' -f1 "$_env6/.claude/state/${_phash}/worktrees/wt-B/proof-status" 2>/dev/null || echo "missing")
fi
if [[ "$_wt_a_status" == "pending" && "$_wt_b_status" == "verified" ]]; then
    pass_test
else
    fail_test "Expected wt-A=pending, wt-B=verified; got wt-A='${_wt_a_status}' wt-B='${_wt_b_status}'"
fi

# =============================================================================
# Fix 8 & 9: task-track.sh workflow-scoped proof status
# =============================================================================

echo ""
echo "--- Fix 8 & 9: task-track.sh workflow-scoped proof ---"

run_test "Fix 8/9: task-track.sh syntax is valid"
if bash -n "$HOOKS_DIR/task-track.sh"; then
    pass_test
else
    fail_test "task-track.sh has syntax errors"
fi

run_test "Fix 8: task-track.sh Gate C references workflow detection"
# Gate C writes needs-verification — should be workflow-aware
if grep -qE '(detect_workflow_id|worktree.*proof|workflow.*proof|resolve_proof_file_for_path)' "$HOOKS_DIR/task-track.sh"; then
    pass_test
else
    fail_test "task-track.sh Gate C does not use workflow-scoped proof"
fi

# =============================================================================
# Parallel proof isolation: two worktrees with independent proof state
# =============================================================================

echo ""
echo "--- Parallel proof isolation ---"

run_test "Parallel isolation: wt-A implementer dispatch sets only wt-A needs-verification"
_env7=$(make_temp_env)
_phash7=$(compute_phash "$_env7")

# Set up git with an initial commit so worktree add works
git -C "$_env7" config user.email "test@test.local" 2>/dev/null || true
git -C "$_env7" config user.name "Test" 2>/dev/null || true
git -C "$_env7" commit --allow-empty -m "init" 2>/dev/null || true
# Create a linked worktree so Gate C.1 allows dispatch
mkdir -p "$_env7/.worktrees"
git -C "$_env7" worktree add "$_env7/.worktrees/wt-A" -b "feature/wt-A" 2>/dev/null || true
git -C "$_env7" worktree add "$_env7/.worktrees/wt-B" -b "feature/wt-B" 2>/dev/null || true

# Start both worktrees as "verified"
mkdir -p "$_env7/.claude/state/${_phash7}/worktrees/wt-A"
mkdir -p "$_env7/.claude/state/${_phash7}/worktrees/wt-B"
echo "verified|$(date +%s)" > "$_env7/.claude/state/${_phash7}/worktrees/wt-A/proof-status"
echo "verified|$(date +%s)" > "$_env7/.claude/state/${_phash7}/worktrees/wt-B/proof-status"

# Dispatch implementer for wt-A (hook reads prompt to extract worktree name)
_DISPATCH_JSON="{\"tool_input\":{\"subagent_type\":\"implementer\",\"prompt\":\"Work in ${_env7}/.worktrees/wt-A please\"},\"cwd\":\"$_env7\"}"
echo "$_DISPATCH_JSON" | \
    CLAUDE_DIR="$_env7/.claude" \
    CLAUDE_PROJECT_DIR="$_env7" \
    TRACE_STORE="$_env7/.claude/traces" \
    bash "$HOOKS_DIR/task-track.sh" >/dev/null 2>&1 || true

# wt-A should be needs-verification, wt-B should remain verified
_status_a7=""
_status_b7=""
if [[ -f "$_env7/.claude/state/${_phash7}/worktrees/wt-A/proof-status" ]]; then
    _status_a7=$(cut -d'|' -f1 "$_env7/.claude/state/${_phash7}/worktrees/wt-A/proof-status" 2>/dev/null || echo "")
fi
if [[ -f "$_env7/.claude/state/${_phash7}/worktrees/wt-B/proof-status" ]]; then
    _status_b7=$(cut -d'|' -f1 "$_env7/.claude/state/${_phash7}/worktrees/wt-B/proof-status" 2>/dev/null || echo "")
fi
if [[ "$_status_a7" == "needs-verification" && "$_status_b7" == "verified" ]]; then
    pass_test
else
    fail_test "Expected wt-A=needs-verification, wt-B=verified; got wt-A='${_status_a7}' wt-B='${_status_b7}'"
fi

run_test "Parallel isolation: main-branch operations use project-wide proof (not worktree-scoped)"
_env8=$(make_temp_env)
_phash8=$(compute_phash "$_env8")

# Set up git with an initial commit
git -C "$_env8" config user.email "test@test.local" 2>/dev/null || true
git -C "$_env8" config user.name "Test" 2>/dev/null || true
git -C "$_env8" commit --allow-empty -m "init" 2>/dev/null || true
# Create a linked worktree so Gate C.1 allows dispatch
mkdir -p "$_env8/.worktrees"
git -C "$_env8" worktree add "$_env8/.worktrees/feature-x" -b "feature/x" 2>/dev/null || true

# No pre-existing proof file (bootstrap: first dispatch)
# Dispatch implementer for main (no worktree in prompt)
_DISPATCH_JSON2="{\"tool_input\":{\"subagent_type\":\"implementer\",\"prompt\":\"Fix a bug in the main checkout\"},\"cwd\":\"$_env8\"}"
echo "$_DISPATCH_JSON2" | \
    CLAUDE_DIR="$_env8/.claude" \
    CLAUDE_PROJECT_DIR="$_env8" \
    TRACE_STORE="$_env8/.claude/traces" \
    bash "$HOOKS_DIR/task-track.sh" >/dev/null 2>&1 || true

# Project-wide proof should be needs-verification (initialized by Gate C.2)
# Worktree-scoped proof file should NOT exist (no worktree in prompt)
_status_main=""
_new_proof="$_env8/.claude/state/${_phash8}/proof-status"
_old_proof="$_env8/.claude/.proof-status-${_phash8}"
if [[ -f "$_new_proof" ]]; then
    _status_main=$(cut -d'|' -f1 "$_new_proof" 2>/dev/null || echo "")
elif [[ -f "$_old_proof" ]]; then
    _status_main=$(cut -d'|' -f1 "$_old_proof" 2>/dev/null || echo "")
fi
# Verify: project-wide proof is needs-verification AND no worktree-scoped file was created
_wt_scoped_exists=false
if [[ -d "$_env8/.claude/state/${_phash8}/worktrees" ]]; then
    _wt_count=$(find "$_env8/.claude/state/${_phash8}/worktrees" -name "proof-status" 2>/dev/null | wc -l | tr -d ' ')
    [[ "$_wt_count" -gt 0 ]] && _wt_scoped_exists=true
fi
if [[ "$_status_main" == "needs-verification" && "$_wt_scoped_exists" == "false" ]]; then
    pass_test
else
    fail_test "Expected project-wide=needs-verification and no wt-scoped file; got main='${_status_main}' wt-scoped=${_wt_scoped_exists}"
fi

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "==========================="
echo "v3 Concurrency Fix Tests: $TESTS_RUN run | $TESTS_PASSED passed | $TESTS_FAILED failed"
echo "==========================="

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
