#!/usr/bin/env bash
# scripts/hook-timing-report.sh — Parse .hook-timing.log and emit formatted statistics.
#
# Usage: hook-timing-report.sh [log_file] [--last N]
#
# Reads hook timing entries and computes per-hook-name and per-event-type statistics
# (count, p50, p95, max, avg). Sorted by p95 descending (slowest hooks first).
#
# Log formats supported (tab-separated):
#   4-field: timestamp hook_name elapsed_ms exit_code          (old format)
#   5-field: timestamp hook_name event_type elapsed_ms exit_code (new format)
#
# Entries with empty hook_name are skipped (test harness noise).
#
# @decision DEC-TIMING-001
# @title awk-only timing statistics (no Python or jq dependency)
# @status accepted
# @rationale hook-timing-report.sh runs in any environment where hooks run —
#   that means bash + awk are the only safe dependencies. Python and jq are
#   optional extras not guaranteed in CI or minimal environments.

set -euo pipefail

DEFAULT_LOG="${HOME}/.claude/.hook-timing.log"
LOG_FILE=""
LAST_N=0

# --- Argument parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --last)
            shift
            if [[ -z "${1:-}" || ! "${1}" =~ ^[0-9]+$ ]]; then
                echo "ERROR: --last requires a positive integer argument" >&2
                exit 1
            fi
            LAST_N="$1"
            shift
            ;;
        --help|-h)
            echo "Usage: $(basename "$0") [log_file] [--last N]"
            echo ""
            echo "  log_file   Path to .hook-timing.log (default: ~/.claude/.hook-timing.log)"
            echo "  --last N   Only analyze the last N entries (default: all)"
            exit 0
            ;;
        -*)
            echo "ERROR: unknown option: $1" >&2
            exit 1
            ;;
        *)
            if [[ -z "$LOG_FILE" ]]; then
                LOG_FILE="$1"
            else
                echo "ERROR: unexpected argument: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

LOG_FILE="${LOG_FILE:-$DEFAULT_LOG}"

if [[ ! -f "$LOG_FILE" ]]; then
    echo "ERROR: log file not found: $LOG_FILE" >&2
    exit 1
fi

# --- Determine entry count for header ---
total_entries=$(wc -l < "$LOG_FILE" | tr -d ' ')
if [[ "$LAST_N" -gt 0 && "$LAST_N" -lt "$total_entries" ]]; then
    analyzed=$LAST_N
    header_label="last $LAST_N entries"
else
    analyzed=$total_entries
    header_label="$total_entries entries"
fi

echo "Hook Timing Report ($header_label)"
echo "====================================="
echo ""

# --- Extract and normalize entries ---
# Pipe through tail if --last N is set. Then normalize to a consistent format:
#   hook_name TAB event_type TAB elapsed_ms
# for further awk processing. Empty hook_name rows are dropped.
#
# Field layout:
#   4-field: $1=ts $2=hook $3=elapsed $4=exit  → event_type = ""
#   5-field: $1=ts $2=hook $3=event  $4=elapsed $5=exit
#
# awk handles both in a single pass by checking NF.

_normalize() {
    if [[ "$LAST_N" -gt 0 ]]; then
        tail -n "$LAST_N" "$LOG_FILE"
    else
        cat "$LOG_FILE"
    fi | awk -F'\t' '
        # Skip blank lines
        NF == 0 { next }
        # 4-field (old): timestamp hook elapsed exit
        NF == 4 && length($2) > 0 {
            printf "%s\t\t%s\n", $2, $3
            next
        }
        # 5-field (new): timestamp hook event elapsed exit
        NF == 5 && length($2) > 0 {
            printf "%s\t%s\t%s\n", $2, $3, $4
            next
        }
        # Any other NF with hook_name populated — best effort
        NF >= 4 && length($2) > 0 {
            elapsed = (NF == 4) ? $3 : $4
            event   = (NF >= 5) ? $3 : ""
            printf "%s\t%s\t%s\n", $2, event, elapsed
        }
    '
}

# --- Compute statistics using awk ---
# Input: hook_name TAB event_type TAB elapsed_ms
# Uses two pass-equivalent approach: collect all values per key, then compute stats.
#
# p50/p95 are computed by sorting the value array for each key.
# awk's built-in sort (PROCINFO["sorted_in"]) is gawk-specific.
# For portability we use a simple insertion-sort over the value arrays.
#
# Output is two blocks: "By Hook Name" and "By Event Type".

_compute_stats() {
    awk -F'\t' '
    function isort(arr, n,    i, j, tmp) {
        for (i = 2; i <= n; i++) {
            tmp = arr[i]
            j = i - 1
            while (j >= 1 && arr[j] > tmp) {
                arr[j+1] = arr[j]
                j--
            }
            arr[j+1] = tmp
        }
    }

    function percentile(arr, n, pct,    idx) {
        idx = int(n * pct / 100 + 0.999)
        if (idx < 1) idx = 1
        if (idx > n) idx = n
        return arr[idx]
    }

    function format_stats(label, n, p50, p95, mx, av,    out) {
        out = sprintf("  %-16s n=%-5d p50=%-7s p95=%-7s max=%-7s avg=%s",
            label, n,
            p50 "ms", p95 "ms", mx "ms", av "ms")
        return out
    }

    {
        hook  = $1
        event = $2
        ms    = $3 + 0

        # Per hook_name accumulation
        hook_count[hook]++
        hook_sum[hook]  += ms
        if (!(hook in hook_max) || ms > hook_max[hook]) hook_max[hook] = ms
        hook_vals[hook, hook_count[hook]] = ms

        # Per event_type accumulation (only if event is non-empty)
        if (length(event) > 0) {
            ev_count[event]++
            ev_sum[event]  += ms
            if (!(event in ev_max) || ms > ev_max[event]) ev_max[event] = ms
            ev_vals[event, ev_count[event]] = ms
        }
    }

    END {
        # ---- By Hook Name ----
        print "By Hook Name:"

        # Collect hook names, compute p50/p95/avg, store for sorting
        n_hooks = 0
        for (h in hook_count) {
            n = hook_count[h]
            # Rebuild sort array
            delete sarr
            for (k = 1; k <= n; k++) sarr[k] = hook_vals[h, k]
            isort(sarr, n)
            p50 = percentile(sarr, n, 50)
            p95 = percentile(sarr, n, 95)
            avg = int(hook_sum[h] / n + 0.5)
            # Store line with p95 as sort key (padded for numeric sort)
            n_hooks++
            hook_lines[n_hooks] = sprintf("%010d\t%s", p95, \
                format_stats(h, n, p50, p95, hook_max[h], avg))
        }

        # Sort hook_lines descending by p95 (simple insertion sort on strings)
        for (i = 2; i <= n_hooks; i++) {
            tmp = hook_lines[i]
            j = i - 1
            while (j >= 1 && hook_lines[j] < tmp) {
                hook_lines[j+1] = hook_lines[j]
                j--
            }
            hook_lines[j+1] = tmp
        }
        for (i = 1; i <= n_hooks; i++) {
            # Strip leading sort key
            sub(/^[0-9]+\t/, "", hook_lines[i])
            print hook_lines[i]
        }
        print ""

        # ---- By Event Type ----
        print "By Event Type:"
        n_evs = 0
        for (e in ev_count) {
            n = ev_count[e]
            delete sarr
            for (k = 1; k <= n; k++) sarr[k] = ev_vals[e, k]
            isort(sarr, n)
            p50 = percentile(sarr, n, 50)
            p95 = percentile(sarr, n, 95)
            avg = int(ev_sum[e] / n + 0.5)
            n_evs++
            ev_lines[n_evs] = sprintf("%010d\t%s", p95, \
                format_stats(e, n, p50, p95, ev_max[e], avg))
        }

        if (n_evs == 0) {
            print "  (no event-type data — log contains only old 4-field format entries)"
        } else {
            for (i = 2; i <= n_evs; i++) {
                tmp = ev_lines[i]
                j = i - 1
                while (j >= 1 && ev_lines[j] < tmp) {
                    ev_lines[j+1] = ev_lines[j]
                    j--
                }
                ev_lines[j+1] = tmp
            }
            for (i = 1; i <= n_evs; i++) {
                sub(/^[0-9]+\t/, "", ev_lines[i])
                print ev_lines[i]
            }
        }
    }
    '
}

_normalize | _compute_stats
