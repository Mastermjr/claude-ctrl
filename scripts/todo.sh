#!/usr/bin/env bash
# todo.sh — Backlog backing layer for Claude Code hooks.
#
# Purpose: Provides subcommands for hooks (session-init, prompt-submit, stop)
# to query, create, and claim GitHub issues labeled claude-todo. Designed as
# a standalone script that can be called with & (fire-and-forget) from hooks
# without blocking the prompt pipeline.
#
# @decision DEC-BL-TODO-001
# @title Restore todo.sh as standalone script matching hook call signatures
# @status accepted
# @rationale Hooks in session-init.sh, prompt-submit.sh, and stop.sh already
# reference $HOME/.claude/scripts/todo.sh with specific call signatures (hud,
# count --all, claim N [--auto] [--global], create "title" [--body] [--context]
# [--global]). Providing a single canonical script avoids duplicating gh CLI
# logic across hooks and makes the backlog layer testable in isolation.
# Follows the statusline.sh pattern: standalone, chmod +x, self-contained.
#
# Commands:
#   hud                         — Print compact HUD lines for session-init injection
#   count --all                 — Print pipe-delimited counts: project|global|config|total
#   claim N [--auto] [--global] — Add a claim comment to issue #N
#   create "title" [opts]       — Create issue with claude-todo label; echo URL
#
# Options for create:
#   --body "..."     Additional body text
#   --context "..."  Append context info to body (used for auto-capture)
#   --global         Use global repo (juanandresgs/cc-todos) instead of project repo
#
# Exit codes: always 0 (graceful degradation — hooks must not break on missing gh)
#
# Dependencies: gh CLI (optional — graceful when absent)
# Env: HOME (standard), CLAUDE_TODO_GLOBAL_REPO (override global repo)
#
# Usage: scripts/todo.sh <command> [args]

set -euo pipefail

# --- Constants ---
GLOBAL_REPO="${CLAUDE_TODO_GLOBAL_REPO:-juanandresgs/cc-todos}"
TODO_LABEL="claude-todo"
TODO_COUNT_FILE="$HOME/.claude/.todo-count"

# --- Optional SQLite KV integration ---
# @decision DEC-STATE-KV-006
# @title todo.sh optional state_update for todo_count KV migration
# @status accepted
# @rationale todo.sh is a standalone script (no source-lib.sh dependency by design).
#   Adding an optional source of state-lib.sh enables dual-write to SQLite KV alongside
#   the legacy flat-file (.todo-count). If state-lib.sh is unavailable (fresh install,
#   non-hook context, or sourcing error), the script degrades gracefully — flat-file
#   write still occurs. _TODO_STATE_AVAILABLE gates all KV calls.
_TODO_STATE_AVAILABLE=false
if [[ -f "$HOME/.claude/hooks/source-lib.sh" && -f "$HOME/.claude/hooks/state-lib.sh" ]]; then
    _HOOK_NAME="todo"
    # shellcheck source=/dev/null
    if source "$HOME/.claude/hooks/source-lib.sh" 2>/dev/null; then
        if source "$HOME/.claude/hooks/state-lib.sh" 2>/dev/null; then
            _TODO_STATE_AVAILABLE=true
        fi
    fi
fi

_todo_state_update() {
    # Wrapper: calls state_update if available, silently skips otherwise.
    local key="$1" value="$2"
    if [[ "$_TODO_STATE_AVAILABLE" == "true" ]]; then
        state_update "$key" "$value" "todo" 2>/dev/null || true
    fi
}

# --- Graceful gh check ---
# If gh is not installed or not authenticated, exit 0 with no output.
# Checks both presence (command -v) and auth (gh auth token). The auth check
# is fast (~5ms, reads local config — no network call) and catches the case
# where gh is installed but not logged in (e.g. CI runners with gh pre-installed).
# @decision DEC-BL-GH-CHECK-001
# @title _require_gh checks both presence and auth to prevent zero-count leaks
# @status accepted
# @rationale On GitHub Actions runners, gh is pre-installed at /usr/bin/gh but
# may not be authenticated. The original presence-only check passed, causing
# gh issue list to fail with || echo "0" fallback, producing "0|0|0|0" output
# when the caller expected silence. Adding gh auth token catches both cases:
# truly missing binary and present-but-unauthenticated.
_require_gh() {
    command -v gh >/dev/null 2>&1 || exit 0
    gh auth token >/dev/null 2>&1 || exit 0
}

# --- Detect current project repo ---
# Returns empty string if not in a GitHub-connected git repo.
_detect_project_repo() {
    gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo ""
}

# --- Get the target repo for an operation ---
# Args: [--global flag presence]
# Sets TARGET_REPO variable
_get_target_repo() {
    local use_global="${1:-false}"
    if [[ "$use_global" == "true" ]]; then
        TARGET_REPO="$GLOBAL_REPO"
    else
        TARGET_REPO=$(_detect_project_repo)
        if [[ -z "$TARGET_REPO" ]]; then
            TARGET_REPO="$GLOBAL_REPO"
        fi
    fi
}

# =============================================================================
# Subcommand: hud
# Print compact summary lines for injection into session-init CONTEXT_PARTS.
#
# Queries both project repo (if available) and global repo, then formats a
# compact summary. Also writes proj|glob counts to .todo-count for statusline
# and to the SQLite KV store (DEC-STATE-KV-006).
#
# Output format (one or more lines):
#   Backlog: 3 project + 7 global todos pending
#   (or just "Backlog: 7 global todos pending" when no project repo)
# =============================================================================
_cmd_hud() {
    _require_gh

    local project_repo
    project_repo=$(_detect_project_repo)

    local project_count=0
    local global_count=0

    # Query project repo if available and different from global
    if [[ -n "$project_repo" && "$project_repo" != "$GLOBAL_REPO" ]]; then
        project_count=$(gh issue list \
            --repo "$project_repo" \
            --label "$TODO_LABEL" \
            --state open \
            --json number \
            --jq length 2>/dev/null || echo "0")
        project_count="${project_count:-0}"
    fi

    # Query global repo
    global_count=$(gh issue list \
        --repo "$GLOBAL_REPO" \
        --label "$TODO_LABEL" \
        --state open \
        --json number \
        --jq length 2>/dev/null || echo "0")
    global_count="${global_count:-0}"

    # @decision DEC-STATE-KV-006: dual-write — KV primary + flat-file for statusline.sh.
    # statusline.sh is standalone (cannot source state-lib.sh), so flat-file persists.
    # Write proj|glob format for both stores (replaces legacy global-only integer).
    local _todo_kv_val="${project_count}|${global_count}"
    _todo_state_update "todo_count" "$_todo_kv_val"
    echo "$_todo_kv_val" > "$TODO_COUNT_FILE" 2>/dev/null || true

    # Format output
    local total=$(( project_count + global_count ))
    if [[ "$total" -eq 0 ]]; then
        # No output when nothing pending — don't clutter the context
        return 0
    fi

    if [[ -n "$project_repo" && "$project_repo" != "$GLOBAL_REPO" && "$project_count" -gt 0 && "$global_count" -gt 0 ]]; then
        echo "Backlog: ${project_count} project + ${global_count} global todos pending"
    elif [[ -n "$project_repo" && "$project_repo" != "$GLOBAL_REPO" && "$project_count" -gt 0 ]]; then
        echo "Backlog: ${project_count} project todos pending"
    elif [[ "$global_count" -gt 0 ]]; then
        echo "Backlog: ${global_count} global todos pending"
    fi
}

# =============================================================================
# Subcommand: count --all
# Print pipe-delimited counts for stop.sh: project|global|config|total
#
# stop.sh usage:
#   TODO_COUNTS=$("$TODO_SCRIPT" count --all 2>/dev/null || echo "0|0|0|0")
#   TODO_PROJECT=$(echo "$TODO_COUNTS" | cut -d'|' -f1)
#   TODO_GLOBAL=$(echo "$TODO_COUNTS" | cut -d'|' -f2)
#   TODO_CONFIG=$(echo "$TODO_COUNTS" | cut -d'|' -f3)
# =============================================================================
_cmd_count() {
    _require_gh

    local project_repo
    project_repo=$(_detect_project_repo)

    local project_count=0
    local global_count=0
    local config_count=0  # Future use — always 0 for now

    # Query project repo if available and different from global
    if [[ -n "$project_repo" && "$project_repo" != "$GLOBAL_REPO" ]]; then
        project_count=$(gh issue list \
            --repo "$project_repo" \
            --label "$TODO_LABEL" \
            --state open \
            --json number \
            --jq length 2>/dev/null || echo "0")
        project_count="${project_count:-0}"
    fi

    # Query global repo
    global_count=$(gh issue list \
        --repo "$GLOBAL_REPO" \
        --label "$TODO_LABEL" \
        --state open \
        --json number \
        --jq length 2>/dev/null || echo "0")
    global_count="${global_count:-0}"

    echo "${project_count}|${global_count}|${config_count}|$(( project_count + global_count + config_count ))"
}

# =============================================================================
# Subcommand: claim N [--auto] [--global]
# Add a claim comment to issue #N.
#
# prompt-submit.sh usage:
#   "$TODO_SCRIPT" claim "$ISSUE_NUM" --auto 2>/dev/null || true
#   "$TODO_SCRIPT" claim "$ISSUE_NUM" --global --auto 2>/dev/null || true
# =============================================================================
_cmd_claim() {
    _require_gh

    local issue_num=""
    local use_global=false
    local is_auto=false

    # Parse args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --global) use_global=true ;;
            --auto)   is_auto=true ;;
            [0-9]*)   issue_num="$1" ;;
            *)        ;;  # ignore unknown flags
        esac
        shift
    done

    if [[ -z "$issue_num" ]]; then
        return 0  # No issue number — silent exit
    fi

    _get_target_repo "$use_global"

    local comment_prefix="Claimed by Claude Code session"
    if [[ "$is_auto" == "true" ]]; then
        comment_prefix="Auto-claimed by Claude Code session"
    fi

    gh issue comment "$issue_num" \
        --repo "$TARGET_REPO" \
        --body "$comment_prefix ($(date -u '+%Y-%m-%dT%H:%M:%SZ'))" \
        2>/dev/null || true
}

# =============================================================================
# Subcommand: create "title" [--body "..."] [--context "..."] [--global]
# Create a GitHub issue with label claude-todo. Echo URL on stdout.
#
# prompt-submit.sh usage:
#   "$TODO_SCRIPT" create "$DEFERRAL_TEXT" --context "session:auto-captured" &
# =============================================================================
_cmd_create() {
    _require_gh

    local title=""
    local body=""
    local context_info=""
    local use_global=false

    # Parse args: first non-flag arg is title
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --body)
                shift
                body="${1:-}"
                ;;
            --context)
                shift
                context_info="${1:-}"
                ;;
            --global)
                use_global=true
                ;;
            *)
                if [[ -z "$title" ]]; then
                    title="$1"
                fi
                ;;
        esac
        shift
    done

    if [[ -z "$title" ]]; then
        return 0  # No title — silent exit
    fi

    _get_target_repo "$use_global"

    # Build issue body
    local full_body="## Captured\n\n${title}"
    if [[ -n "$body" ]]; then
        full_body="${full_body}\n\n${body}"
    fi
    if [[ -n "$context_info" ]]; then
        full_body="${full_body}\n\n---\n_Context: ${context_info}_"
    fi
    full_body="${full_body}\n\n## Acceptance Criteria\n\n- [ ] TBD"

    # Truncate title to 100 chars to avoid gh CLI errors
    local safe_title="${title:0:100}"

    gh issue create \
        --repo "$TARGET_REPO" \
        --title "$safe_title" \
        --label "$TODO_LABEL" \
        --body "$(printf '%b' "$full_body")" \
        2>/dev/null || true
}

# =============================================================================
# Usage / dispatch
# =============================================================================
_usage() {
    cat <<'USAGE'
Usage: todo.sh <command> [args]

Commands:
  hud                           Print compact backlog HUD for session context
  count --all                   Print pipe-delimited counts: project|global|config|total
  claim <N> [--auto] [--global] Add claim comment to issue #N
  create "title" [opts]         Create claude-todo issue, echo URL
    --body "..."                Additional body text
    --context "..."             Append context info (auto-capture metadata)
    --global                    Use global repo instead of project repo

Examples:
  todo.sh hud
  todo.sh count --all
  todo.sh claim 42 --auto
  todo.sh create "Look into X later" --context "session:auto-captured"
USAGE
}

# --- Main dispatch ---
COMMAND="${1:-}"
shift || true  # shift off the command; remaining args passed to subcommand

case "$COMMAND" in
    hud)    _cmd_hud "$@" ;;
    count)  _cmd_count "$@" ;;
    claim)  _cmd_claim "$@" ;;
    create) _cmd_create "$@" ;;
    ""|--help|-h) _usage; exit 0 ;;
    *)
        echo "todo.sh: unknown command '$COMMAND'" >&2
        _usage >&2
        exit 0  # Always exit 0 — hooks must not break
        ;;
esac
