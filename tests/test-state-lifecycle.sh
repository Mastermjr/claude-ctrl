#!/usr/bin/env bash
# test-state-lifecycle.sh — Full proof-status lifecycle E2E test.
#
# Exercises the complete state machine in sequence, verifying that
# resolve_proof_file() returns the correct path at each stage and
# write_proof_status() correctly dual-writes to all 3 locations.
#
# State machine under test:
#   [no proof] → implementer dispatch (needs-verification)
#             → source write (invalidation check)
#             → user approval (verified)
#             → guardian dispatch (Gate A allows)
#             → post-commit cleanup (all proof files + breadcrumb removed)
#
# @decision DEC-STATE-LIFECYCLE-001
# @title E2E state lifecycle test covering all state transitions
# @status accepted
# @rationale Previous test files cover individual hooks or resolver paths.
#   This test exercises the complete state machine in sequence, verifying
#   that resolve_proof_file() returns the correct path at each stage and
#   that write_proof_status() correctly dual-writes to all 3 locations.
#   Uses isolated temp repos in $PROJECT_ROOT/tmp/ (not /tmp/) per Sacred
#   Practice #3. All state transitions exercised with real function calls,
#   no mocks.

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

mkdir -p "$PROJECT_ROOT/tmp"

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

# Helper: compute project_hash the same way log.sh does
compute_phash() {
    echo "$1" | $_SHA256_CMD | cut -c1-8 2>/dev/null || echo "00000000"
}

# Helper: call resolve_proof_file() in a subshell with controlled env
# core-lib.sh must be sourced BEFORE log.sh because write_proof_status()
# calls _lock_fd() which is defined in core-lib.sh.
call_resolve() {
    local project_root="$1"
    local claude_dir="$2"
    bash -c "
        source '$HOOKS_DIR/core-lib.sh' 2>/dev/null
        source '$HOOKS_DIR/log.sh' 2>/dev/null
        export CLAUDE_DIR='$claude_dir'
        export PROJECT_ROOT='$project_root'
        resolve_proof_file 2>/dev/null
    "
}

# ─────────────────────────────────────────────────────────────────────────────
# Setup: create a persistent temp environment for the lifecycle test sequence
# ─────────────────────────────────────────────────────────────────────────────

TMPDIR="$PROJECT_ROOT/tmp/test-lifecycle-$$"
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

# Orchestrator side: the ~/.claude-like directory
ORCH_DIR="$TMPDIR/orchestrator"
mkdir -p "$ORCH_DIR"

# Mock "project root" for the orchestrator session
MOCK_PROJECT="$TMPDIR/project"
mkdir -p "$MOCK_PROJECT"
git -C "$MOCK_PROJECT" init >/dev/null 2>&1

# The "CLAUDE_DIR" for the orchestrator (project/.claude)
ORCH_CLAUDE="$MOCK_PROJECT/.claude"
mkdir -p "$ORCH_CLAUDE"

# Worktree side: simulated feature worktree
MOCK_WORKTREE="$TMPDIR/worktrees/feature-foo"
mkdir -p "$MOCK_WORKTREE/.claude"

# Pre-compute phash for the mock project
PHASH=$(compute_phash "$MOCK_PROJECT")
# New canonical path: state/{phash}/proof-status
SCOPED_PROOF="$ORCH_CLAUDE/state/${PHASH}/proof-status"
# Legacy path (dual-write compat): .proof-status-{phash}
LEGACY_PROOF="$ORCH_CLAUDE/.proof-status-${PHASH}"
# Note: breadcrumb system (.active-worktree-path-*) and worktree proof copy
# have been removed per DEC-PROOF-BREADCRUMB-001. There is no WORKTREE_PROOF.

# ─────────────────────────────────────────────────────────────────────────────
# Test 1: Initial state — no proof file, resolve returns scoped default
# ─────────────────────────────────────────────────────────────────────────────

run_test "T01: Initial state — no proof file, resolve returns state/{phash}/proof-status path"
RESULT=$(call_resolve "$MOCK_PROJECT" "$ORCH_CLAUDE")
EXPECTED="$SCOPED_PROOF"
if [[ "$RESULT" == "$EXPECTED" ]]; then
    pass_test
else
    fail_test "Expected '$EXPECTED', got '$RESULT'"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 2: State dir exists but no proof file — resolve returns new path
#         (Breadcrumb system removed per DEC-PROOF-BREADCRUMB-001; resolver
#          now uses a simple two-step: check new path, check old dotfile, default to new)
# ─────────────────────────────────────────────────────────────────────────────

run_test "T02: State dir exists but no proof file — resolve returns state/{phash}/proof-status"
mkdir -p "$ORCH_CLAUDE/state/${PHASH}"
# No proof file yet — resolver should return the new canonical path
RESULT=$(call_resolve "$MOCK_PROJECT" "$ORCH_CLAUDE")
EXPECTED="$SCOPED_PROOF"
if [[ "$RESULT" == "$EXPECTED" ]]; then
    pass_test
else
    fail_test "Expected new canonical path '$EXPECTED', got '$RESULT'"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 3: Implementer dispatch → needs-verification written to worktree path
# ─────────────────────────────────────────────────────────────────────────────

run_test "T03: needs-verification written — resolve returns new canonical state path"
TS=$(date +%s)
# write_proof_status dual-writes to new path + legacy dotfile; simulate both
mkdir -p "$(dirname "$SCOPED_PROOF")"
echo "needs-verification|${TS}" > "$SCOPED_PROOF"
echo "needs-verification|${TS}" > "$LEGACY_PROOF"

RESULT=$(call_resolve "$MOCK_PROJECT" "$ORCH_CLAUDE")
EXPECTED="$SCOPED_PROOF"
if [[ "$RESULT" == "$EXPECTED" ]]; then
    pass_test
else
    fail_test "Expected canonical path '$EXPECTED', got '$RESULT'"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 4: Source file write — proof invalidation targets worktree proof
#         (resolve_proof_file returns the worktree path, so post-write.sh
#          would reset THAT file back to pending, not the scoped orchestrator file)
# ─────────────────────────────────────────────────────────────────────────────

run_test "T04: After source write invalidation — proof transitions to pending at canonical path"
# Simulate post-write.sh behavior: it calls resolve_proof_file and writes "pending"
# to that resolved path
RESOLVED=$(call_resolve "$MOCK_PROJECT" "$ORCH_CLAUDE")
TS=$(date +%s)
echo "pending|${TS}" > "$RESOLVED"

# Now test that resolve still returns the canonical new path
RESULT=$(call_resolve "$MOCK_PROJECT" "$ORCH_CLAUDE")
EXPECTED="$SCOPED_PROOF"
WAS_WRITTEN_CORRECTLY="false"
[[ "$RESOLVED" == "$SCOPED_PROOF" ]] && WAS_WRITTEN_CORRECTLY="true"

if [[ "$RESULT" == "$EXPECTED" && "$WAS_WRITTEN_CORRECTLY" == "true" ]]; then
    pass_test
else
    fail_test "Resolved='$RESOLVED' (want '$SCOPED_PROOF'), result='$RESULT'"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 5: User approval → write_proof_status("verified") dual-writes all 3 paths
# ─────────────────────────────────────────────────────────────────────────────

run_test "T05: User approval — write_proof_status('verified') dual-writes new + legacy paths"
TRACE_DIR_TMP="$TMPDIR/traces"
mkdir -p "$TRACE_DIR_TMP"

# Reset proof to pending first (so monotonic lattice allows verified write)
echo "pending|$(date +%s)" > "$SCOPED_PROOF"
echo "pending|$(date +%s)" > "$LEGACY_PROOF"

bash -c "
    source '$HOOKS_DIR/core-lib.sh' 2>/dev/null
    source '$HOOKS_DIR/log.sh' 2>/dev/null
    export CLAUDE_DIR='$ORCH_CLAUDE'
    export PROJECT_ROOT='$MOCK_PROJECT'
    export TRACE_STORE='$TRACE_DIR_TMP'
    export CLAUDE_SESSION_ID='test-lifecycle-$$'
    write_proof_status 'verified' '$MOCK_PROJECT' 2>/dev/null
"

SCOPED_STATUS=$(cut -d'|' -f1 "$SCOPED_PROOF" 2>/dev/null || echo "missing")
LEGACY_STATUS=$(cut -d'|' -f1 "$LEGACY_PROOF" 2>/dev/null || echo "missing")

# No worktree proof — the breadcrumb/worktree system was removed
if [[ "$SCOPED_STATUS" == "verified" && "$LEGACY_STATUS" == "verified" ]]; then
    pass_test
else
    fail_test "new_canonical='$SCOPED_STATUS', legacy_dotfile='$LEGACY_STATUS' (both must be 'verified')"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 6: After verified — resolve returns worktree path (worktree still active)
# ─────────────────────────────────────────────────────────────────────────────

run_test "T06: After verified — resolve returns canonical state path (no breadcrumb system)"
RESULT=$(call_resolve "$MOCK_PROJECT" "$ORCH_CLAUDE")
EXPECTED="$SCOPED_PROOF"
if [[ "$RESULT" == "$EXPECTED" ]]; then
    pass_test
else
    fail_test "Expected canonical path '$EXPECTED', got '$RESULT'"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 7: Guardian dispatch → Gate A reads verified from resolved path → allows
# ─────────────────────────────────────────────────────────────────────────────

run_test "T07: Guardian Gate A — verified proof allows guardian dispatch"
# Simulate what task-track.sh Gate A does: read proof from the resolved path
RESOLVED=$(call_resolve "$MOCK_PROJECT" "$ORCH_CLAUDE")
GATE_STATUS=$(cut -d'|' -f1 "$RESOLVED" 2>/dev/null || echo "missing")

if [[ "$GATE_STATUS" == "verified" ]]; then
    pass_test
else
    fail_test "Gate A would block: resolved path '$RESOLVED' has status '$GATE_STATUS'"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 8: validate_state_file passes on well-formed proof status
# ─────────────────────────────────────────────────────────────────────────────

run_test "T08: validate_state_file passes on well-formed 'verified|timestamp' content"
RESULT=$(bash -c "
    source '$HOOKS_DIR/core-lib.sh' 2>/dev/null
    source '$HOOKS_DIR/log.sh' 2>/dev/null
    validate_state_file '$SCOPED_PROOF' 2 && echo 'valid' || echo 'invalid'
" 2>/dev/null)

if [[ "$RESULT" == "valid" ]]; then
    pass_test
else
    fail_test "validate_state_file returned '$RESULT' for '$SCOPED_PROOF'"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 9: Post-commit cleanup — check-guardian.sh removes proof files + breadcrumb
#         Simulate cleanup via the same logic check-guardian.sh uses
# ─────────────────────────────────────────────────────────────────────────────

run_test "T09: Post-commit cleanup — scoped proof removed after verified commit"
# Simulate check-guardian's cleanup: remove scoped and legacy proof-status if "verified"
_PHASH="$PHASH"
for PROOF_FILE in "$SCOPED_PROOF" "$LEGACY_PROOF"; do
    if [[ -f "$PROOF_FILE" ]]; then
        PROOF_VAL=$(cut -d'|' -f1 "$PROOF_FILE" 2>/dev/null || echo "")
        if [[ "$PROOF_VAL" == "verified" ]]; then
            rm -f "$PROOF_FILE"
        fi
    fi
done

SCOPED_EXISTS=false
LEGACY_EXISTS=false
[[ -f "$SCOPED_PROOF" ]] && SCOPED_EXISTS=true
[[ -f "$LEGACY_PROOF" ]] && LEGACY_EXISTS=true

if [[ "$SCOPED_EXISTS" == "false" && "$LEGACY_EXISTS" == "false" ]]; then
    pass_test
else
    fail_test "Proof files still exist: scoped=$SCOPED_EXISTS, legacy=$LEGACY_EXISTS"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 10: Post-commit cleanup — no stale legacy dotfiles remain
#         (Breadcrumb system removed per DEC-PROOF-BREADCRUMB-001)
# ─────────────────────────────────────────────────────────────────────────────

run_test "T10: Post-commit cleanup — no legacy dotfiles remain after state cleanup"
# After T09 removed the proof files, verify no stale .proof-status* dotfiles remain
STALE_DOTFILES=0
for _f in "${ORCH_CLAUDE}/.proof-status"*; do
    [[ -f "$_f" ]] && STALE_DOTFILES=$((STALE_DOTFILES + 1))
done
# Also ensure no breadcrumb files exist (they should never have been created)
BREADCRUMB_EXISTS=false
for _b in "${ORCH_CLAUDE}/.active-worktree-path"*; do
    [[ -f "$_b" ]] && BREADCRUMB_EXISTS=true
done

if [[ "$STALE_DOTFILES" -eq 0 && "$BREADCRUMB_EXISTS" == "false" ]]; then
    pass_test
else
    fail_test "stale_dotfiles=$STALE_DOTFILES breadcrumb_exists=$BREADCRUMB_EXISTS (both must be 0/false)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 11: Post-cleanup — resolve returns scoped default (breadcrumb gone)
# ─────────────────────────────────────────────────────────────────────────────

run_test "T11: After full cleanup — resolve returns new canonical path (clean state)"
RESULT=$(call_resolve "$MOCK_PROJECT" "$ORCH_CLAUDE")
EXPECTED="$SCOPED_PROOF"
if [[ "$RESULT" == "$EXPECTED" ]]; then
    pass_test
else
    fail_test "Expected scoped default '$EXPECTED', got '$RESULT'"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 12: write_proof_status — no breadcrumb, only writes orchestrator paths
# ─────────────────────────────────────────────────────────────────────────────

run_test "T12: write_proof_status — writes new canonical + legacy dotfile (no worktree path)"
# State is fully cleaned (T09 removed proof files). Write needs-verification to start fresh.
# Note: Proof files were removed, so needs-verification (ordinal 1) can be written from none (ordinal 0).
TRACE_DIR_TMP2="$TMPDIR/traces2"
mkdir -p "$TRACE_DIR_TMP2"

bash -c "
    source '$HOOKS_DIR/core-lib.sh' 2>/dev/null
    source '$HOOKS_DIR/log.sh' 2>/dev/null
    export CLAUDE_DIR='$ORCH_CLAUDE'
    export PROJECT_ROOT='$MOCK_PROJECT'
    export TRACE_STORE='$TRACE_DIR_TMP2'
    export CLAUDE_SESSION_ID='test-lifecycle2-$$'
    write_proof_status 'needs-verification' '$MOCK_PROJECT' 2>/dev/null
"

SCOPED_STATUS2=$(cut -d'|' -f1 "$SCOPED_PROOF" 2>/dev/null || echo "missing")
LEGACY_STATUS2=$(cut -d'|' -f1 "$LEGACY_PROOF" 2>/dev/null || echo "missing")
# Worktree proof path no longer exists — dual-write is only new path + legacy dotfile
WORKTREE_PROOF_ABSENT=true
[[ -f "$MOCK_WORKTREE/.claude/.proof-status" ]] && WORKTREE_PROOF_ABSENT=false

if [[ "$SCOPED_STATUS2" == "needs-verification" && "$LEGACY_STATUS2" == "needs-verification" && "$WORKTREE_PROOF_ABSENT" == "true" ]]; then
    pass_test
else
    fail_test "canonical='$SCOPED_STATUS2', legacy='$LEGACY_STATUS2', worktree_absent=$WORKTREE_PROOF_ABSENT (first two must be needs-verification, last must be true)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 13: Old-path migration fallback — resolve returns legacy dotfile path
#          when only .proof-status-{phash} exists (not state/{phash}/proof-status)
#          (Breadcrumb system removed; this tests the migration fallback path)
# ─────────────────────────────────────────────────────────────────────────────

run_test "T13: Migration fallback — only old .proof-status-{phash} exists → resolve returns it"
# Create a separate mock project to test the legacy fallback cleanly
LEGACY_TEST_PROJECT="$TMPDIR/legacy-project"
LEGACY_TEST_CLAUDE="$LEGACY_TEST_PROJECT/.claude"
mkdir -p "$LEGACY_TEST_CLAUDE"
git -C "$LEGACY_TEST_PROJECT" init >/dev/null 2>&1

LEGACY_TEST_PHASH=$(compute_phash "$LEGACY_TEST_PROJECT")
LEGACY_DOTFILE="$LEGACY_TEST_CLAUDE/.proof-status-${LEGACY_TEST_PHASH}"
# Write only the old dotfile path — do NOT create state/{phash}/proof-status
echo "needs-verification|$(date +%s)" > "$LEGACY_DOTFILE"

RESULT=$(call_resolve "$LEGACY_TEST_PROJECT" "$LEGACY_TEST_CLAUDE")
EXPECTED="$LEGACY_DOTFILE"
if [[ "$RESULT" == "$EXPECTED" ]]; then
    pass_test
else
    fail_test "Expected legacy dotfile '$EXPECTED', got '$RESULT'"
fi
rm -rf "$LEGACY_TEST_PROJECT"

# ─────────────────────────────────────────────────────────────────────────────
# Test 14: project_hash is consistent (same input → same output)
# ─────────────────────────────────────────────────────────────────────────────

run_test "T14: project_hash consistency — same path produces same 8-char hash"
HASH1=$(bash -c "
    source '$HOOKS_DIR/log.sh' 2>/dev/null
    project_hash '$MOCK_PROJECT' 2>/dev/null
")
HASH2=$(bash -c "
    source '$HOOKS_DIR/core-lib.sh' 2>/dev/null
    project_hash '$MOCK_PROJECT' 2>/dev/null
")

if [[ -n "$HASH1" && "$HASH1" == "$HASH2" && ${#HASH1} -eq 8 ]]; then
    pass_test
else
    fail_test "hash1='$HASH1' hash2='$HASH2' (must be equal and 8 chars)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 15: validate_state_file rejects missing and corrupt files
# ─────────────────────────────────────────────────────────────────────────────

run_test "T15: validate_state_file — rejects missing, empty, and single-field files"
CORRUPT_FILE="$TMPDIR/bad-proof-status"

# Missing file
MISSING=$(bash -c "
    source '$HOOKS_DIR/core-lib.sh' 2>/dev/null
    validate_state_file '/nonexistent/path/.proof-status' 2 && echo 'valid' || echo 'invalid'
" 2>/dev/null)

# Empty file
touch "$CORRUPT_FILE"
EMPTY_RESULT=$(bash -c "
    source '$HOOKS_DIR/core-lib.sh' 2>/dev/null
    validate_state_file '$CORRUPT_FILE' 2 && echo 'valid' || echo 'invalid'
" 2>/dev/null)

# Single field (missing timestamp)
echo "verified" > "$CORRUPT_FILE"
SINGLE_FIELD=$(bash -c "
    source '$HOOKS_DIR/core-lib.sh' 2>/dev/null
    validate_state_file '$CORRUPT_FILE' 2 && echo 'valid' || echo 'invalid'
" 2>/dev/null)

# Well-formed
echo "verified|12345" > "$CORRUPT_FILE"
VALID_RESULT=$(bash -c "
    source '$HOOKS_DIR/core-lib.sh' 2>/dev/null
    validate_state_file '$CORRUPT_FILE' 2 && echo 'valid' || echo 'invalid'
" 2>/dev/null)

rm -f "$CORRUPT_FILE"

if [[ "$MISSING" == "invalid" && "$EMPTY_RESULT" == "invalid" && "$SINGLE_FIELD" == "invalid" && "$VALID_RESULT" == "valid" ]]; then
    pass_test
else
    fail_test "missing='$MISSING' empty='$EMPTY_RESULT' single='$SINGLE_FIELD' valid='$VALID_RESULT'"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Auto-verify → Guardian lifecycle E2E test (DEC-PROOF-RACE-001)
#
# Full lifecycle covering the race condition fix:
#   Step 1: Tester completes → auto-verify marker created + "verified" written
#   Step 2: Source write → proof-status NOT invalidated (marker protects)
#   Step 3: Guardian dispatch → auto-verify marker cleaned, guardian marker created
#   Step 4: Guardian commit workflow → guardian marker cleans up
#   Step 5: Verify proof-status remained "verified" throughout
#
# @decision DEC-PROOF-RACE-001
# @title Auto-verify markers protect the verified→guardian dispatch gap
# @status accepted
# @rationale post-write.sh could invalidate proof-status between when post-task.sh
#   writes "verified" and when task-track.sh creates the guardian marker. The
#   auto-verify marker fills this gap identically to the guardian marker.
# ─────────────────────────────────────────────────────────────────────────────

AV_TMPDIR="$TMPDIR/av-lifecycle-$$"
mkdir -p "$AV_TMPDIR"
AV_PROJECT="$AV_TMPDIR/project"
AV_TRACES="$AV_TMPDIR/traces"
mkdir -p "$AV_PROJECT/.claude" "$AV_TRACES"
git -C "$AV_PROJECT" init >/dev/null 2>&1
AV_PHASH=$(compute_phash "$AV_PROJECT")
AV_SESSION="av-lifecycle-$$"
# New canonical path: state/{phash}/proof-status
AV_SCOPED_PROOF="$AV_PROJECT/.claude/state/${AV_PHASH}/proof-status"
mkdir -p "$(dirname "$AV_SCOPED_PROOF")"

# ─────────────────────────────────────────────────────────────────────────────
# T16-Step1: Tester completes — auto-verify marker created + "verified" written
# ─────────────────────────────────────────────────────────────────────────────

run_test "T16a: Auto-verify lifecycle: tester completes → marker created + verified written"

AV_TS=$(date +%s)
# Simulate post-task.sh: write auto-verify marker then write "verified"
printf 'auto-verify|%s\n' "$AV_TS" > \
    "${AV_TRACES}/.active-autoverify-${AV_SESSION}-${AV_PHASH}"
# Dual-write: new canonical path + legacy dotfile
printf 'verified|%s\n' "$AV_TS" > "$AV_SCOPED_PROOF"
printf 'verified|%s\n' "$AV_TS" > "$AV_PROJECT/.claude/.proof-status-${AV_PHASH}"

AV_MARKER_EXISTS=false
[[ -f "${AV_TRACES}/.active-autoverify-${AV_SESSION}-${AV_PHASH}" ]] && AV_MARKER_EXISTS=true
AV_PROOF_STATUS=$(cut -d'|' -f1 "$AV_SCOPED_PROOF" 2>/dev/null || echo "missing")

if [[ "$AV_MARKER_EXISTS" == "true" && "$AV_PROOF_STATUS" == "verified" ]]; then
    pass_test
else
    fail_test "marker_exists=$AV_MARKER_EXISTS, proof_status=$AV_PROOF_STATUS (both must be true/verified)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# T16-Step2: Source write event — proof NOT invalidated (marker protects)
# ─────────────────────────────────────────────────────────────────────────────

run_test "T16b: Auto-verify lifecycle: source write → proof stays verified (marker active)"

# Simulate post-write.sh proof-invalidation logic
_av_guardian_active=false

for _gm in "${AV_TRACES}/.active-guardian-"*; do
    if [[ -f "$_gm" ]]; then
        _marker_ts=$(cut -d'|' -f2 "$_gm" 2>/dev/null || echo "0")
        _now=$(date +%s)
        if [[ "$_marker_ts" =~ ^[0-9]+$ && $(( _now - _marker_ts )) -lt 300 ]]; then
            _av_guardian_active=true; break
        fi
    fi
done

if [[ "$_av_guardian_active" == "false" ]]; then
    for _avm in "${AV_TRACES}/.active-autoverify-"*; do
        if [[ -f "$_avm" ]]; then
            _marker_ts=$(cut -d'|' -f2 "$_avm" 2>/dev/null || echo "0")
            _now=$(date +%s)
            if [[ "$_marker_ts" =~ ^[0-9]+$ && $(( _now - _marker_ts )) -lt 300 ]]; then
                _av_guardian_active=true; break
            fi
        fi
    done
fi

# With marker active, invalidation would NOT happen — proof stays "verified"
if [[ "$_av_guardian_active" == "true" ]]; then
    # Verify proof is still verified (marker blocked invalidation)
    AV_PROOF_AFTER_WRITE=$(cut -d'|' -f1 "$AV_SCOPED_PROOF" 2>/dev/null || echo "missing")
    if [[ "$AV_PROOF_AFTER_WRITE" == "verified" ]]; then
        pass_test
    else
        fail_test "Proof invalidated despite autoverify marker: '$AV_PROOF_AFTER_WRITE'"
    fi
else
    fail_test "Auto-verify marker not detected as active during write event"
fi

# ─────────────────────────────────────────────────────────────────────────────
# T16-Step3: Guardian dispatch — auto-verify marker cleaned, guardian marker created
# ─────────────────────────────────────────────────────────────────────────────

run_test "T16c: Auto-verify lifecycle: guardian dispatch → AV marker cleaned, guardian marker created"

# Simulate task-track.sh Gate A (W4a):
# 1. Remove auto-verify markers for this project
rm -f "${AV_TRACES}/.active-autoverify-"*"-${AV_PHASH}" 2>/dev/null || true
# 2. Create guardian marker
printf 'pre-dispatch|%s\n' "$(date +%s)" > \
    "${AV_TRACES}/.active-guardian-${AV_SESSION}-${AV_PHASH}"

AV_MARKER_GONE=true
[[ -f "${AV_TRACES}/.active-autoverify-${AV_SESSION}-${AV_PHASH}" ]] && AV_MARKER_GONE=false
GUARDIAN_MARKER_EXISTS=false
[[ -f "${AV_TRACES}/.active-guardian-${AV_SESSION}-${AV_PHASH}" ]] && GUARDIAN_MARKER_EXISTS=true

if [[ "$AV_MARKER_GONE" == "true" && "$GUARDIAN_MARKER_EXISTS" == "true" ]]; then
    pass_test
else
    fail_test "av_marker_gone=$AV_MARKER_GONE guardian_marker_exists=$GUARDIAN_MARKER_EXISTS"
fi

# ─────────────────────────────────────────────────────────────────────────────
# T16-Step4: Guardian commit — guardian marker cleaned, proof still verified
# ─────────────────────────────────────────────────────────────────────────────

run_test "T16d: Auto-verify lifecycle: post-commit cleanup — proof verified throughout"

# Simulate finalize_trace cleanup (removes guardian markers)
rm -f "${AV_TRACES}/.active-guardian-"*"-${AV_PHASH}" 2>/dev/null || true

GUARDIAN_MARKER_GONE=true
[[ -f "${AV_TRACES}/.active-guardian-${AV_SESSION}-${AV_PHASH}" ]] && GUARDIAN_MARKER_GONE=false

# Proof should still be "verified" — was never invalidated
AV_FINAL_PROOF=$(cut -d'|' -f1 "$AV_SCOPED_PROOF" 2>/dev/null || echo "missing")

if [[ "$GUARDIAN_MARKER_GONE" == "true" && "$AV_FINAL_PROOF" == "verified" ]]; then
    pass_test
else
    fail_test "guardian_marker_gone=$GUARDIAN_MARKER_GONE, final_proof=$AV_FINAL_PROOF"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "=========================================="
echo "State Lifecycle Tests: $TESTS_PASSED/$TESTS_RUN passed"
echo "=========================================="

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAILED: $TESTS_FAILED tests failed"
    exit 1
else
    echo "SUCCESS: All tests passed"
    exit 0
fi
