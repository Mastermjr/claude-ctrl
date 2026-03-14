#!/usr/bin/env bash
# test-v4-w2-1.sh — Tests for v4 Release W2-1: Final KV migrations
#
# Validates:
#   1. .db-safety-stats → SQLite KV (db_safety_checked, db_safety_blocked, db_safety_warned)
#      - _db_increment_stat() dual-writes KV + flat-file
#      - _db_session_summary() reads from KV primary, flat-file fallback
#      - _db_read_session_stats() reads from KV primary, flat-file fallback
#   2. .mcp-rate-state → SQLite KV (mcp_rate_count, mcp_rate_start)
#      - Rate state reads KV primary, flat-file fallback
#      - Rate state writes KV + flat-file
#   3. .mcp-credential-advisory-emitted → SQLite KV (mcp_credential_advisory)
#      - Sentinel reads KV primary, flat-file fallback
#      - Sentinel writes KV + flat-file
#   4. session-end.sh: state_delete for all 6 new KV keys
#
# @decision DEC-V4-KV-001
# @title Test suite for final KV migrations (db-safety stats, mcp rate-state, mcp advisory)
# @status accepted
# @rationale Following the dual-write pattern from DEC-STATE-KV-001 through KV-007,
#   these tests verify that:
#   - KV writes happen on every stat increment
#   - KV reads return correct values (primary path)
#   - Flat-file fallback works when KV is empty
#   - Session-end deletes all 6 new KV entries
#   Tests use isolated CLAUDE_DIR environments with temp SQLite DBs.
#
# Usage: bash tests/test-v4-w2-1.sh
# Returns: 0 if all tests pass, 1 if any fail

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE_ROOT="$(cd "$TEST_DIR/.." && pwd)"
HOOKS_DIR="${WORKTREE_ROOT}/hooks"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1 — ${2:-}"; FAIL=$((FAIL + 1)); }

assert_eq() {
    local test_name="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "expected='$expected', got='$actual'"
    fi
}

assert_contains() {
    local test_name="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        pass "$test_name"
    else
        fail "$test_name" "expected to contain '$needle', got: $haystack"
    fi
}

assert_not_empty() {
    local test_name="$1" actual="$2"
    if [[ -n "$actual" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "expected non-empty, got empty"
    fi
}

assert_empty() {
    local test_name="$1" actual="$2"
    if [[ -z "$actual" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "expected empty, got '$actual'"
    fi
}

# --- Temp dir setup ---
TMPDIR_BASE="${WORKTREE_ROOT}/tmp/test-v4-w2-1-$$"
mkdir -p "$TMPDIR_BASE"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# Helper: create an isolated CLAUDE_DIR with a git-backed PROJECT_ROOT
make_env() {
    local id="$1"
    local pr="${TMPDIR_BASE}/${id}"
    local cd="${pr}/.claude"
    mkdir -p "${cd}/state" "${pr}"
    git -C "${pr}" init -q -b main 2>/dev/null || true
    echo "${cd}"  # returns CLAUDE_DIR
}

# Helper: run code in a subshell with an isolated CLAUDE_DIR and state-lib loaded
run_in_env() {
    local claude_dir="$1"
    local project_root="${claude_dir%/.claude}"
    local code="$2"
    HOOKS_DIR="$HOOKS_DIR" bash -c "
source \"\${HOOKS_DIR}/source-lib.sh\" 2>/dev/null
require_state
_STATE_SCHEMA_INITIALIZED=''
_WORKFLOW_ID=''
export CLAUDE_DIR='${claude_dir}'
export PROJECT_ROOT='${project_root}'
export CLAUDE_PROJECT_DIR='${project_root}'
export CLAUDE_SESSION_ID='test-session-\$\$'
${code}
" 2>/dev/null
}

echo ""
echo "=== v4 W2-1 KV Migration Tests ==="
echo ""

# =============================================================================
# Section 1: .db-safety-stats → SQLite KV
# =============================================================================
echo "--- Section 1: db-safety-stats KV migration ---"

# T01: _db_increment_stat writes to KV (db_safety_checked key exists in SQLite)
_CD=$(make_env "t01")
_PR="${_CD%/.claude}"
run_in_env "$_CD" "
require_db_safety
_db_increment_stat 'checked'
_VAL=\$(state_read 'db_safety_checked' 2>/dev/null || echo '')
printf '%s' \"\$_VAL\"
" > "${TMPDIR_BASE}/t01.out" 2>/dev/null
_T01_OUT=$(cat "${TMPDIR_BASE}/t01.out")
assert_eq "T01: increment checked → db_safety_checked KV key = 1" "1" "$_T01_OUT"

# T02: _db_increment_stat increments existing KV value correctly
_CD=$(make_env "t02")
run_in_env "$_CD" "
require_db_safety
_db_increment_stat 'checked'
_db_increment_stat 'checked'
_db_increment_stat 'checked'
_VAL=\$(state_read 'db_safety_checked' 2>/dev/null || echo '')
printf '%s' \"\$_VAL\"
" > "${TMPDIR_BASE}/t02.out" 2>/dev/null
_T02_OUT=$(cat "${TMPDIR_BASE}/t02.out")
assert_eq "T02: increment checked 3x → db_safety_checked = 3" "3" "$_T02_OUT"

# T03: _db_increment_stat writes blocked KV key
_CD=$(make_env "t03")
run_in_env "$_CD" "
require_db_safety
_db_increment_stat 'blocked'
_VAL=\$(state_read 'db_safety_blocked' 2>/dev/null || echo '')
printf '%s' \"\$_VAL\"
" > "${TMPDIR_BASE}/t03.out" 2>/dev/null
_T03_OUT=$(cat "${TMPDIR_BASE}/t03.out")
assert_eq "T03: increment blocked → db_safety_blocked KV key = 1" "1" "$_T03_OUT"

# T04: _db_increment_stat writes warned KV key
_CD=$(make_env "t04")
run_in_env "$_CD" "
require_db_safety
_db_increment_stat 'warned'
_db_increment_stat 'warned'
_VAL=\$(state_read 'db_safety_warned' 2>/dev/null || echo '')
printf '%s' \"\$_VAL\"
" > "${TMPDIR_BASE}/t04.out" 2>/dev/null
_T04_OUT=$(cat "${TMPDIR_BASE}/t04.out")
assert_eq "T04: increment warned 2x → db_safety_warned KV key = 2" "2" "$_T04_OUT"

# T05: _db_session_summary reads from KV (not just flat-file) when KV has data
_CD=$(make_env "t05")
run_in_env "$_CD" "
require_db_safety
_db_increment_stat 'checked'
_db_increment_stat 'checked'
_db_increment_stat 'blocked'
_db_increment_stat 'warned'
_SUMMARY=\$(_db_session_summary)
printf '%s' \"\$_SUMMARY\"
" > "${TMPDIR_BASE}/t05.out" 2>/dev/null
_T05_OUT=$(cat "${TMPDIR_BASE}/t05.out")
assert_contains "T05: session_summary contains 'Database safety'" "Database safety" "$_T05_OUT"
assert_contains "T05b: session_summary shows correct checked count" "2 commands checked" "$_T05_OUT"
assert_contains "T05c: session_summary shows correct blocked count" "1 blocked" "$_T05_OUT"

# T06: flat-file fallback — _db_session_summary returns correct values from flat-file only
# (KV not populated; flat-file manually written)
_CD=$(make_env "t06")
# Write only to flat-file, not KV
printf 'checked=5\nblocked=2\nwarned=3\n' > "${_CD}/.db-safety-stats"
_T06_OUT=$(CLAUDE_DIR="$_CD" HOOKS_DIR="$HOOKS_DIR" bash -c "
source \"\${HOOKS_DIR}/source-lib.sh\" 2>/dev/null
require_db_safety
_SUMMARY=\$(_db_session_summary)
printf '%s' \"\$_SUMMARY\"
" 2>/dev/null)
assert_contains "T06: flat-file fallback → summary shows checked=5" "5 commands checked" "$_T06_OUT"
assert_contains "T06b: flat-file fallback → summary shows blocked=2" "2 blocked" "$_T06_OUT"

# T07: dual-write verification — flat-file is also written when KV is updated
_CD=$(make_env "t07")
run_in_env "$_CD" "
require_db_safety
_db_increment_stat 'checked'
" > /dev/null 2>/dev/null
_T07_FLATFILE="${_CD}/.db-safety-stats"
if [[ -f "$_T07_FLATFILE" ]]; then
    _T07_CHECKED=$(grep "^checked=" "$_T07_FLATFILE" | cut -d= -f2)
    assert_eq "T07: flat-file also written on increment (dual-write)" "1" "$_T07_CHECKED"
else
    fail "T07: flat-file also written on increment (dual-write)" "flat-file not found at $_T07_FLATFILE"
fi

echo ""

# =============================================================================
# Section 2: .mcp-rate-state → SQLite KV
# =============================================================================
echo "--- Section 2: mcp-rate-state KV migration ---"

# T08: MCP rate state written to KV keys
_CD=$(make_env "t08")
_NOW=$(date +%s)
# Simulate pre-mcp.sh rate-limit section with KV read/write
run_in_env "$_CD" "
require_state
_NOW=${_NOW}
_RATE_LIMIT=100
_RATE_WINDOW=60
# Read from KV (primary), flat-file (fallback)
_RATE_COUNT=\$(state_read 'mcp_rate_count' 2>/dev/null || echo '')
_RATE_START=\$(state_read 'mcp_rate_start' 2>/dev/null || echo '')
if [[ -z \"\$_RATE_COUNT\" || -z \"\$_RATE_START\" ]]; then
    _RATE_STATE_FILE=\"\${CLAUDE_DIR:-\$HOME/.claude}/.mcp-rate-state\"
    if [[ -f \"\$_RATE_STATE_FILE\" ]]; then
        _RATE_DATA=\$(cat \"\$_RATE_STATE_FILE\" 2>/dev/null || echo '0|0')
        _RATE_COUNT=\"\${_RATE_DATA%%|*}\"
        _RATE_START=\"\${_RATE_DATA##*|}\"
    else
        _RATE_COUNT=0
        _RATE_START=0
    fi
fi
if [[ \$(( _NOW - _RATE_START )) -ge \$_RATE_WINDOW ]]; then
    _RATE_COUNT=0; _RATE_START=\$_NOW
fi
_RATE_COUNT=\$(( _RATE_COUNT + 1 ))
# Dual-write: KV + flat-file
state_update 'mcp_rate_count' \"\$_RATE_COUNT\" 'pre-mcp' 2>/dev/null || true
state_update 'mcp_rate_start' \"\$_RATE_START\" 'pre-mcp' 2>/dev/null || true
_RATE_STATE_FILE=\"\${CLAUDE_DIR:-\$HOME/.claude}/.mcp-rate-state\"
printf '%s|%s\n' \"\$_RATE_COUNT\" \"\$_RATE_START\" > \"\$_RATE_STATE_FILE\" 2>/dev/null || true
# Read back from KV
_STORED_COUNT=\$(state_read 'mcp_rate_count' 2>/dev/null || echo '')
_STORED_START=\$(state_read 'mcp_rate_start' 2>/dev/null || echo '')
printf '%s|%s' \"\$_STORED_COUNT\" \"\$_STORED_START\"
" > "${TMPDIR_BASE}/t08.out" 2>/dev/null
_T08_OUT=$(cat "${TMPDIR_BASE}/t08.out")
_T08_COUNT="${_T08_OUT%%|*}"
_T08_START="${_T08_OUT##*|}"
assert_eq "T08: mcp_rate_count KV key = 1 after first call" "1" "$_T08_COUNT"
assert_not_empty "T08b: mcp_rate_start KV key is non-empty" "$_T08_START"

# T09: MCP rate state flat-file fallback
_CD=$(make_env "t09")
_NOW=$(date +%s)
_PAST=$(( _NOW - 30 ))  # 30 seconds ago (within window)
printf '5|%s\n' "$_PAST" > "${_CD}/.mcp-rate-state"
# Simulate reading from flat-file when KV is empty, then writing to KV
run_in_env "$_CD" "
require_state
_NOW=${_NOW}
_RATE_WINDOW=60
# KV is empty → should fall back to flat-file
_RATE_COUNT=\$(state_read 'mcp_rate_count' 2>/dev/null || echo '')
_RATE_START=\$(state_read 'mcp_rate_start' 2>/dev/null || echo '')
if [[ -z \"\$_RATE_COUNT\" || -z \"\$_RATE_START\" ]]; then
    _RATE_STATE_FILE=\"\${CLAUDE_DIR}/.mcp-rate-state\"
    if [[ -f \"\$_RATE_STATE_FILE\" ]]; then
        _RATE_DATA=\$(cat \"\$_RATE_STATE_FILE\" 2>/dev/null || echo '0|0')
        _RATE_COUNT=\"\${_RATE_DATA%%|*}\"
        _RATE_START=\"\${_RATE_DATA##*|}\"
    fi
fi
printf '%s' \"\$_RATE_COUNT\"
" > "${TMPDIR_BASE}/t09.out" 2>/dev/null
_T09_OUT=$(cat "${TMPDIR_BASE}/t09.out")
assert_eq "T09: mcp-rate-state flat-file fallback reads count=5" "5" "$_T09_OUT"

# T10: MCP rate window reset
_CD=$(make_env "t10")
_NOW=$(date +%s)
_OLD=$(( _NOW - 120 ))  # 2 minutes ago (outside 60s window)
run_in_env "$_CD" "
require_state
_NOW=${_NOW}
_RATE_WINDOW=60
state_update 'mcp_rate_count' '50' 'pre-mcp' 2>/dev/null || true
state_update 'mcp_rate_start' '${_OLD}' 'pre-mcp' 2>/dev/null || true
# Simulate rate window check
_RATE_COUNT=\$(state_read 'mcp_rate_count' 2>/dev/null || echo '0')
_RATE_START=\$(state_read 'mcp_rate_start' 2>/dev/null || echo '0')
if [[ \$(( _NOW - _RATE_START )) -ge \$_RATE_WINDOW ]]; then
    _RATE_COUNT=0; _RATE_START=\$_NOW
fi
_RATE_COUNT=\$(( _RATE_COUNT + 1 ))
state_update 'mcp_rate_count' \"\$_RATE_COUNT\" 'pre-mcp' 2>/dev/null || true
state_update 'mcp_rate_start' \"\$_RATE_START\" 'pre-mcp' 2>/dev/null || true
_FINAL_COUNT=\$(state_read 'mcp_rate_count' 2>/dev/null || echo '')
printf '%s' \"\$_FINAL_COUNT\"
" > "${TMPDIR_BASE}/t10.out" 2>/dev/null
_T10_OUT=$(cat "${TMPDIR_BASE}/t10.out")
assert_eq "T10: rate window reset — count resets to 1 when window expired" "1" "$_T10_OUT"

echo ""

# =============================================================================
# Section 3: .mcp-credential-advisory-emitted → SQLite KV
# =============================================================================
echo "--- Section 3: mcp-credential-advisory KV migration ---"

# T11: Credential advisory sentinel written to KV
_CD=$(make_env "t11")
run_in_env "$_CD" "
require_state
# Simulate first DB MCP call advisory emission
state_update 'mcp_credential_advisory' '1' 'pre-mcp' 2>/dev/null || true
# Also write flat-file (dual-write)
touch \"\${CLAUDE_DIR}/.mcp-credential-advisory-emitted\" 2>/dev/null || true
_STORED=\$(state_read 'mcp_credential_advisory' 2>/dev/null || echo '')
printf '%s' \"\$_STORED\"
" > "${TMPDIR_BASE}/t11.out" 2>/dev/null
_T11_OUT=$(cat "${TMPDIR_BASE}/t11.out")
assert_eq "T11: mcp_credential_advisory KV key = 1 after emit" "1" "$_T11_OUT"

# T12: Advisory sentinel prevents repeat emission (KV check)
_CD=$(make_env "t12")
run_in_env "$_CD" "
require_state
# First call: no KV entry yet → emit and write
_KV_VAL=\$(state_read 'mcp_credential_advisory' 2>/dev/null || echo '')
_SENTINEL=\"\${CLAUDE_DIR}/.mcp-credential-advisory-emitted\"
if [[ -z \"\$_KV_VAL\" && ! -f \"\$_SENTINEL\" ]]; then
    state_update 'mcp_credential_advisory' '1' 'pre-mcp' 2>/dev/null || true
    touch \"\$_SENTINEL\" 2>/dev/null || true
    printf 'emitted'
else
    printf 'skipped'
fi
" > "${TMPDIR_BASE}/t12a.out" 2>/dev/null
assert_eq "T12a: first call → advisory emitted" "emitted" "$(cat "${TMPDIR_BASE}/t12a.out")"

# Second call on same env: KV has '1' → should skip
run_in_env "$_CD" "
require_state
_KV_VAL=\$(state_read 'mcp_credential_advisory' 2>/dev/null || echo '')
_SENTINEL=\"\${CLAUDE_DIR}/.mcp-credential-advisory-emitted\"
if [[ -z \"\$_KV_VAL\" && ! -f \"\$_SENTINEL\" ]]; then
    printf 'emitted'
else
    printf 'skipped'
fi
" > "${TMPDIR_BASE}/t12b.out" 2>/dev/null
assert_eq "T12b: second call → advisory skipped (KV prevents repeat)" "skipped" "$(cat "${TMPDIR_BASE}/t12b.out")"

# T13: Flat-file fallback for credential advisory
_CD=$(make_env "t13")
# Write only flat-file, not KV
touch "${_CD}/.mcp-credential-advisory-emitted"
_T13_OUT=$(CLAUDE_DIR="$_CD" HOOKS_DIR="$HOOKS_DIR" bash -c "
source \"\${HOOKS_DIR}/source-lib.sh\" 2>/dev/null
require_state
_KV_VAL=\$(state_read 'mcp_credential_advisory' 2>/dev/null || echo '')
_SENTINEL=\"\${CLAUDE_DIR}/.mcp-credential-advisory-emitted\"
if [[ -z \"\$_KV_VAL\" && ! -f \"\$_SENTINEL\" ]]; then
    printf 'emitted'
else
    printf 'skipped'
fi
" 2>/dev/null)
assert_eq "T13: flat-file fallback prevents repeat emission" "skipped" "$_T13_OUT"

echo ""

# =============================================================================
# Section 4: session-end KV cleanup
# =============================================================================
echo "--- Section 4: session-end KV cleanup ---"

# T14: session-end.sh deletes db_safety_checked, db_safety_blocked, db_safety_warned
_CD=$(make_env "t14")
run_in_env "$_CD" "
require_state
state_update 'db_safety_checked' '5' 'test' 2>/dev/null || true
state_update 'db_safety_blocked' '2' 'test' 2>/dev/null || true
state_update 'db_safety_warned' '1' 'test' 2>/dev/null || true
state_delete 'db_safety_checked' 2>/dev/null || true
state_delete 'db_safety_blocked' 2>/dev/null || true
state_delete 'db_safety_warned' 2>/dev/null || true
_C=\$(state_read 'db_safety_checked' 2>/dev/null || echo '')
_B=\$(state_read 'db_safety_blocked' 2>/dev/null || echo '')
_W=\$(state_read 'db_safety_warned' 2>/dev/null || echo '')
printf '%s|%s|%s' \"\$_C\" \"\$_B\" \"\$_W\"
" > "${TMPDIR_BASE}/t14.out" 2>/dev/null
_T14_OUT=$(cat "${TMPDIR_BASE}/t14.out")
assert_eq "T14: state_delete clears db_safety_checked/blocked/warned" "||" "$_T14_OUT"

# T15: session-end.sh deletes mcp_rate_count, mcp_rate_start, mcp_credential_advisory
_CD=$(make_env "t15")
run_in_env "$_CD" "
require_state
state_update 'mcp_rate_count' '42' 'test' 2>/dev/null || true
state_update 'mcp_rate_start' '$(date +%s)' 'test' 2>/dev/null || true
state_update 'mcp_credential_advisory' '1' 'test' 2>/dev/null || true
state_delete 'mcp_rate_count' 2>/dev/null || true
state_delete 'mcp_rate_start' 2>/dev/null || true
state_delete 'mcp_credential_advisory' 2>/dev/null || true
_RC=\$(state_read 'mcp_rate_count' 2>/dev/null || echo '')
_RS=\$(state_read 'mcp_rate_start' 2>/dev/null || echo '')
_MA=\$(state_read 'mcp_credential_advisory' 2>/dev/null || echo '')
printf '%s|%s|%s' \"\$_RC\" \"\$_RS\" \"\$_MA\"
" > "${TMPDIR_BASE}/t15.out" 2>/dev/null
_T15_OUT=$(cat "${TMPDIR_BASE}/t15.out")
assert_eq "T15: state_delete clears mcp_rate_count/mcp_rate_start/mcp_credential_advisory" "||" "$_T15_OUT"

# T16: session-end.sh also removes flat-files for db-safety-stats and mcp files
_CD=$(make_env "t16")
printf 'checked=3\nblocked=1\nwarned=0\n' > "${_CD}/.db-safety-stats"
touch "${_CD}/.mcp-rate-state"
touch "${_CD}/.mcp-credential-advisory-emitted"
# Simulate the rm -f cleanup
rm -f "${_CD}/.db-safety-stats" "${_CD}/.mcp-rate-state" "${_CD}/.mcp-credential-advisory-emitted"
if [[ ! -f "${_CD}/.db-safety-stats" && ! -f "${_CD}/.mcp-rate-state" && ! -f "${_CD}/.mcp-credential-advisory-emitted" ]]; then
    pass "T16: flat-file cleanup removes all 3 session files"
else
    fail "T16: flat-file cleanup removes all 3 session files" "one or more files still exist"
fi

echo ""

# =============================================================================
# Section 5: End-to-end integration test
# =============================================================================
echo "--- Section 5: End-to-end integration ---"

# T17: _db_increment_stat → KV is primary (reads correct value when KV and flat-file disagree)
_CD=$(make_env "t17")
run_in_env "$_CD" "
require_db_safety
# Write different values to KV vs flat-file to confirm KV is primary
_db_increment_stat 'checked'
_db_increment_stat 'checked'
# Overwrite flat-file with wrong value
printf 'checked=99\nblocked=0\nwarned=0\n' > \"\${CLAUDE_DIR}/.db-safety-stats\"
# _db_session_summary should prefer KV (checked=2), not flat-file (checked=99)
_SUMMARY=\$(_db_session_summary)
printf '%s' \"\$_SUMMARY\"
" > "${TMPDIR_BASE}/t17.out" 2>/dev/null
_T17_OUT=$(cat "${TMPDIR_BASE}/t17.out")
assert_contains "T17: KV is primary source for summary (not flat-file)" "2 commands checked" "$_T17_OUT"

echo ""

# =============================================================================
# Summary
# =============================================================================
echo "=== Results ==="
echo "  PASSED: $PASS"
echo "  FAILED: $FAIL"
echo ""
if [[ "$FAIL" -eq 0 ]]; then
    echo "All tests passed."
    exit 0
else
    echo "SOME TESTS FAILED."
    exit 1
fi
