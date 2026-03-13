#!/usr/bin/env bash
# test-governance-bypass.sh — Tests for DEC-RECK-011: governance self-bypass prevention
#
# Validates three fixes that close governance bypass vectors:
#
#   Fix 1: pre-write.sh branch guard extended to governance-critical markdown
#     - TG01: pre-write.sh blocks agents/*.md on main branch
#     - TG02: pre-write.sh allows agents/*.md in a worktree (feature branch)
#     - TG03: pre-write.sh blocks CLAUDE.md on main branch
#     - TG04: pre-write.sh blocks docs/*.md on main branch
#     - TG05: pre-write.sh blocks ARCHITECTURE.md on main branch
#     - TG06: pre-write.sh allows source .sh files in worktree (no regression)
#
#   Fix 2: task-track.sh @plan-update bypass narrowed to plan-only commits
#     - TG07: @plan-update with ONLY MASTER_PLAN.md staged → bypass allowed
#     - TG08: @plan-update with agents/*.md staged → bypass denied
#     - TG09: @plan-update with docs/*.md staged → bypass denied
#     - TG10: @no-source with non-plan files staged → bypass denied
#
#   Fix 3: pre-bash.sh config commit guard
#     - TG11: git commit with agents/*.md staged on main → governance deny
#     - TG12: git commit with docs/*.md staged on main → governance deny
#     - TG13: git commit with CLAUDE.md staged on main → governance deny
#     - TG14: git commit with ARCHITECTURE.md staged on main → governance deny
#     - TG15: git commit with only MASTER_PLAN.md (untracked) on main → allow (bootstrap)
#     - TG16: git commit on feature branch with governance files → allow
#
# @decision DEC-RECK-011
# @title Governance self-bypass prevention test suite
# @status accepted
# @rationale Validates all three bypass vectors identified in the reckoning:
#   (1) pre-write.sh branch guard not protecting governance markdown,
#   (2) @plan-update bypass too permissive, and
#   (3) no specific error for governance file commits on main.
#   Uses real hook executables; no mocks. Follows patterns from
#   test-orchestrator-guard.sh and test-bootstrap-mitigation.sh.
#
# Usage: bash tests/test-governance-bypass.sh
# Returns: 0 if all tests pass, 1 if any fail
# Sacred Practice #3: temp dirs use project tmp/, not /tmp/

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

CURRENT_TEST=""

run_test() {
    local test_name="$1"
    CURRENT_TEST="$test_name"
    TESTS_RUN=$((TESTS_RUN + 1))
    echo ""
    echo "Running: $test_name"
}

pass_test() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: $CURRENT_TEST"
}

fail_test() {
    local reason="$1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: $CURRENT_TEST — $reason"
}

# ---------------------------------------------------------------------------
# Setup: cleanup on EXIT
# ---------------------------------------------------------------------------
CLEANUP_DIRS=()
cleanup() {
    [[ ${#CLEANUP_DIRS[@]} -gt 0 ]] && rm -rf "${CLEANUP_DIRS[@]}" 2>/dev/null || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# SHA-256 helper (portable: macOS shasum, Linux sha256sum)
# ---------------------------------------------------------------------------
if command -v shasum >/dev/null 2>&1; then
    _SHA256_CMD="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
    _SHA256_CMD="sha256sum"
else
    _SHA256_CMD="shasum -a 256"
fi

compute_phash() {
    local dir="$1"
    printf '%s' "$dir" | $_SHA256_CMD | cut -c1-16
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Create an isolated temp git repo on main branch with an initial commit
make_main_repo() {
    local d
    d=$(mktemp -d "$PROJECT_ROOT/tmp/test-govbypass-XXXXXX")
    CLEANUP_DIRS+=("$d")
    git -C "$d" init -q
    git -C "$d" config user.email "test@test.com"
    git -C "$d" config user.name "Test"
    # Initial commit to establish main branch
    echo "readme" > "$d/README.md"
    git -C "$d" add README.md
    git -C "$d" commit -q -m "Initial commit"
    echo "$d"
}

# Create an isolated temp git repo on a feature branch (worktree-like context)
make_feature_repo() {
    local d
    d=$(mktemp -d "$PROJECT_ROOT/tmp/test-govbypass-XXXXXX")
    CLEANUP_DIRS+=("$d")
    git -C "$d" init -q -b feature/test-governance
    git -C "$d" config user.email "test@test.com"
    git -C "$d" config user.name "Test"
    mkdir -p "$d/.claude"
    echo "$d"
}

# Create a worktree path (for _IN_WORKTREE detection in pre-write.sh)
make_worktree_path() {
    local d="$1"
    local name="${2:-test-feature}"
    local wt_dir="$d/.worktrees/$name"
    mkdir -p "$wt_dir/agents"
    mkdir -p "$wt_dir/docs"
    echo "$wt_dir"
}

# Build Write tool JSON input for pre-write.sh
make_write_input() {
    local file_path="$1"
    local content="${2:-# governance markdown content\n## Section\nsome content here\n}"
    printf '{"tool_name":"Write","tool_input":{"file_path":%s,"content":%s}}' \
        "$(printf '%s' "$file_path" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
        "$(printf '%s' "$content" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
}

# Build Bash tool JSON input for pre-bash.sh
make_bash_input() {
    local cmd="$1"
    local cwd="${2:-$PROJECT_ROOT}"
    printf '{"tool_name":"Bash","tool_input":{"command":%s,"cwd":%s}}' \
        "$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
        "$(printf '%s' "$cwd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
}

# Assert output contains a deny decision
assert_deny() {
    local output="$1"
    local label="$2"
    local pattern="${3:-}"
    if echo "$output" | grep -q '"permissionDecision".*"deny"'; then
        if [[ -n "$pattern" ]] && ! echo "$output" | grep -q "$pattern"; then
            fail_test "$label: denied but missing expected pattern '$pattern'. Output: $(echo "$output" | head -2)"
        else
            pass_test
        fi
    else
        fail_test "$label: expected deny but got allow. Output: $(echo "$output" | head -3)"
    fi
}

# Assert output does NOT contain a deny decision
assert_allow() {
    local output="$1"
    local label="$2"
    if echo "$output" | grep -q '"permissionDecision".*"deny"'; then
        local reason
        reason=$(echo "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("hookSpecificOutput",{}).get("permissionDecisionReason",""))' 2>/dev/null || echo "(parse error)")
        fail_test "$label: was denied but should be allowed. Reason: ${reason:0:200}"
    else
        pass_test
    fi
}

echo "=== DEC-RECK-011: Governance Bypass Prevention Tests ==="

# ===========================================================================
# SYNTAX CHECKS
# ===========================================================================

run_test "Syntax: pre-write.sh is valid bash"
if bash -n "$HOOKS_DIR/pre-write.sh" 2>/dev/null; then
    pass_test
else
    fail_test "pre-write.sh has syntax errors"
fi

run_test "Syntax: task-track.sh is valid bash"
if bash -n "$HOOKS_DIR/task-track.sh" 2>/dev/null; then
    pass_test
else
    fail_test "task-track.sh has syntax errors"
fi

run_test "Syntax: pre-bash.sh is valid bash"
if bash -n "$HOOKS_DIR/pre-bash.sh" 2>/dev/null; then
    pass_test
else
    fail_test "pre-bash.sh has syntax errors"
fi

# ===========================================================================
# FIX 1: pre-write.sh branch guard extended to governance markdown
# ===========================================================================

echo ""
echo "--- Fix 1: pre-write.sh governance markdown branch guard ---"

# TG01: agents/*.md blocked on main
run_test "TG01: pre-write.sh blocks agents/*.md on main branch"

TG01_REPO=$(make_main_repo)
TG01_FILE="$TG01_REPO/agents/implementer.md"
mkdir -p "$(dirname "$TG01_FILE")"
TG01_INPUT=$(make_write_input "$TG01_FILE" "# Agent doc\n## Section\nsome content\n")

TG01_OUTPUT=$(
    PROJECT_ROOT="$TG01_REPO" \
    bash "$HOOKS_DIR/pre-write.sh" \
    < <(echo "$TG01_INPUT") 2>/dev/null
) || true

assert_deny "$TG01_OUTPUT" "TG01" "governance-critical markdown\|DEC-RECK-011"

# TG02: agents/*.md allowed in worktree (feature branch)
run_test "TG02: pre-write.sh allows agents/*.md in worktree (feature branch)"

TG02_REPO=$(make_feature_repo)
TG02_WT=$(make_worktree_path "$TG02_REPO")
TG02_FILE="$TG02_WT/agents/implementer.md"
mkdir -p "$(dirname "$TG02_FILE")"
TG02_INPUT=$(make_write_input "$TG02_FILE" "# Agent doc\n## Section\nsome content\n")

TG02_OUTPUT=$(
    PROJECT_ROOT="$TG02_REPO" \
    bash "$HOOKS_DIR/pre-write.sh" \
    < <(echo "$TG02_INPUT") 2>/dev/null
) || true

assert_allow "$TG02_OUTPUT" "TG02"

# TG03: CLAUDE.md blocked on main
run_test "TG03: pre-write.sh blocks CLAUDE.md on main branch"

TG03_REPO=$(make_main_repo)
TG03_FILE="$TG03_REPO/CLAUDE.md"
TG03_INPUT=$(make_write_input "$TG03_FILE" "# CLAUDE.md\nsome governance content\n")

TG03_OUTPUT=$(
    PROJECT_ROOT="$TG03_REPO" \
    bash "$HOOKS_DIR/pre-write.sh" \
    < <(echo "$TG03_INPUT") 2>/dev/null
) || true

assert_deny "$TG03_OUTPUT" "TG03" "governance-critical markdown\|DEC-RECK-011"

# TG04: docs/*.md blocked on main
run_test "TG04: pre-write.sh blocks docs/*.md on main branch"

TG04_REPO=$(make_main_repo)
TG04_FILE="$TG04_REPO/docs/DISPATCH.md"
mkdir -p "$(dirname "$TG04_FILE")"
TG04_INPUT=$(make_write_input "$TG04_FILE" "# Dispatch docs\nsome content\n")

TG04_OUTPUT=$(
    PROJECT_ROOT="$TG04_REPO" \
    bash "$HOOKS_DIR/pre-write.sh" \
    < <(echo "$TG04_INPUT") 2>/dev/null
) || true

assert_deny "$TG04_OUTPUT" "TG04" "governance-critical markdown\|DEC-RECK-011"

# TG05: ARCHITECTURE.md blocked on main
run_test "TG05: pre-write.sh blocks ARCHITECTURE.md on main branch"

TG05_REPO=$(make_main_repo)
TG05_FILE="$TG05_REPO/ARCHITECTURE.md"
TG05_INPUT=$(make_write_input "$TG05_FILE" "# Architecture\nsome content\n")

TG05_OUTPUT=$(
    PROJECT_ROOT="$TG05_REPO" \
    bash "$HOOKS_DIR/pre-write.sh" \
    < <(echo "$TG05_INPUT") 2>/dev/null
) || true

assert_deny "$TG05_OUTPUT" "TG05" "governance-critical markdown\|DEC-RECK-011"

# TG06: regular .sh files in worktree still allowed (no regression)
# Note: content must include a doc header to avoid doc-gate deny (Sacred Practice #7)
run_test "TG06: pre-write.sh allows source .sh files in worktree (no regression)"

TG06_REPO=$(make_feature_repo)
TG06_WT=$(make_worktree_path "$TG06_REPO")
TG06_FILE="$TG06_WT/hooks/my-hook.sh"
mkdir -p "$(dirname "$TG06_FILE")"
# Use Edit tool JSON to avoid doc-gate (Edit skips doc-header check on existing files)
# Actually: Write to a non-.sh file or use a minimal file with proper header.
# The branch guard is what we're testing — use doc-gate-exempt content.
TG06_CONTENT='#!/usr/bin/env bash
# My hook script — test fixture for branch guard regression test
# @decision DEC-RECK-011-TEST
# @title Test fixture for governance bypass prevention
# @status accepted
# @rationale Validates that source files in worktrees pass branch guard
echo hello
'
TG06_INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":%s,"content":%s}}' \
    "$(printf '%s' "$TG06_FILE" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
    "$(printf '%s' "$TG06_CONTENT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')")

TG06_OUTPUT=$(
    PROJECT_ROOT="$TG06_REPO" \
    bash "$HOOKS_DIR/pre-write.sh" \
    < <(echo "$TG06_INPUT") 2>/dev/null
) || true

assert_allow "$TG06_OUTPUT" "TG06"

# ===========================================================================
# FIX 2: task-track.sh @plan-update bypass narrowed to plan-only commits
# ===========================================================================

echo ""
echo "--- Fix 2: task-track.sh @plan-update bypass narrowing ---"

# TG07: @plan-update with ONLY MASTER_PLAN.md staged → bypass allowed
run_test "TG07: @plan-update with ONLY MASTER_PLAN.md staged → bypass allowed"

TG07_REPO=$(make_main_repo)
TG07_PHASH=$(compute_phash "$TG07_REPO")
mkdir -p "$TG07_REPO/.claude"

# Set proof-status to needs-verification (would block without bypass)
printf 'needs-verification|%s\n' "$(date +%s)" > "$TG07_REPO/.claude/.proof-status-${TG07_PHASH}"

# Stage ONLY MASTER_PLAN.md
echo "# Master Plan" > "$TG07_REPO/MASTER_PLAN.md"
git -C "$TG07_REPO" add MASTER_PLAN.md

TG07_INPUT=$(cat <<EOF
{
  "tool_name": "Agent",
  "tool_input": {
    "subagent_type": "guardian",
    "prompt": "Merge plan amendment @plan-update — MASTER_PLAN.md only, no source files changed"
  }
}
EOF
)

TG07_OUTPUT=$(cd "$TG07_REPO" && echo "$TG07_INPUT" | \
    CLAUDE_PROJECT_DIR="$TG07_REPO" bash "$HOOKS_DIR/task-track.sh" 2>&1) || true

# Should NOT deny (bypass granted for plan-only files)
if echo "$TG07_OUTPUT" | grep -q '"permissionDecision".*"deny"'; then
    fail_test "@plan-update with ONLY MASTER_PLAN.md was denied. Output: ${TG07_OUTPUT:0:300}"
else
    pass_test
fi

# Unstage files for cleanup
git -C "$TG07_REPO" reset HEAD 2>/dev/null || true

# TG08: @plan-update with agents/*.md staged → bypass denied
run_test "TG08: @plan-update with agents/*.md staged → bypass denied"

TG08_REPO=$(make_main_repo)
TG08_PHASH=$(compute_phash "$TG08_REPO")
mkdir -p "$TG08_REPO/.claude" "$TG08_REPO/agents"

# Set proof-status to needs-verification
printf 'needs-verification|%s\n' "$(date +%s)" > "$TG08_REPO/.claude/.proof-status-${TG08_PHASH}"

# Stage agents/*.md along with MASTER_PLAN.md
echo "# Master Plan" > "$TG08_REPO/MASTER_PLAN.md"
echo "# Agent doc" > "$TG08_REPO/agents/implementer.md"
git -C "$TG08_REPO" add MASTER_PLAN.md agents/implementer.md

TG08_INPUT=$(cat <<EOF
{
  "tool_name": "Agent",
  "tool_input": {
    "subagent_type": "guardian",
    "prompt": "Merge changes @plan-update including agent doc updates"
  }
}
EOF
)

TG08_OUTPUT=$(cd "$TG08_REPO" && echo "$TG08_INPUT" | \
    CLAUDE_PROJECT_DIR="$TG08_REPO" bash "$HOOKS_DIR/task-track.sh" 2>&1) || true

# Must deny — agents/implementer.md is not a plan file
if echo "$TG08_OUTPUT" | grep -q '"permissionDecision".*"deny"'; then
    pass_test
else
    fail_test "@plan-update with agents/*.md staged should deny. Output: ${TG08_OUTPUT:0:300}"
fi

# Unstage for cleanup
git -C "$TG08_REPO" reset HEAD 2>/dev/null || true

# TG09: @plan-update with docs/*.md staged → bypass denied
run_test "TG09: @plan-update with docs/*.md staged → bypass denied"

TG09_REPO=$(make_main_repo)
TG09_PHASH=$(compute_phash "$TG09_REPO")
mkdir -p "$TG09_REPO/.claude" "$TG09_REPO/docs"

printf 'needs-verification|%s\n' "$(date +%s)" > "$TG09_REPO/.claude/.proof-status-${TG09_PHASH}"

echo "# Dispatch doc" > "$TG09_REPO/docs/DISPATCH.md"
git -C "$TG09_REPO" add docs/DISPATCH.md

TG09_INPUT=$(cat <<EOF
{
  "tool_name": "Agent",
  "tool_input": {
    "subagent_type": "guardian",
    "prompt": "@plan-update commit including dispatch doc changes"
  }
}
EOF
)

TG09_OUTPUT=$(cd "$TG09_REPO" && echo "$TG09_INPUT" | \
    CLAUDE_PROJECT_DIR="$TG09_REPO" bash "$HOOKS_DIR/task-track.sh" 2>&1) || true

if echo "$TG09_OUTPUT" | grep -q '"permissionDecision".*"deny"'; then
    pass_test
else
    fail_test "@plan-update with docs/*.md staged should deny. Output: ${TG09_OUTPUT:0:300}"
fi

git -C "$TG09_REPO" reset HEAD 2>/dev/null || true

# TG10: @no-source with non-plan files staged → bypass denied
run_test "TG10: @no-source with non-plan files staged → bypass denied"

TG10_REPO=$(make_main_repo)
TG10_PHASH=$(compute_phash "$TG10_REPO")
mkdir -p "$TG10_REPO/.claude" "$TG10_REPO/hooks"

printf 'needs-verification|%s\n' "$(date +%s)" > "$TG10_REPO/.claude/.proof-status-${TG10_PHASH}"

# Stage a hooks/*.sh file (not plan-related)
echo "#!/bin/bash" > "$TG10_REPO/hooks/my-hook.sh"
git -C "$TG10_REPO" add hooks/my-hook.sh

TG10_INPUT=$(cat <<EOF
{
  "tool_name": "Agent",
  "tool_input": {
    "subagent_type": "guardian",
    "prompt": "@no-source commit — just hook scripts, nothing to verify"
  }
}
EOF
)

TG10_OUTPUT=$(cd "$TG10_REPO" && echo "$TG10_INPUT" | \
    CLAUDE_PROJECT_DIR="$TG10_REPO" bash "$HOOKS_DIR/task-track.sh" 2>&1) || true

if echo "$TG10_OUTPUT" | grep -q '"permissionDecision".*"deny"'; then
    pass_test
else
    fail_test "@no-source with hooks/*.sh staged should deny. Output: ${TG10_OUTPUT:0:300}"
fi

git -C "$TG10_REPO" reset HEAD 2>/dev/null || true

# ===========================================================================
# FIX 3: pre-bash.sh config commit guard
# ===========================================================================

echo ""
echo "--- Fix 3: pre-bash.sh config commit guard ---"

# Helper: build bash input JSON
make_commit_input() {
    local cmd="$1"
    local cwd="$2"
    printf '{"tool_name":"Bash","tool_input":{"command":%s,"cwd":%s}}' \
        "$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
        "$(printf '%s' "$cwd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
}

# TG11: git commit with agents/*.md staged on main → governance deny
run_test "TG11: git commit with agents/*.md staged on main → governance deny"

TG11_REPO=$(make_main_repo)
mkdir -p "$TG11_REPO/agents"
echo "# Agent doc" > "$TG11_REPO/agents/implementer.md"
git -C "$TG11_REPO" add agents/implementer.md

TG11_CMD="git -C \"$TG11_REPO\" commit -m \"update agent doc\""
TG11_INPUT=$(make_commit_input "$TG11_CMD" "$TG11_REPO")

TG11_OUTPUT=$(echo "$TG11_INPUT" | bash "$HOOKS_DIR/pre-bash.sh" 2>/dev/null) || true

assert_deny "$TG11_OUTPUT" "TG11" "governance\|DEC-RECK-011"

git -C "$TG11_REPO" reset HEAD 2>/dev/null || true

# TG12: git commit with docs/*.md staged on main → governance deny
run_test "TG12: git commit with docs/*.md staged on main → governance deny"

TG12_REPO=$(make_main_repo)
mkdir -p "$TG12_REPO/docs"
echo "# Dispatch doc" > "$TG12_REPO/docs/DISPATCH.md"
git -C "$TG12_REPO" add docs/DISPATCH.md

TG12_CMD="git -C \"$TG12_REPO\" commit -m \"update dispatch doc\""
TG12_INPUT=$(make_commit_input "$TG12_CMD" "$TG12_REPO")

TG12_OUTPUT=$(echo "$TG12_INPUT" | bash "$HOOKS_DIR/pre-bash.sh" 2>/dev/null) || true

assert_deny "$TG12_OUTPUT" "TG12" "governance\|DEC-RECK-011"

git -C "$TG12_REPO" reset HEAD 2>/dev/null || true

# TG13: git commit with CLAUDE.md staged on main → governance deny
run_test "TG13: git commit with CLAUDE.md staged on main → governance deny"

TG13_REPO=$(make_main_repo)
echo "# CLAUDE content" > "$TG13_REPO/CLAUDE.md"
git -C "$TG13_REPO" add CLAUDE.md

TG13_CMD="git -C \"$TG13_REPO\" commit -m \"update CLAUDE.md\""
TG13_INPUT=$(make_commit_input "$TG13_CMD" "$TG13_REPO")

TG13_OUTPUT=$(echo "$TG13_INPUT" | bash "$HOOKS_DIR/pre-bash.sh" 2>/dev/null) || true

assert_deny "$TG13_OUTPUT" "TG13" "governance\|DEC-RECK-011"

git -C "$TG13_REPO" reset HEAD 2>/dev/null || true

# TG14: git commit with ARCHITECTURE.md staged on main → governance deny
run_test "TG14: git commit with ARCHITECTURE.md staged on main → governance deny"

TG14_REPO=$(make_main_repo)
echo "# Architecture content" > "$TG14_REPO/ARCHITECTURE.md"
git -C "$TG14_REPO" add ARCHITECTURE.md

TG14_CMD="git -C \"$TG14_REPO\" commit -m \"update ARCHITECTURE.md\""
TG14_INPUT=$(make_commit_input "$TG14_CMD" "$TG14_REPO")

TG14_OUTPUT=$(echo "$TG14_INPUT" | bash "$HOOKS_DIR/pre-bash.sh" 2>/dev/null) || true

assert_deny "$TG14_OUTPUT" "TG14" "governance\|DEC-RECK-011"

git -C "$TG14_REPO" reset HEAD 2>/dev/null || true

# TG15: git commit with ONLY untracked MASTER_PLAN.md on main → allow (bootstrap)
run_test "TG15: git commit with ONLY untracked MASTER_PLAN.md on main → allow (bootstrap)"

TG15_REPO=$(make_main_repo)
# MASTER_PLAN.md not yet committed (bootstrap case)
echo "# Master Plan" > "$TG15_REPO/MASTER_PLAN.md"
git -C "$TG15_REPO" add MASTER_PLAN.md

TG15_CMD="git -C \"$TG15_REPO\" commit -m \"init: add MASTER_PLAN.md\""
TG15_INPUT=$(make_commit_input "$TG15_CMD" "$TG15_REPO")

TG15_OUTPUT=$(echo "$TG15_INPUT" | bash "$HOOKS_DIR/pre-bash.sh" 2>/dev/null) || true

# Bootstrap case: MASTER_PLAN.md not tracked yet → allowed (Check 2 bootstrap exception)
assert_allow "$TG15_OUTPUT" "TG15"

git -C "$TG15_REPO" reset HEAD 2>/dev/null || true

# TG16: git commit on feature branch with governance files → allow
run_test "TG16: git commit on feature branch with governance files → allow"

TG16_REPO=$(make_feature_repo)
mkdir -p "$TG16_REPO/agents"
# Need an initial commit on the feature branch
echo "# base" > "$TG16_REPO/base.md"
git -C "$TG16_REPO" add base.md
git -C "$TG16_REPO" commit -q -m "Initial"
# Now stage the governance file
echo "# Agent doc" > "$TG16_REPO/agents/implementer.md"
git -C "$TG16_REPO" add agents/implementer.md

TG16_CMD="git -C \"$TG16_REPO\" commit -m \"add implementer.md in worktree\""
TG16_INPUT=$(make_commit_input "$TG16_CMD" "$TG16_REPO")

TG16_OUTPUT=$(echo "$TG16_INPUT" | bash "$HOOKS_DIR/pre-bash.sh" 2>/dev/null) || true

# Feature branch: governance files allowed to commit
assert_allow "$TG16_OUTPUT" "TG16"

git -C "$TG16_REPO" reset HEAD 2>/dev/null || true

# ===========================================================================
# SOURCE-LEVEL STRUCTURAL CHECKS
# ===========================================================================

echo ""
echo "--- Structural source checks ---"

run_test "Source: pre-write.sh contains DEC-RECK-011 annotation"
if grep -q 'DEC-RECK-011' "$HOOKS_DIR/pre-write.sh"; then
    pass_test
else
    fail_test "DEC-RECK-011 annotation not found in pre-write.sh"
fi

run_test "Source: pre-write.sh checks agents/*.md pattern"
if grep -q 'agents/\[^/\]' "$HOOKS_DIR/pre-write.sh"; then
    pass_test
else
    fail_test "agents/*.md pattern not found in pre-write.sh"
fi

run_test "Source: pre-write.sh checks CLAUDE.md"
if grep -q 'CLAUDE\.md' "$HOOKS_DIR/pre-write.sh"; then
    pass_test
else
    fail_test "CLAUDE.md check not found in pre-write.sh"
fi

run_test "Source: task-track.sh contains DEC-RECK-011b annotation"
if grep -q 'DEC-RECK-011b' "$HOOKS_DIR/task-track.sh"; then
    pass_test
else
    fail_test "DEC-RECK-011b annotation not found in task-track.sh"
fi

run_test "Source: task-track.sh checks staged files for @plan-update bypass"
if grep -q '_NON_PLAN_FILES' "$HOOKS_DIR/task-track.sh"; then
    pass_test
else
    fail_test "_NON_PLAN_FILES check not found in task-track.sh"
fi

run_test "Source: pre-bash.sh contains DEC-RECK-011 reference"
if grep -q 'DEC-RECK-011' "$HOOKS_DIR/pre-bash.sh"; then
    pass_test
else
    fail_test "DEC-RECK-011 reference not found in pre-bash.sh"
fi

run_test "Source: pre-bash.sh checks governance files in staged list"
if grep -q '_C2_GOV_FILES' "$HOOKS_DIR/pre-bash.sh"; then
    pass_test
else
    fail_test "_C2_GOV_FILES check not found in pre-bash.sh"
fi

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
echo "========================================"

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
exit 0
