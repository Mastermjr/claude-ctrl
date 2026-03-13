#!/usr/bin/env bash
# Test proof-status gate bootstrapping and state machine
#
# @decision DEC-TEST-PROOF-GATE-001
# @title Proof-status gate bootstrapping test suite
# @status accepted
# @rationale Tests the proof-status gate state machine which prevents commits
#   without verification while avoiding bootstrap deadlock. Validates that
#   missing .proof-status allows commits (bootstrap path), implementer dispatch
#   activates the gate, and only verified status allows Guardian dispatch.
#   Also validates the guard.sh Check 10 which blocks deletion of active gates.

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

# Cleanup trap (DEC-PROD-002): collect temp dirs and remove on exit
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
    echo "  ✓ PASS"
}

fail_test() {
    local reason="$1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  ✗ FAIL: $reason"
}

# --- Test 1: Syntax validation ---
run_test "Syntax: guard.sh is valid bash"
if bash -n "$HOOKS_DIR/pre-bash.sh"; then
    pass_test
else
    fail_test "guard.sh has syntax errors"
fi

run_test "Syntax: task-track.sh is valid bash"
if bash -n "$HOOKS_DIR/task-track.sh"; then
    pass_test
else
    fail_test "task-track.sh has syntax errors"
fi

# --- Test 2-9: task-track.sh Gate A (Guardian dispatch) ---
# These tests validate the Guardian gate behavior in task-track.sh

# Helper to run task-track.sh with mock input
# Gate A now reads proof state via proof_state_get() (SQLite sole authority since W5-2).
# We seed the SQLite DB via proof_state_set() with PROJECT_ROOT pointing to the temp repo.
# The flat-file path is no longer relevant to Gate A.
run_task_track() {
    local agent_type="$1"
    local proof_file="$2"  # Proof-status content (pipe-delimited) or "missing"

    # Create a temp git repo (not meta-repo)
    local TEMP_REPO
    TEMP_REPO=$(mktemp -d "$PROJECT_ROOT/tmp/test-pg-repo-XXXXXX")
    _CLEANUP_DIRS+=("$TEMP_REPO")
    git -C "$TEMP_REPO" init > /dev/null 2>&1
    mkdir -p "$TEMP_REPO/.claude"

    # Seed SQLite proof_state table if not "missing".
    # proof_state_get() queries SQLite; flat-file writes are not read by Gate A.
    if [[ "$proof_file" != "missing" ]]; then
        local proof_status
        proof_status=$(echo "$proof_file" | cut -d'|' -f1)
        # Use proof_state_set to write through the same path task-track.sh reads.
        # Source the state-lib directly (same hooks dir) with isolated PROJECT_ROOT.
        PROJECT_ROOT="$TEMP_REPO" CLAUDE_DIR="$TEMP_REPO/.claude" \
            bash -c "source '${HOOKS_DIR}/source-lib.sh'; require_state; proof_state_set '${proof_status}' 'test-setup'" 2>/dev/null || true
    fi

    # Mock input JSON
    local INPUT_JSON
    INPUT_JSON=$(cat <<EOF
{
  "tool_name": "Agent",
  "tool_input": {
    "subagent_type": "$agent_type",
    "instructions": "Test task"
  }
}
EOF
)

    # Run hook with mocked environment.
    # CLAUDE_PROJECT_DIR / PROJECT_ROOT scoped to temp repo so proof_state_get()
    # reads from the isolated SQLite DB, not ~/.claude real state.
    local OUTPUT
    OUTPUT=$(cd "$TEMP_REPO" && \
             echo "$INPUT_JSON" | CLAUDE_PROJECT_DIR="$TEMP_REPO" CLAUDE_DIR="$TEMP_REPO/.claude" bash "$HOOKS_DIR/task-track.sh" 2>&1)
    local EXIT_CODE=$?

    # Return output and exit code
    echo "$OUTPUT"
    return $EXIT_CODE
}

run_test "Gate A: Missing .proof-status allows Guardian dispatch (bootstrap)"
OUTPUT=$(run_task_track "guardian" "missing" 2>&1) || true
if echo "$OUTPUT" | grep -q "deny"; then
    fail_test "Guardian blocked when .proof-status missing (should allow)"
else
    pass_test
fi

run_test "Gate A: needs-verification blocks Guardian dispatch"
OUTPUT=$(run_task_track "guardian" "needs-verification|12345" 2>&1) || true
if echo "$OUTPUT" | grep -q "deny" && echo "$OUTPUT" | grep -q "needs-verification"; then
    pass_test
else
    fail_test "Guardian allowed with needs-verification status"
fi

run_test "Gate A: pending blocks Guardian dispatch"
OUTPUT=$(run_task_track "guardian" "pending|12345" 2>&1) || true
if echo "$OUTPUT" | grep -q "deny" && echo "$OUTPUT" | grep -q "pending"; then
    pass_test
else
    fail_test "Guardian allowed with pending status"
fi

run_test "Gate A: verified allows Guardian dispatch"
SECONDS=0
OUTPUT=$(run_task_track "guardian" "verified|12345" 2>&1) || true
ELAPSED=$SECONDS
if echo "$OUTPUT" | grep -q "deny"; then
    fail_test "Guardian blocked with verified status (should allow)"
elif [[ "$ELAPSED" -gt 10 ]]; then
    fail_test "Took ${ELAPSED}s (>10s) — likely FD leak from background heartbeat (see DEC-GUARDIAN-HEARTBEAT-002)"
else
    pass_test
fi

# --- Test 10: task-track.sh Gate C (Implementer activation) ---
# Gate C writes to state/{phash}/proof-status (new canonical path via write_proof_status()).
# Set CLAUDE_DIR to isolated dir so writes go to test env, not real ~/.claude.
run_test "Gate C: Implementer dispatch creates needs-verification"
TEMP_REPO=$(mktemp -d "$PROJECT_ROOT/tmp/test-pg-impl-XXXXXX")
_CLEANUP_DIRS+=("$TEMP_REPO")
git -C "$TEMP_REPO" init > /dev/null 2>&1
mkdir -p "$TEMP_REPO/.claude"
IMPL_PHASH=$(echo "$TEMP_REPO" | $_SHA256_CMD | cut -c1-8)
# Gate C.1 requires at least one linked worktree (enforces worktree isolation).
# Without this, task-track.sh denies implementer dispatch before Gate C.2 writes .proof-status.
IMPL_WORKTREE="$TEMP_REPO/.worktrees/feature-test"
mkdir -p "$IMPL_WORKTREE"
git -C "$TEMP_REPO" worktree add "$IMPL_WORKTREE" -b feature/test > /dev/null 2>&1 || \
    git -C "$TEMP_REPO" worktree add --detach "$IMPL_WORKTREE" > /dev/null 2>&1 || true

INPUT_JSON=$(cat <<'EOF'
{
  "tool_name": "Agent",
  "tool_input": {
    "subagent_type": "implementer",
    "instructions": "Test implementation"
  }
}
EOF
)

echo "$INPUT_JSON" | CLAUDE_PROJECT_DIR="$TEMP_REPO" CLAUDE_DIR="$TEMP_REPO/.claude" bash "$HOOKS_DIR/task-track.sh" > /dev/null 2>&1

# Gate C.2 writes proof state to SQLite (sole authority since W5-2).
# Query via proof_state_get with PROJECT_ROOT scoped to the temp repo.
_IMPL_SQLITE_STATUS=$(PROJECT_ROOT="$TEMP_REPO" CLAUDE_DIR="$TEMP_REPO/.claude" \
    bash -c "source '${HOOKS_DIR}/source-lib.sh'; require_state; proof_state_get 2>/dev/null | cut -d'|' -f1" 2>/dev/null || echo "")
if [[ "$_IMPL_SQLITE_STATUS" == "needs-verification" ]]; then
    pass_test
elif [[ -n "$_IMPL_SQLITE_STATUS" ]]; then
    fail_test "Gate C wrote wrong status to SQLite: ${_IMPL_SQLITE_STATUS} (expected needs-verification)"
else
    fail_test "Implementer did not create proof state in SQLite (proof_state_get returned empty)"
fi

# --- Test 11: gate activation only when missing ---
run_test "Gate C: Implementer does not overwrite existing .proof-status"
TEMP_REPO=$(mktemp -d "$PROJECT_ROOT/tmp/test-pg-exist-XXXXXX")
git -C "$TEMP_REPO" init > /dev/null 2>&1
mkdir -p "$TEMP_REPO/.claude"
EXIST_PHASH=$(echo "$TEMP_REPO" | $_SHA256_CMD | cut -c1-8)
# Write to new canonical path so resolve_proof_file() finds it
mkdir -p "$TEMP_REPO/.claude/state/${EXIST_PHASH}"
echo "pending|99999" > "$TEMP_REPO/.claude/state/${EXIST_PHASH}/proof-status"
# Gate C.1 requires at least one linked worktree — add one so the hook reaches Gate C.2
EXIST_WORKTREE="$TEMP_REPO/.worktrees/feature-exist"
mkdir -p "$EXIST_WORKTREE"
git -C "$TEMP_REPO" worktree add "$EXIST_WORKTREE" -b feature/exist > /dev/null 2>&1 || \
    git -C "$TEMP_REPO" worktree add --detach "$EXIST_WORKTREE" > /dev/null 2>&1 || true

echo "$INPUT_JSON" | CLAUDE_PROJECT_DIR="$TEMP_REPO" CLAUDE_DIR="$TEMP_REPO/.claude" bash "$HOOKS_DIR/task-track.sh" > /dev/null 2>&1

_EXIST_PROOF="$TEMP_REPO/.claude/state/${EXIST_PHASH}/proof-status"
STATUS=$(cut -d'|' -f1 "$_EXIST_PROOF" 2>/dev/null || echo "")
TIMESTAMP=$(cut -d'|' -f2 "$_EXIST_PROOF" 2>/dev/null || echo "")

if [[ "$STATUS" == "pending" && "$TIMESTAMP" == "99999" ]]; then
    pass_test
else
    fail_test "Implementer overwrote existing proof-status (status: $STATUS, timestamp: $TIMESTAMP)"
fi

rm -rf "$TEMP_REPO"

# --- Tests 12-15: guard.sh Check 6-7 (test-status gate inversion) ---

# Helper to run guard.sh with mock input
run_guard() {
    local command="$1"
    local test_file="$2"  # Path to .test-status or "missing"

    # Create a temp git repo
    local TEMP_REPO=$(mktemp -d "$PROJECT_ROOT/tmp/test-pg-guard-XXXXXX")
    git -C "$TEMP_REPO" init > /dev/null 2>&1
    mkdir -p "$TEMP_REPO/.claude"

    # Set up .test-status if not missing
    if [[ "$test_file" != "missing" ]]; then
        echo "$test_file" > "$TEMP_REPO/.claude/.test-status"
    fi

    # Mock input JSON
    local INPUT_JSON=$(cat <<EOF
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "cd $TEMP_REPO && $command"
  }
}
EOF
)

    # Run hook — cd into temp repo so detect_project_root finds it (not meta-repo)
    local OUTPUT
    OUTPUT=$(cd "$TEMP_REPO" && \
             echo "$INPUT_JSON" | bash "$HOOKS_DIR/pre-bash.sh" 2>&1)
    local EXIT_CODE=$?

    # Cleanup - ensure we're not in TEMP_REPO before deleting
    cd "$PROJECT_ROOT"
    rm -rf "$TEMP_REPO"

    echo "$OUTPUT"
    return $EXIT_CODE
}

run_test "Check 7: Missing .test-status allows commit (bootstrap)"
OUTPUT=$(run_guard "git commit -m test" "missing" 2>&1) || true
if echo "$OUTPUT" | grep -q "deny"; then
    fail_test "Commit blocked when .test-status missing (should allow)"
else
    pass_test
fi

run_test "Check 6: Missing .test-status allows merge (bootstrap)"
OUTPUT=$(run_guard "git merge feature" "missing" 2>&1) || true
if echo "$OUTPUT" | grep -q "deny"; then
    fail_test "Merge blocked when .test-status missing (should allow)"
else
    pass_test
fi

run_test "Check 7: fail test-status blocks commit"
RECENT_TIME=$(date +%s)
OUTPUT=$(run_guard "git commit -m test" "fail|2|$RECENT_TIME|10" 2>&1) || true
if echo "$OUTPUT" | grep -q "deny" && echo "$OUTPUT" | grep -q "failing"; then
    pass_test
else
    fail_test "Commit allowed with failing tests"
fi

run_test "Check 6: fail test-status blocks merge"
RECENT_TIME=$(date +%s)
OUTPUT=$(run_guard "git merge feature" "fail|2|$RECENT_TIME|10" 2>&1) || true
if echo "$OUTPUT" | grep -q "deny" && echo "$OUTPUT" | grep -q "failing"; then
    pass_test
else
    fail_test "Merge allowed with failing tests"
fi

# --- Tests 16-17: guard.sh Check 8 (proof-status gate inversion) ---

# Helper to run guard.sh with proof-status mock.
# resolve_proof_file() uses CLAUDE_DIR to locate the proof-status file.
# We set CLAUDE_DIR="$TEMP_REPO/.claude" and write to state/{phash}/proof-status.
run_guard_proof() {
    local command="$1"
    local proof_file="$2"  # Proof-status content or "missing"

    local TEMP_REPO
    TEMP_REPO=$(mktemp -d "$PROJECT_ROOT/tmp/test-pg-proof-XXXXXX")
    git -C "$TEMP_REPO" init > /dev/null 2>&1
    mkdir -p "$TEMP_REPO/.claude"

    local PHASH
    PHASH=$(echo "$TEMP_REPO" | $_SHA256_CMD | cut -c1-8)

    if [[ "$proof_file" != "missing" ]]; then
        # Write to new canonical path (state/{phash}/proof-status)
        mkdir -p "$TEMP_REPO/.claude/state/${PHASH}"
        echo "$proof_file" > "$TEMP_REPO/.claude/state/${PHASH}/proof-status"
    fi

    local INPUT_JSON
    INPUT_JSON=$(cat <<EOF
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "cd $TEMP_REPO && $command"
  }
}
EOF
)

    # Run hook — cd into temp repo so detect_project_root finds it (not meta-repo).
    # CLAUDE_DIR set to isolated .claude so resolve_proof_file() reads test file.
    local OUTPUT
    OUTPUT=$(cd "$TEMP_REPO" && \
             echo "$INPUT_JSON" | CLAUDE_DIR="$TEMP_REPO/.claude" bash "$HOOKS_DIR/pre-bash.sh" 2>&1)
    local EXIT_CODE=$?

    # Cleanup - ensure we're not in TEMP_REPO before deleting
    cd "$PROJECT_ROOT"
    rm -rf "$TEMP_REPO"

    echo "$OUTPUT"
    return $EXIT_CODE
}

run_test "Check 8: Missing .proof-status allows commit (bootstrap)"
OUTPUT=$(run_guard_proof "git commit -m test" "missing" 2>&1) || true
if echo "$OUTPUT" | grep -q "deny"; then
    fail_test "Commit blocked when .proof-status missing (should allow)"
else
    pass_test
fi

run_test "Check 8: needs-verification blocks commit"
OUTPUT=$(run_guard_proof "git commit -m test" "needs-verification|12345" 2>&1) || true
if echo "$OUTPUT" | grep -q "deny" && echo "$OUTPUT" | grep -q "needs-verification"; then
    pass_test
else
    fail_test "Commit allowed with needs-verification status"
fi

# --- Tests 18-20: guard.sh Check 10 (block .proof-status deletion) ---

# Check 10 tests: pre-bash.sh Check 10 reads the OLD path via get_claude_dir().
# Set CLAUDE_DIR to the isolated .claude dir AND write to the old path so Check 10 finds it.
# Also write to new path for forward-compat.
run_test "Check 10: Block rm .proof-status when needs-verification"
TEMP_REPO=$(mktemp -d "$PROJECT_ROOT/tmp/test-pg-del-XXXXXX")
git -C "$TEMP_REPO" init > /dev/null 2>&1
mkdir -p "$TEMP_REPO/.claude"
C10_PHASH=$(echo "$TEMP_REPO" | $_SHA256_CMD | cut -c1-8)
# Write to old path (what Check 10 reads via get_claude_dir()/.proof-status-{phash})
echo "needs-verification|12345" > "$TEMP_REPO/.claude/.proof-status-${C10_PHASH}"
# Also write to new path for completeness
mkdir -p "$TEMP_REPO/.claude/state/${C10_PHASH}"
echo "needs-verification|12345" > "$TEMP_REPO/.claude/state/${C10_PHASH}/proof-status"
# Create active agent marker so Check 10 blocks deletion (DEC-PROOF-DELETE-SOFTEN-001)
C10_SID="test-check10-$$"
C10_TRACE_DIR=$(mktemp -d "$PROJECT_ROOT/tmp/test-traces-XXXXXX")
echo "implementer-fake" > "$C10_TRACE_DIR/.active-implementer-${C10_SID}-${C10_PHASH}"

INPUT_JSON=$(cat <<EOF
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "rm $TEMP_REPO/.claude/.proof-status"
  }
}
EOF
)

OUTPUT=$(cd "$TEMP_REPO" && \
         echo "$INPUT_JSON" | CLAUDE_SESSION_ID="$C10_SID" TRACE_STORE="$C10_TRACE_DIR" CLAUDE_DIR="$TEMP_REPO/.claude" bash "$HOOKS_DIR/pre-bash.sh" 2>&1) || true

if echo "$OUTPUT" | grep -q "deny" && echo "$OUTPUT" | grep -q "verification is active"; then
    pass_test
else
    fail_test "Deletion allowed when needs-verification"
fi

cd "$PROJECT_ROOT"
rm -rf "$TEMP_REPO" "$C10_TRACE_DIR"

run_test "Check 10: Block rm .proof-status when pending"
TEMP_REPO=$(mktemp -d "$PROJECT_ROOT/tmp/test-pg-pend-XXXXXX")
git -C "$TEMP_REPO" init > /dev/null 2>&1
mkdir -p "$TEMP_REPO/.claude"
C10_PHASH=$(echo "$TEMP_REPO" | $_SHA256_CMD | cut -c1-8)
echo "pending|12345" > "$TEMP_REPO/.claude/.proof-status-${C10_PHASH}"
mkdir -p "$TEMP_REPO/.claude/state/${C10_PHASH}"
echo "pending|12345" > "$TEMP_REPO/.claude/state/${C10_PHASH}/proof-status"
# Create active agent marker so Check 10 blocks deletion (DEC-PROOF-DELETE-SOFTEN-001)
C10_SID="test-check10-pend-$$"
C10_TRACE_DIR=$(mktemp -d "$PROJECT_ROOT/tmp/test-traces-XXXXXX")
echo "implementer-fake" > "$C10_TRACE_DIR/.active-implementer-${C10_SID}-${C10_PHASH}"

INPUT_JSON=$(cat <<EOF
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "rm $TEMP_REPO/.claude/.proof-status"
  }
}
EOF
)

OUTPUT=$(cd "$TEMP_REPO" && \
         echo "$INPUT_JSON" | CLAUDE_SESSION_ID="$C10_SID" TRACE_STORE="$C10_TRACE_DIR" CLAUDE_DIR="$TEMP_REPO/.claude" bash "$HOOKS_DIR/pre-bash.sh" 2>&1) || true

if echo "$OUTPUT" | grep -q "deny" && echo "$OUTPUT" | grep -q "verification is active"; then
    pass_test
else
    fail_test "Deletion allowed when pending"
fi

cd "$PROJECT_ROOT"
rm -rf "$TEMP_REPO" "$C10_TRACE_DIR"

run_test "Check 10: Allow rm .proof-status when verified"
TEMP_REPO=$(mktemp -d "$PROJECT_ROOT/tmp/test-pg-ver-XXXXXX")
git -C "$TEMP_REPO" init > /dev/null 2>&1
mkdir -p "$TEMP_REPO/.claude"
C10_PHASH=$(echo "$TEMP_REPO" | $_SHA256_CMD | cut -c1-8)
echo "verified|12345" > "$TEMP_REPO/.claude/.proof-status-${C10_PHASH}"
mkdir -p "$TEMP_REPO/.claude/state/${C10_PHASH}"
echo "verified|12345" > "$TEMP_REPO/.claude/state/${C10_PHASH}/proof-status"

INPUT_JSON=$(cat <<EOF
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "rm $TEMP_REPO/.claude/.proof-status"
  }
}
EOF
)

OUTPUT=$(cd "$TEMP_REPO" && \
         echo "$INPUT_JSON" | CLAUDE_DIR="$TEMP_REPO/.claude" bash "$HOOKS_DIR/pre-bash.sh" 2>&1) || true

if echo "$OUTPUT" | grep -q "deny"; then
    fail_test "Deletion blocked when verified (should allow)"
else
    pass_test
fi

cd "$PROJECT_ROOT"
rm -rf "$TEMP_REPO"

# --- Tests 21-24: Check 8 + Check 10 read from SQLite (require_state fix, issue #237) ---
#
# These tests verify that pre-bash.sh Check 8 and Check 10 call require_state()
# before proof_state_get(), so they read proof state from SQLite — not just the
# flat-file fallback. Tests seed SQLite only (no flat file) to prove SQLite is
# the actual read path after the fix.
#
# Before the fix: proof_state_get() is never available (require_state not called),
# so the gate silently falls back to the flat file and misses fresh SQLite state.
# After the fix: require_state is called → proof_state_get() reads SQLite correctly.

# Helper: seed SQLite proof state and run Check 8 (commit gate)
run_guard_proof_sqlite() {
    local command="$1"
    local sqlite_status="$2"  # Status to seed into SQLite, or "missing" for no entry

    local TEMP_REPO
    TEMP_REPO=$(mktemp -d "$PROJECT_ROOT/tmp/test-pg-sqlite-XXXXXX")
    _CLEANUP_DIRS+=("$TEMP_REPO")
    git -C "$TEMP_REPO" init > /dev/null 2>&1
    mkdir -p "$TEMP_REPO/.claude"

    # Seed SQLite via proof_state_set — no flat file written
    if [[ "$sqlite_status" != "missing" ]]; then
        PROJECT_ROOT="$TEMP_REPO" CLAUDE_DIR="$TEMP_REPO/.claude" \
            bash -c "source '${HOOKS_DIR}/source-lib.sh'; require_state; proof_state_set '${sqlite_status}' 'test-setup'" 2>/dev/null || true
    fi

    local INPUT_JSON
    INPUT_JSON=$(cat <<EOF
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "cd $TEMP_REPO && $command"
  }
}
EOF
)

    local OUTPUT
    OUTPUT=$(cd "$TEMP_REPO" && \
             echo "$INPUT_JSON" | CLAUDE_DIR="$TEMP_REPO/.claude" bash "$HOOKS_DIR/pre-bash.sh" 2>&1)
    local EXIT_CODE=$?

    cd "$PROJECT_ROOT"

    echo "$OUTPUT"
    return $EXIT_CODE
}

run_test "Check 8 (SQLite): needs-verification in SQLite blocks commit (require_state fix)"
OUTPUT=$(run_guard_proof_sqlite "git commit -m test" "needs-verification" 2>&1) || true
if echo "$OUTPUT" | grep -q "deny" && echo "$OUTPUT" | grep -q "needs-verification"; then
    pass_test
else
    fail_test "Commit allowed with needs-verification in SQLite — require_state may not be called"
fi

run_test "Check 8 (SQLite): verified in SQLite allows commit"
OUTPUT=$(run_guard_proof_sqlite "git commit -m test" "verified" 2>&1) || true
if echo "$OUTPUT" | grep -q "deny"; then
    fail_test "Commit blocked with verified status in SQLite"
else
    pass_test
fi

# Helper: seed SQLite proof state and run Check 10 (delete gate)
run_guard_delete_sqlite() {
    local sqlite_status="$1"
    local with_agent_marker="$2"  # "true" to create an active agent marker

    local TEMP_REPO
    TEMP_REPO=$(mktemp -d "$PROJECT_ROOT/tmp/test-pg-del-sql-XXXXXX")
    _CLEANUP_DIRS+=("$TEMP_REPO")
    git -C "$TEMP_REPO" init > /dev/null 2>&1
    mkdir -p "$TEMP_REPO/.claude"

    local PHASH
    PHASH=$(echo "$TEMP_REPO" | $_SHA256_CMD | cut -c1-8)

    # Seed SQLite via proof_state_set — no flat file written
    PROJECT_ROOT="$TEMP_REPO" CLAUDE_DIR="$TEMP_REPO/.claude" \
        bash -c "source '${HOOKS_DIR}/source-lib.sh'; require_state; proof_state_set '${sqlite_status}' 'test-setup'" 2>/dev/null || true

    local SID="test-c10-sql-$$"
    local TRACE_D
    TRACE_D=$(mktemp -d "$PROJECT_ROOT/tmp/test-traces-sql-XXXXXX")
    _CLEANUP_DIRS+=("$TRACE_D")

    if [[ "$with_agent_marker" == "true" ]]; then
        echo "implementer-fake" > "$TRACE_D/.active-implementer-${SID}-${PHASH}"
    fi

    local INPUT_JSON
    INPUT_JSON=$(cat <<EOF
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "rm $TEMP_REPO/.claude/.proof-status"
  }
}
EOF
)

    local OUTPUT
    OUTPUT=$(cd "$TEMP_REPO" && \
             echo "$INPUT_JSON" | CLAUDE_SESSION_ID="$SID" TRACE_STORE="$TRACE_D" CLAUDE_DIR="$TEMP_REPO/.claude" bash "$HOOKS_DIR/pre-bash.sh" 2>&1) || true

    cd "$PROJECT_ROOT"

    echo "$OUTPUT"
}

run_test "Check 10 (SQLite): needs-verification in SQLite blocks deletion (require_state fix)"
OUTPUT=$(run_guard_delete_sqlite "needs-verification" "true" 2>&1) || true
if echo "$OUTPUT" | grep -q "deny" && echo "$OUTPUT" | grep -q "verification is active"; then
    pass_test
else
    fail_test "Deletion allowed with needs-verification in SQLite — require_state may not be called in Check 10"
fi

run_test "Check 10 (SQLite): verified in SQLite allows deletion"
OUTPUT=$(run_guard_delete_sqlite "verified" "false" 2>&1) || true
if echo "$OUTPUT" | grep -q "deny"; then
    fail_test "Deletion blocked with verified status in SQLite"
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
