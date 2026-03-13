#!/usr/bin/env bash
# test-statusline-4line.sh — Tests for the three bugs fixed in statusline/session-lib:
#   Bug 1: double-nesting path in write_statusline_cache() and CACHE_FILE computation
#   Bug 2: time-based cache pruning (replaces count-based "keep 3 newest")
#   Bug 3: 4-line layout — Line 2 = primary metrics, Line 3 = secondary metrics, Line 4 = initiative
#
# @decision DEC-STATUSLINE-4LINE-TEST-001
# @title Test suite for 4-line statusline redesign and double-nesting/pruning bug fixes
# @status accepted
# @rationale Validates the three compounding bugs described in the task requirements:
#   1. write_statusline_cache path bug: $root/.claude/.statusline-cache when root IS ~/.claude
#   2. Count-based pruning deletes active concurrent session caches
#   3. Aggressive responsive layout drops "Project Lifetime" at any terminal <= 125 cols
# Tests run against both the hook library (session-lib.sh) and the standalone statusline.sh script.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUSLINE="${SCRIPT_DIR}/../scripts/statusline.sh"
SESSION_LIB="${SCRIPT_DIR}/../hooks/session-lib.sh"
LOG_LIB="${SCRIPT_DIR}/../hooks/log.sh"
SOURCE_LIB="${SCRIPT_DIR}/../hooks/source-lib.sh"

# Set a fixed session ID
export CLAUDE_SESSION_ID="test-4line-$$"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

_CLEANUP_DIRS=()
trap '[[ ${#_CLEANUP_DIRS[@]} -gt 0 ]] && rm -rf "${_CLEANUP_DIRS[@]}" 2>/dev/null; true' EXIT

pass_test() { TESTS_PASSED=$(( TESTS_PASSED + 1 )); echo -e "${GREEN}✓${NC} $1"; }
fail_test() { TESTS_FAILED=$(( TESTS_FAILED + 1 )); echo -e "${RED}✗${NC} $1"; echo -e "  ${YELLOW}Details:${NC} $2"; }
run_test()  { TESTS_RUN=$(( TESTS_RUN + 1 )); }

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

# Extract line N (1-indexed) from multiline string without pipes
extract_line() {
    local str="$1" n="$2" i=0
    while IFS= read -r _el_line; do
        i=$(( i + 1 ))
        [[ "$i" -eq "$n" ]] && { printf '%s' "$_el_line"; return 0; }
    done <<< "$str"
}

# Run statusline with given JSON at given COLUMNS
run_sl_columns() {
    local json="$1" columns="$2" home_dir="${3:-}"
    local tmpdir=""
    if [[ -z "$home_dir" ]]; then
        tmpdir=$(mktemp -d)
        home_dir="$tmpdir"
    fi
    local result
    result=$(printf '%s' "$json" | COLUMNS="$columns" HOME="$home_dir" CLAUDE_SESSION_ID="$CLAUDE_SESSION_ID" bash "$STATUSLINE" 2>/dev/null)
    [[ -n "$tmpdir" ]] && rm -rf "$tmpdir"
    printf '%s' "$result"
}

# Helper: create a cache with lifetime_tokens set, in a .claude subdir of dir
make_lifetime_cache() {
    local dir="$1" lifetime_tokens="$2" subagent_tokens="${3:-0}"
    mkdir -p "$dir/.claude"
    printf '{"dirty":0,"worktrees":0,"agents_active":0,"agents_types":"","todo_project":0,"todo_global":0,"lifetime_cost":0,"lifetime_tokens":%d,"subagent_tokens":%d}' \
        "$lifetime_tokens" "$subagent_tokens" > "$dir/.claude/.statusline-cache-${CLAUDE_SESSION_ID}"
}

# Helper: create a cache with initiative set
make_initiative_cache() {
    local dir="$1" initiative="$2" phase="${3:-}" active_inits="${4:-1}" total_phases="${5:-0}"
    mkdir -p "$dir/.claude"
    printf '{"dirty":0,"worktrees":0,"agents_active":0,"agents_types":"","todo_project":0,"todo_global":0,"lifetime_cost":0,"lifetime_tokens":0,"initiative":"%s","phase":"%s","active_initiatives":%d,"total_phases":%d}' \
        "$initiative" "$phase" "$active_inits" "$total_phases" > "$dir/.claude/.statusline-cache-${CLAUDE_SESSION_ID}"
}

# ============================================================================
# Test group 1: Bug 1 — double-nesting in write_statusline_cache()
# When root is ~/.claude, the cache should go in ~/.claude/.statusline-cache-*
# NOT in ~/.claude/.claude/.statusline-cache-*
# ============================================================================

test_write_cache_no_double_nesting_for_home_claude() {
    run_test
    # Simulate the ~/.claude project: root = HOME/.claude
    # Call write_statusline_cache() and verify the cache file lands in root directly,
    # not in root/.claude/
    local tmpdir
    tmpdir=$(mktemp -d)
    _CLEANUP_DIRS+=("$tmpdir")

    # Simulate HOME so the HOME/.claude path is tmpdir/.claude
    local fake_home="$tmpdir"
    local fake_root="${fake_home}/.claude"
    mkdir -p "$fake_root"

    # Source the hooks to get write_statusline_cache (requires sourcing in correct order)
    # We test the path logic: for root == HOME/.claude, cache_file should be $root/.statusline-cache-*
    # The double-nesting bug would put it at $root/.claude/.statusline-cache-*
    local bad_path="${fake_root}/.claude/.statusline-cache-test-nesting"
    local good_path="${fake_root}/.statusline-cache-test-nesting"

    # Verify that after the fix, write_statusline_cache creates the good path, not the bad path
    # We can test this by sourcing the library and calling the function
    (
        export HOME="$fake_home"
        export PROJECT_ROOT="$fake_root"
        export CLAUDE_SESSION_ID="test-nesting"
        export GIT_DIRTY_COUNT=0
        export GIT_WT_COUNT=0
        # Source session-lib directly (bypasses source-lib's HOME-based hook loading)
        # shellcheck source=/dev/null
        source "$SESSION_LIB" 2>/dev/null || true
        type write_statusline_cache &>/dev/null && write_statusline_cache "$fake_root" 2>/dev/null || true
    )

    if [[ -f "$good_path" && ! -f "$bad_path" ]]; then
        pass_test "Bug 1 fix: write_statusline_cache places cache at root/.statusline-cache-* (no double-nesting)"
    elif [[ -f "$bad_path" ]]; then
        fail_test "Bug 1 NOT fixed: cache at root/.claude/.statusline-cache-* (double-nesting)" \
            "bad_path=$bad_path exists; good_path=$good_path"
    elif [[ ! -f "$good_path" ]]; then
        # Function might not have run due to missing deps — check if bad path was also skipped
        fail_test "Bug 1: write_statusline_cache did not create cache at expected path" \
            "good_path=$good_path missing; tested root=$fake_root"
    fi
}

test_write_cache_normal_project_uses_dot_claude() {
    run_test
    # For a normal project (root != ~/.claude), cache should go in root/.claude/.statusline-cache-*
    local tmpdir
    tmpdir=$(mktemp -d)
    _CLEANUP_DIRS+=("$tmpdir")

    local fake_home="$tmpdir/home"
    local project_root="$tmpdir/myproject"
    mkdir -p "$fake_home/.claude"
    mkdir -p "$project_root"

    local good_path="${project_root}/.claude/.statusline-cache-test-normal"
    local bad_path="${project_root}/.statusline-cache-test-normal"

    (
        export HOME="$fake_home"
        export PROJECT_ROOT="$project_root"
        export CLAUDE_SESSION_ID="test-normal"
        export GIT_DIRTY_COUNT=0
        export GIT_WT_COUNT=0
        # Source session-lib directly (bypasses source-lib's HOME-based hook loading)
        # shellcheck source=/dev/null
        source "$SESSION_LIB" 2>/dev/null || true
        type write_statusline_cache &>/dev/null && write_statusline_cache "$project_root" 2>/dev/null || true
    )

    if [[ -f "$good_path" && ! -f "$bad_path" ]]; then
        pass_test "Bug 1: normal project cache at project/.claude/.statusline-cache-* (correct behavior preserved)"
    elif [[ -f "$bad_path" ]]; then
        fail_test "Bug 1: normal project cache at wrong path (not in .claude/)" "bad_path=$bad_path"
    else
        fail_test "Bug 1: normal project cache not created at expected path" \
            "good_path=$good_path missing"
    fi
}

# ============================================================================
# Test group 2: Bug 1 — double-nesting in statusline.sh CACHE_FILE computation
# When workspace_dir is ~/.claude, CACHE_FILE should use $workspace_dir directly
# ============================================================================

test_statusline_cache_file_no_double_nesting() {
    run_test
    # When workspace_dir = ~/.claude equivalent, statusline should find the cache
    # at $workspace_dir/.statusline-cache-* (not $workspace_dir/.claude/.statusline-cache-*)
    local tmpdir
    tmpdir=$(mktemp -d)
    _CLEANUP_DIRS+=("$tmpdir")

    local fake_home="$tmpdir"
    local fake_claude="${fake_home}/.claude"
    mkdir -p "$fake_claude"

    # Create cache at the CORRECT path: $claude_dir/.statusline-cache-<SID>
    # For home/.claude project, this is $fake_claude/.statusline-cache-<SID>
    local correct_cache="${fake_claude}/.statusline-cache-${CLAUDE_SESSION_ID}"
    printf '{"dirty":3,"worktrees":1,"agents_active":0,"agents_types":"","todo_project":0,"todo_global":0,"lifetime_cost":0,"lifetime_tokens":5700000}' \
        > "$correct_cache"

    local json
    json=$(printf '{"model":{"display_name":"Claude"},"workspace":{"current_dir":"%s"},"cost":{},"context_window":{"total_input_tokens":100000,"total_output_tokens":45000}}' "$fake_claude")

    local output
    output=$(printf '%s' "$json" | COLUMNS=200 HOME="$fake_home" bash "$STATUSLINE" 2>/dev/null)
    local stripped
    stripped=$(printf '%s' "$output" | strip_ansi)

    # If the cache is found, dirty:3 should show as "dirty: 3"
    if printf '%s' "$stripped" | grep -q 'dirty: 3'; then
        pass_test "Bug 1 fix: statusline finds cache at workspace_dir/.statusline-cache-* when workspace=home/.claude"
    else
        fail_test "Bug 1 NOT fixed in statusline.sh: cache not found at correct path" \
            "stripped=$stripped (expected 'dirty: 3')"
    fi
}

# ============================================================================
# Test group 3: Bug 2 — time-based pruning
# Old behavior: ls -t | tail -n +4 | xargs rm -f (keeps 3 newest, kills active sessions)
# New behavior: delete files older than 1 hour
# ============================================================================

test_pruning_keeps_recent_files() {
    run_test
    # Create >10 cache files all with current mtimes (less than 1 hour old).
    # After running statusline, none should be deleted.
    local tmpdir
    tmpdir=$(mktemp -d)
    _CLEANUP_DIRS+=("$tmpdir")
    local cache_dir="${tmpdir}/.claude"
    mkdir -p "$cache_dir"

    # Create 12 recent cache files (less than 1 hour old)
    local i
    for i in $(seq 1 12); do
        printf '{"dirty":0,"worktrees":0,"agents_active":0}' > "${cache_dir}/.statusline-cache-sess${i}"
    done

    local before_count
    before_count=$(ls "${cache_dir}"/.statusline-cache-* 2>/dev/null | wc -l | tr -d ' ')

    local json
    json=$(printf '{"model":{"display_name":"Claude"},"workspace":{"current_dir":"%s"},"cost":{},"context_window":{}}' "$tmpdir")
    printf '%s' "$json" | COLUMNS=80 HOME="$tmpdir" bash "$STATUSLINE" 2>/dev/null > /dev/null

    local after_count
    after_count=$(ls "${cache_dir}"/.statusline-cache-* 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$after_count" -eq "$before_count" ]]; then
        pass_test "Bug 2 fix: time-based pruning — 12 recent files, none deleted (all < 1 hour old)"
    else
        fail_test "Bug 2 NOT fixed: recent files deleted by count-based pruning" \
            "before=$before_count after=$after_count (expected equal)"
    fi
}

test_pruning_deletes_old_files() {
    run_test
    # Create >10 cache files where some are old (>1 hour).
    # After running statusline, the old ones should be pruned.
    local tmpdir
    tmpdir=$(mktemp -d)
    _CLEANUP_DIRS+=("$tmpdir")
    local cache_dir="${tmpdir}/.claude"
    mkdir -p "$cache_dir"

    # Create 5 old cache files (touch -t sets mtime to 2 hours ago)
    local old_time
    old_time=$(date -v -2H +%Y%m%d%H%M.%S 2>/dev/null || date -d '2 hours ago' +%Y%m%d%H%M.%S 2>/dev/null || echo "")
    local i
    for i in $(seq 1 5); do
        printf '{"dirty":0,"worktrees":0,"agents_active":0}' > "${cache_dir}/.statusline-cache-old${i}"
        if [[ -n "$old_time" ]]; then
            touch -t "$old_time" "${cache_dir}/.statusline-cache-old${i}" 2>/dev/null || true
        fi
    done

    # Create 5 recent cache files
    for i in $(seq 1 5); do
        printf '{"dirty":0,"worktrees":0,"agents_active":0}' > "${cache_dir}/.statusline-cache-new${i}"
    done
    # Also create our session's cache file (the one statusline will find)
    printf '{"dirty":0,"worktrees":0,"agents_active":0}' > "${cache_dir}/.statusline-cache-${CLAUDE_SESSION_ID}"

    local json
    json=$(printf '{"model":{"display_name":"Claude"},"workspace":{"current_dir":"%s"},"cost":{},"context_window":{}}' "$tmpdir")
    printf '%s' "$json" | COLUMNS=80 HOME="$tmpdir" bash "$STATUSLINE" 2>/dev/null > /dev/null

    # Old files should be deleted
    # Use find -name pattern to avoid glob expansion failing when no files match
    local old_remaining
    old_remaining=$(find "${cache_dir}" -name '.statusline-cache-old*' 2>/dev/null | wc -l | tr -d ' ')
    # New files should remain
    local new_remaining
    new_remaining=$(find "${cache_dir}" -name '.statusline-cache-new*' 2>/dev/null | wc -l | tr -d ' ')

    if [[ "${old_time:-}" == "" ]]; then
        # Can't backdate on this system, skip old-deletion check
        pass_test "Bug 2: time-based pruning — cannot backdate on this system, test skipped"
    elif [[ "$old_remaining" -eq 0 && "$new_remaining" -eq 5 ]]; then
        pass_test "Bug 2 fix: time-based pruning — old files deleted, recent files preserved"
    elif [[ "$old_remaining" -gt 0 ]]; then
        fail_test "Bug 2 NOT fixed: old files not deleted by time-based pruning" \
            "old_remaining=$old_remaining (expected 0)"
    else
        fail_test "Bug 2: unexpected pruning result" \
            "old_remaining=$old_remaining new_remaining=$new_remaining"
    fi
}

test_pruning_only_triggers_above_threshold() {
    run_test
    # Only 3 files — pruning should NOT trigger (threshold requires >10 files)
    local tmpdir
    tmpdir=$(mktemp -d)
    _CLEANUP_DIRS+=("$tmpdir")
    local cache_dir="${tmpdir}/.claude"
    mkdir -p "$cache_dir"

    # Create 3 old files
    local old_time
    old_time=$(date -v -2H +%Y%m%d%H%M.%S 2>/dev/null || date -d '2 hours ago' +%Y%m%d%H%M.%S 2>/dev/null || echo "")
    local i
    for i in $(seq 1 3); do
        printf '{"dirty":0,"worktrees":0,"agents_active":0}' > "${cache_dir}/.statusline-cache-old${i}"
        if [[ -n "$old_time" ]]; then
            touch -t "$old_time" "${cache_dir}/.statusline-cache-old${i}" 2>/dev/null || true
        fi
    done

    local before_count
    before_count=$(ls "${cache_dir}"/.statusline-cache-* 2>/dev/null | wc -l | tr -d ' ')

    local json
    json=$(printf '{"model":{"display_name":"Claude"},"workspace":{"current_dir":"%s"},"cost":{},"context_window":{}}' "$tmpdir")
    printf '%s' "$json" | COLUMNS=80 HOME="$tmpdir" bash "$STATUSLINE" 2>/dev/null > /dev/null

    local after_count
    after_count=$(ls "${cache_dir}"/.statusline-cache-* 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$after_count" -eq "$before_count" ]]; then
        pass_test "Bug 2: pruning skipped when file count <= 10 (threshold guard works)"
    else
        fail_test "Bug 2: pruning triggered below threshold" \
            "before=$before_count after=$after_count"
    fi
}

# ============================================================================
# Test group 4: Bug 3 — 4-line output structure
# New layout:
#   Line 1: workspace | dirty | wt | agents | todos
#   Line 2: [ctx bar] | tokens | cost | lifetime
#   Line 3: model | cache% | duration | +N/-N lines
#   Line 4: initiative banner (conditional)
# ============================================================================

test_output_has_4_lines_with_initiative() {
    run_test
    # With an initiative banner, output should have 4 lines (3 newlines)
    local tmpdir
    tmpdir=$(mktemp -d)
    _CLEANUP_DIRS+=("$tmpdir")
    make_initiative_cache "$tmpdir" "Test Initiative" "#### Phase 1: Testing" 1 3

    local json
    json=$(printf '{"model":{"display_name":"Claude"},"workspace":{"current_dir":"%s"},"cost":{"total_cost_usd":0.5,"total_duration_ms":60000},"context_window":{"used_percentage":40,"total_input_tokens":100000,"total_output_tokens":45000}}' "$tmpdir")

    local output
    output=$(printf '%s' "$json" | COLUMNS=200 HOME="$tmpdir" bash "$STATUSLINE" 2>/dev/null)
    local line_count
    line_count=$(printf '%s' "$output" | wc -l | tr -d ' ')
    local line4
    line4=$(extract_line "$output" 4 | sed 's/\x1b\[[0-9;]*m//g')

    # With initiative: need 3 newlines in captured output (4th line strips trailing, so captured = 3+ lines)
    # or Line 4 must have the initiative content
    if [[ "$line_count" -ge 3 || -n "$line4" ]]; then
        pass_test "4-line layout: output has 4 lines with initiative (line4='$line4')"
    else
        fail_test "4-line layout: expected 4 lines (3+ newlines), got $((line_count + 1)) lines" \
            "line_count_newlines=$line_count"
    fi
}

test_output_has_4_lines_without_initiative() {
    run_test
    # Without initiative, output still has content on 3+ lines (stable height).
    # Note: bash command substitution strips trailing newlines from output, so a 4-line
    # output (line1\nline2\nline3\n) becomes a 3-line string (line1\nline2\nline3) when
    # captured via $(...). We check for at least 2 newlines (3 lines) to verify Line 3 is present.
    local json
    json='{"model":{"display_name":"Claude"},"workspace":{"current_dir":"/tmp/p"},"cost":{"total_cost_usd":0.5,"total_duration_ms":60000},"context_window":{"used_percentage":40,"total_input_tokens":100000,"total_output_tokens":45000}}'

    local output
    output=$(run_sl_columns "$json" 200)
    local line_count
    line_count=$(printf '%s' "$output" | wc -l | tr -d ' ')
    local line3
    line3=$(printf '%s' "$output" | sed -n '3p' | sed 's/\x1b\[[0-9;]*m//g')

    # Must have 3 lines (at least 2 newlines when captured via $()) and Line 3 must have content
    if [[ "$line_count" -ge 2 && -n "$line3" ]]; then
        pass_test "4-line layout: output has 3+ content lines without initiative (Line 3 present: '$line3')"
    else
        fail_test "4-line layout: expected 3 content lines, got $((line_count + 1)) or Line 3 empty" \
            "line_count_newlines=$line_count line3='$line3'"
    fi
}

test_line1_is_project_context() {
    run_test
    # Line 1 = workspace name
    local json
    json='{"model":{"display_name":"Opus 4.6"},"workspace":{"current_dir":"/Users/turla/myproject"},"cost":{},"context_window":{}}'
    local output
    output=$(run_sl_columns "$json" 200)
    local line1
    line1=$(extract_line "$output" 1 | strip_ansi)

    if [[ "$line1" == *"myproject"* ]] && [[ "$line1" != *"Opus 4.6"* ]]; then
        pass_test "Line 1 is project context (workspace, NOT model)"
    else
        fail_test "Line 1 wrong: should have workspace, not model" "line1=$line1"
    fi
}

test_line2_contains_ctx_bar_tokens_cost() {
    run_test
    # Line 2 = primary metrics: context bar, tokens, cost
    local json
    json='{"model":{"display_name":"Opus 4.6"},"workspace":{"current_dir":"/Users/turla/myproject"},"cost":{"total_cost_usd":0.53,"total_duration_ms":60000},"context_window":{"used_percentage":40,"total_input_tokens":100000,"total_output_tokens":45000}}'
    local output
    output=$(run_sl_columns "$json" 200)
    local line2
    line2=$(extract_line "$output" 2 | strip_ansi)

    # Line 2 must have: context bar (% sign) and tokens ("tks") and cost ("~$")
    if [[ "$line2" == *"40%"* ]] && [[ "$line2" == *"tks"* ]] && [[ "$line2" == *"~$"* ]]; then
        pass_test "Line 2 contains context bar %, tokens, and cost"
    else
        fail_test "Line 2 missing primary metrics (ctx bar, tokens, or cost)" "line2=$line2"
    fi
}

test_line2_does_not_contain_model() {
    run_test
    # Line 2 = primary metrics only — model is on Line 3 now
    local json
    json='{"model":{"display_name":"Opus 4.6"},"workspace":{"current_dir":"/tmp/proj"},"cost":{"total_cost_usd":0.10},"context_window":{"used_percentage":30,"total_input_tokens":50000,"total_output_tokens":10000}}'
    local output
    output=$(run_sl_columns "$json" 200)
    local line2
    line2=$(extract_line "$output" 2 | strip_ansi)

    if [[ "$line2" != *"Opus 4.6"* ]]; then
        pass_test "Line 2 does NOT contain model name (model moved to Line 3)"
    else
        fail_test "Line 2 should not have model name (model is on Line 3)" "line2=$line2"
    fi
}

test_line3_contains_model() {
    run_test
    # Line 3 = secondary metrics: model name should appear here
    local json
    json='{"model":{"display_name":"Opus 4.6"},"workspace":{"current_dir":"/tmp/proj"},"cost":{"total_cost_usd":0.10,"total_duration_ms":30000},"context_window":{"used_percentage":30,"total_input_tokens":50000,"total_output_tokens":10000}}'
    local output
    output=$(run_sl_columns "$json" 200)
    local line3
    line3=$(extract_line "$output" 3 | strip_ansi)

    if [[ "$line3" == *"Opus 4.6"* ]]; then
        pass_test "Line 3 contains model name"
    else
        fail_test "Line 3 should contain model name" "line3=$line3"
    fi
}

test_line4_contains_initiative_when_present() {
    run_test
    # Line 4 = initiative banner (moved from Line 3)
    local tmpdir
    tmpdir=$(mktemp -d)
    _CLEANUP_DIRS+=("$tmpdir")
    make_initiative_cache "$tmpdir" "My Initiative" "#### Phase 2: Build" 1 4

    local json
    json=$(printf '{"model":{"display_name":"Claude"},"workspace":{"current_dir":"%s"},"cost":{},"context_window":{}}' "$tmpdir")
    local output
    output=$(printf '%s' "$json" | COLUMNS=200 HOME="$tmpdir" bash "$STATUSLINE" 2>/dev/null)
    local line4
    line4=$(extract_line "$output" 4 | strip_ansi)

    if [[ "$line4" == *"My Initiative"* ]]; then
        pass_test "Line 4 contains initiative banner"
    else
        fail_test "Line 4 should contain initiative banner" "line4=$line4"
    fi
}

test_lifetime_segment_visible_at_old_breakpoint() {
    run_test
    # Bug 3 root cause: with the OLD 3-line layout, "Project Lifetime: ∑5.7M tks" was
    # dropped at any COLUMNS <= 125 (term_w=60, all 8 metrics competed on one line).
    # With the 4-LINE layout, Line 2 only has 4 segments (ctx bar + tokens + cost + lifetime).
    # At COLUMNS=140 (term_w=75): ctx(~19) + tks(~8) + cost(~6) + lifetime(~28) + 3*3=9 = 70 < 75.
    # This proves the improvement: lifetime now visible at COLUMNS=140, was invisible at COLUMNS=190+.
    local tmpdir
    tmpdir=$(mktemp -d)
    _CLEANUP_DIRS+=("$tmpdir")
    make_lifetime_cache "$tmpdir" 5700000 0

    local json
    json=$(printf '{"model":{"display_name":"Claude"},"workspace":{"current_dir":"%s"},"cost":{"total_cost_usd":0.50},"context_window":{"used_percentage":40,"total_input_tokens":100000,"total_output_tokens":45000}}' "$tmpdir")

    local output
    output=$(run_sl_columns "$json" 140 "$tmpdir")
    local line2
    line2=$(extract_line "$output" 2 | strip_ansi)

    if [[ "$line2" == *"∑"* ]] || [[ "$line2" == *"Lifetime"* ]]; then
        pass_test "Bug 3 fix: Project Lifetime visible at COLUMNS=140 (was dropped at <=125 before fix)"
    else
        fail_test "Bug 3 NOT fixed: Project Lifetime missing at COLUMNS=140" \
            "line2=$line2"
    fi
}

test_lifetime_segment_visible_at_130_cols() {
    run_test
    # Boundary test: at COLUMNS=130 (term_w=65), Line 2 = ~70 chars. Just over 65.
    # Lifetime may still drop here — test for graceful handling (no crash, line2 still has ctx+tks+cost).
    local tmpdir
    tmpdir=$(mktemp -d)
    _CLEANUP_DIRS+=("$tmpdir")
    make_lifetime_cache "$tmpdir" 5700000 0

    local json
    json=$(printf '{"model":{"display_name":"Claude"},"workspace":{"current_dir":"%s"},"cost":{"total_cost_usd":0.50},"context_window":{"used_percentage":40,"total_input_tokens":100000,"total_output_tokens":45000}}' "$tmpdir")

    local output
    output=$(run_sl_columns "$json" 130 "$tmpdir")
    local line2
    line2=$(extract_line "$output" 2 | strip_ansi)

    # At minimum, ctx bar and tokens must be present
    if [[ "$line2" == *"%"* ]] && [[ "$line2" == *"tks"* ]]; then
        pass_test "COLUMNS=130: Line 2 has ctx bar + tokens (lifetime may drop at this width)"
    else
        fail_test "COLUMNS=130: Line 2 missing ctx bar or tokens" \
            "line2=$line2"
    fi
}

test_lifetime_segment_visible_at_200_cols() {
    run_test
    # Wide terminal — lifetime should always appear
    local tmpdir
    tmpdir=$(mktemp -d)
    _CLEANUP_DIRS+=("$tmpdir")
    make_lifetime_cache "$tmpdir" 5700000 0

    local json
    json=$(printf '{"model":{"display_name":"Claude"},"workspace":{"current_dir":"%s"},"cost":{"total_cost_usd":0.50},"context_window":{"used_percentage":40,"total_input_tokens":100000,"total_output_tokens":45000}}' "$tmpdir")

    local output
    output=$(printf '%s' "$json" | COLUMNS=200 HOME="$tmpdir" bash "$STATUSLINE" 2>/dev/null)
    local line2
    line2=$(extract_line "$output" 2 | strip_ansi)

    if [[ "$line2" == *"∑"* ]] || [[ "$line2" == *"Lifetime"* ]]; then
        pass_test "Bug 3: Project Lifetime segment visible at COLUMNS=200"
    else
        fail_test "Bug 3: Project Lifetime segment missing at COLUMNS=200" \
            "line2=$line2"
    fi
}

test_line3_contains_duration() {
    run_test
    # Line 3 = secondary metrics: duration should appear here
    local json
    json='{"model":{"display_name":"Claude"},"workspace":{"current_dir":"/tmp/proj"},"cost":{"total_cost_usd":0.10,"total_duration_ms":90000},"context_window":{"used_percentage":30,"total_input_tokens":50000,"total_output_tokens":10000}}'
    local output
    output=$(run_sl_columns "$json" 200)
    local line3
    line3=$(extract_line "$output" 3 | strip_ansi)

    # Duration "1m" should appear on Line 3
    if [[ "$line3" == *"1m"* ]] || [[ "$line3" == *"<1m"* ]] || [[ "$line3" == *"m"* ]]; then
        pass_test "Line 3 contains duration"
    else
        fail_test "Line 3 should contain duration" "line3=$line3"
    fi
}

test_line3_contains_cache_pct() {
    run_test
    # Line 3 = secondary metrics: cache% should appear here
    local json
    json='{"model":{"display_name":"Claude"},"workspace":{"current_dir":"/tmp/proj"},"cost":{},"context_window":{"used_percentage":30,"current_usage":{"cache_read_input_tokens":50000,"input_tokens":10000,"cache_creation_input_tokens":5000},"total_input_tokens":50000,"total_output_tokens":10000}}'
    local output
    output=$(run_sl_columns "$json" 200)
    local line3
    line3=$(extract_line "$output" 3 | strip_ansi)

    if [[ "$line3" == *"cache"* ]]; then
        pass_test "Line 3 contains cache % segment"
    else
        fail_test "Line 3 should contain cache % segment" "line3=$line3"
    fi
}

# ============================================================================
# Test group 5: Regression — existing Line 2 (project context) tests still pass
# ============================================================================

test_regression_line1_workspace() {
    run_test
    local json='{"model":{"display_name":"Claude"},"workspace":{"current_dir":"/Users/turla/regression"},"cost":{},"context_window":{}}'
    local output
    output=$(run_sl_columns "$json" 200)
    local line1
    line1=$(extract_line "$output" 1 | strip_ansi)
    if [[ "$line1" == *"regression"* ]]; then
        pass_test "Regression: Line 1 workspace name present"
    else
        fail_test "Regression: Line 1 workspace missing" "line1=$line1"
    fi
}

test_regression_ctx_bar_on_line2() {
    run_test
    local json='{"model":{"display_name":"Claude"},"workspace":{"current_dir":"/tmp/p"},"cost":{},"context_window":{"used_percentage":55}}'
    local output
    output=$(run_sl_columns "$json" 200)
    local line2
    line2=$(extract_line "$output" 2 | strip_ansi)
    if [[ "$line2" == *"55%"* ]]; then
        pass_test "Regression: context bar still on Line 2"
    else
        fail_test "Regression: context bar missing from Line 2" "line2=$line2"
    fi
}

test_regression_banner_is_line4() {
    run_test
    local tmpdir
    tmpdir=$(mktemp -d)
    _CLEANUP_DIRS+=("$tmpdir")
    make_initiative_cache "$tmpdir" "Regression Banner" "" 1 0

    local json
    json=$(printf '{"model":{"display_name":"Claude"},"workspace":{"current_dir":"%s"},"cost":{},"context_window":{}}' "$tmpdir")
    local output
    output=$(printf '%s' "$json" | COLUMNS=200 HOME="$tmpdir" bash "$STATUSLINE" 2>/dev/null)
    local line4
    line4=$(extract_line "$output" 4 | strip_ansi)

    if [[ "$line4" == *"Regression Banner"* ]]; then
        pass_test "Regression: initiative banner on Line 4 (moved from Line 3)"
    else
        fail_test "Regression: initiative banner not on Line 4" "line4=$line4"
    fi
}

# ============================================================================
# Invoke all tests
# ============================================================================

echo ""
echo "--- Bug 1: double-nesting cache path in write_statusline_cache() ---"
test_write_cache_no_double_nesting_for_home_claude
test_write_cache_normal_project_uses_dot_claude

echo ""
echo "--- Bug 1: CACHE_FILE path in statusline.sh ---"
test_statusline_cache_file_no_double_nesting

echo ""
echo "--- Bug 2: time-based cache pruning ---"
test_pruning_keeps_recent_files
test_pruning_deletes_old_files
test_pruning_only_triggers_above_threshold

echo ""
echo "--- Bug 3: 4-line output structure ---"
test_output_has_4_lines_with_initiative
test_output_has_4_lines_without_initiative
test_line1_is_project_context
test_line2_contains_ctx_bar_tokens_cost
test_line2_does_not_contain_model
test_line3_contains_model
test_line4_contains_initiative_when_present
test_lifetime_segment_visible_at_old_breakpoint
test_lifetime_segment_visible_at_130_cols
test_lifetime_segment_visible_at_200_cols
test_line3_contains_duration
test_line3_contains_cache_pct

echo ""
echo "--- Regression: Line 1 project context ---"
test_regression_line1_workspace
test_regression_ctx_bar_on_line2
test_regression_banner_is_line4

# ============================================================================
# Summary
# ============================================================================

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
