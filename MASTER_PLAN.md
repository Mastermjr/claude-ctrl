# MASTER_PLAN: Claude Code Configuration System

<!--
@decision DEC-RECK-001 through DEC-RECK-007
@title Reckoning operationalization: restore institutional memory
@status accepted
@rationale Project reckoning (2026-03-07) found that a plan rewrite erased 73 decisions,
  12+ completed initiative summaries, and the Original Intent. User confirmed 9 decisions
  via /decide configurator to restore history, park orphaned initiatives, fix DEC-ID
  collision, and execute a strategic reset. This commit implements decisions 1-7.
-->

## Identity

**Type:** meta-infrastructure
**Languages:** Bash (85%), Markdown (10%), JSON/Python (5%)
**Root:** `/Users/turla/.claude`
**Created:** 2026-02-06
**Last updated:** 2026-03-14

The Claude Code configuration directory that shapes how Claude Code operates across all projects. It enforces development practices via hooks (deterministic shell scripts intercepting every tool call), four specialized agents (Planner, Implementer, Tester, Guardian), skills, and session instructions. Instructions guide; hooks enforce.

## Architecture

```
hooks/              — 26 hook scripts + 9 shared libraries; deterministic enforcement layer
agents/             — 5 agent prompt definitions (planner, implementer, tester, guardian, governor) + shared protocols
skills/             — 13 skill directories (deep-research, decide, reckoning, consume-content, etc.)
commands/           — Slash commands (/compact, /backlog); lightweight, no context fork
scripts/            — Utility scripts (statusline, worktree-roster, batch-fetch, etc.)
templates/          — MASTER_PLAN.md and initiative-block templates for Planner
docs/               — DISPATCH.md, development history; reference docs loaded on demand
observatory/        — Self-improving trace analysis flywheel
traces/             — Agent execution archive (index.jsonl + per-agent directories)
tests/              — Hook validation test suite
settings.json       — Hook registration (10 events, 24 hooks) + model config
CLAUDE.md           — Session instructions loaded every session (~149 lines, was ~255 pre-metanoia)
ARCHITECTURE.md     — Definitive technical reference (18 sections)
```

## Original Intent

> Build a configuration layer for Claude Code that enforces engineering discipline — git safety, documentation, proof-before-commit, worktree isolation — across all projects. The system should be self-governing: hooks enforce rules mechanically, agents handle specialized roles, and the observatory learns from traces to improve over time.

## Principles

These are the project's enduring design principles. They do not change between initiatives.

1. **Code is Truth** — Documentation derives from code; annotate at the point of implementation. When docs and code conflict, code is right.
2. **Main is Sacred** — Feature work happens in worktrees; main stays clean and deployable. Never work directly on main.
3. **Deterministic Enforcement** — Hooks enforce rules mechanically regardless of context pressure. Prompts inspire quality; hooks guarantee compliance.
4. **Ephemeral Agents, Persistent Knowledge** — Each agent is temporary; the plan, decisions, and code persist. Enable Future Implementers to succeed.
5. **Purpose Before Procedure** — Lead with WHY, then HOW. The model internalizes what it reads first. Purpose language at the top produces deep work; procedural language at the top produces compliance.

---

## Decision Log

Append-only record of significant decisions across all initiatives. Each entry references
the initiative and decision ID. This log persists across initiative boundaries — it is the
project's institutional memory.

| Date | DEC-ID | Initiative | Decision | Rationale |
|------|--------|-----------|----------|-----------|
| 2026-03-01 | DEC-HOOKS-001 | metanoia-remediation | Fix shellcheck violations inline (not suppress) | Real fixes are safer than disable annotations; violations indicate real fragility |
| 2026-03-01 | DEC-TRACE-002 | metanoia-remediation | Agent-type-aware outcome classification via lookup table | Different agents have different success signals; lookup table is extensible |
| 2026-03-01 | DEC-TRACE-003 | metanoia-remediation | Write compliance.json at trace init, update at finalize | Prevents write-before-read race when agents crash early |
| 2026-03-01 | DEC-PLAN-004 | metanoia-remediation | Reduce planner.md by extracting templates | 641 lines / 31KB consumes excessive context; target ~400 lines / ~20KB |
| 2026-03-01 | DEC-STATE-005 | metanoia-remediation | Registry-based state file cleanup | Orphaned state files accumulate; registry + cleanup script prevents drift |
| 2026-03-01 | DEC-TEST-006 | metanoia-remediation | Validation harness follows existing run-hooks.sh pattern | Consistency with 131-test suite; no new framework needed |
| 2026-03-02 | DEC-AUDIT-001 | hook-consolidation | Map hook-to-library dependencies via static analysis | Static grep is faster and more reliable than runtime tracing for bash |
| 2026-03-02 | DEC-TIMING-001 | hook-consolidation | Parse .hook-timing.log with awk for timing reports | Tab-separated fields, awk is universal, no new dependencies |
| 2026-03-02 | DEC-DEDUP-001 | hook-consolidation | Tighten hooks to exact-minimum require set | Duplicate requires indicate code rot; exact-minimum aids auditing |
| 2026-03-01 | DEC-STATE-007 | state-mgmt-reliability | Replace inline proof resolution with resolve_proof_file() | Canonical resolver handles worktree breadcrumbs correctly; inline copies diverge |
| 2026-03-01 | DEC-STATE-008 | state-mgmt-reliability | Pervasive validate_state_file before cut | Prevents crashes on corrupt/empty/truncated state files |
| 2026-03-02 | DEC-STATE-001 | state-mgmt-reliability | Centralized state coordination via state-lib.sh | Single library for proof lifecycle avoids scattered inline logic |
| 2026-03-02 | DEC-STATE-GOV-001 | state-mgmt-reliability | State governance tests in run-hooks.sh | Integration tests validate hook-level proof behavior end-to-end |
| 2026-03-02 | DEC-STATE-LIFECYCLE-001 | state-mgmt-reliability | Lifecycle E2E tests cover full proof-status state machine | Validates transitions: needs-verification -> verified -> committed with worktree isolation |
| 2026-03-02 | DEC-STATE-CORRUPT-001 | state-mgmt-reliability | Corruption tests exercise validate_state_file edge cases | Ensures empty, truncated, malformed, binary proof files are caught before cut |
| 2026-03-02 | DEC-STATE-CONCURRENT-001 | state-mgmt-reliability | Concurrency tests for simultaneous proof writes | Validates atomicity of write_proof_status under contention |
| 2026-03-02 | DEC-STATE-CLEAN-E2E-001 | state-mgmt-reliability | E2E tests for clean-state.sh audit and cleanup | clean-state.sh is the only recovery path for accumulated stale state |
| 2026-03-02 | DEC-STATE-SESSION-BOUNDARY-001 | state-mgmt-reliability | Session boundary proof cleanup tests | session-init.sh cleanup prevents cross-session contamination |
| 2026-03-02 | DEC-STATE-AUDIT-001 | state-mgmt-reliability | clean-state.sh audit script for state file hygiene | Registry-based detection of orphaned, stale, and corrupt state files |
| 2026-03-02 | DEC-SL-LAYOUT-001 | statusline-ia | Keep 2-line layout with domain clustering | Width analysis shows all segments fit in 2 lines; 3 lines would be more visually intrusive |
| 2026-03-02 | DEC-SL-TOKENS-001 | statusline-ia | Display aggregate tokens as compact K notation | Raw token counts unreadable; K notation is universally understood and fits ~10 chars |
| 2026-03-02 | DEC-SL-TODOCACHE-001 | statusline-ia | Add todo_project and todo_global to .statusline-cache | Existing cache is the natural home; avoids file proliferation |
| 2026-03-02 | DEC-SL-COSTPERSIST-001 | statusline-ia | Append session cost to .session-cost-history | Cross-session data needs persistent file; proven pattern from .compaction-log |
| 2026-03-02 | DEC-COST-PERSIST-001 | statusline-ia | Capture session-end stdin for multi-field extraction | Session-end JSON is small; variable capture enables both reason and cost reads |
| 2026-03-02 | DEC-COST-PERSIST-002 | statusline-ia | Pipe-delimited history file for session cost | Append-only, awk-summable, human-readable; trimmed to 100 entries |
| 2026-03-02 | DEC-TODO-SPLIT-001 | statusline-ia | Compute project/global todo counts via gh issue list | Split lets users distinguish project-scoped vs global backlog |
| 2026-03-02 | DEC-LIFETIME-COST-001 | statusline-ia | Sum lifetime cost from history at session start | O(N) over ~100 lines; inexpensive for running lifetime spend |
| 2026-03-02 | DEC-CACHE-003 | statusline-ia | Add todo_project, todo_global, lifetime_cost to cache | Three new fields default to 0; cache always valid JSON |
| 2026-03-02 | DEC-TODO-SPLIT-002 | statusline-ia | -1 sentinel for absent cache fields (backward compat) | Old caches lack split fields; sentinel enables legacy fallback |
| 2026-03-02 | DEC-TODO-SPLIT-003 | statusline-ia | Split display format with p/g suffixes and legacy fallback | todos: 3p 7g when both; project-only or global-only when one is 0 |
| 2026-03-02 | DEC-LIFETIME-COST-002 | statusline-ia | Display lifetime cost as Sigma annotation next to session cost | Compact, contextual; dim rendering avoids visual noise |
| 2026-03-02 | DEC-RSM-REGISTRY-001 | robust-state-mgmt | Protected state file registry in core-lib.sh | Centralized, extensible, <1ms overhead; pre-write.sh Gate 0 checks registry |
| 2026-03-02 | DEC-RSM-FLOCK-001 | robust-state-mgmt | POSIX advisory locks via flock() for concurrent writes | Sub-ms overhead, auto-release on death, crash-safe subshell pattern |
| 2026-03-02 | DEC-RSM-LATTICE-001 | robust-state-mgmt | Monotonic lattice enforcement on proof-status | Proof-status is a semilattice; enforcing monotonicity eliminates regression bugs |
| 2026-03-02 | DEC-RSM-SQLITE-001 | robust-state-mgmt | SQLite WAL replaces state.json | Zero new deps on macOS; atomic CAS via BEGIN IMMEDIATE; eliminates jq race |
| 2026-03-02 | DEC-RSM-STATEDIR-001 | robust-state-mgmt | Unified state directory $CLAUDE_DIR/state/ | Eliminates breadcrumb heuristics; clean per-project/worktree/agent scoping |
| 2026-03-02 | DEC-RSM-SELFCHECK-001 | robust-state-mgmt | Triple self-validation at session startup | Version sentinels + generation file + bash -n catch different failure modes |
| 2026-03-02 | DEC-RSM-DAEMON-001 | robust-state-mgmt | Unix socket state daemon for multi-instance coordination | Graceful degradation; fencing tokens per Kleppmann; MCP bridge for web agents |
| 2026-03-02 | DEC-BL-TODO-001 | backlog-auto-capture | Restore todo.sh as standalone script matching hook call signatures | Hooks already reference scripts/todo.sh; matches statusline.sh pattern; zero overhead when not called |
| 2026-03-02 | DEC-BL-CAPTURE-001 | backlog-auto-capture | Fire-and-forget auto-capture in prompt-submit.sh | prompt-submit.sh must stay <100ms; background todo.sh create adds zero latency |
| 2026-03-02 | DEC-BL-SCAN-001 | backlog-auto-capture | Standalone scan-backlog.sh with /scan command | Script + command pattern for testability; reusable from gaps-report.sh and CI |
| 2026-03-02 | DEC-BL-GAPS-001 | backlog-auto-capture | gaps-report.sh aggregating .plan-drift, scan-backlog.sh, gh issues | Unified accountability view from multiple existing data sources |
| 2026-03-02 | DEC-BL-TRIGGER-001 | backlog-auto-capture | Immediate fire-and-forget auto-capture on deferral detection | Batching risks data loss on crash; immediate is reliable and simple |
| 2026-03-04 | DEC-PROD-001 | production-reliability | Auto-discover test files via glob in CI | Hardcoded list silently excludes 52 of 61 test files; glob ensures all run |
| 2026-03-04 | DEC-PROD-002 | production-reliability | Capture stderr to file instead of suppressing | 2>/dev/null hides real hook errors; capture preserves diagnostics |
| 2026-03-04 | DEC-PROD-003 | production-reliability | Inline rotation in session-init.sh for state files | session-init already runs at start; tail -n 1000 rotation is O(1) additional work |
| 2026-03-04 | DEC-PROD-004 | production-reliability | SESSION_ID-based TTL sentinel scoping | PID reuse causes false matches; SESSION_ID is unique per session |
| 2026-03-04 | DEC-PROD-005 | production-reliability | Non-blocking macOS CI matrix job | macOS is primary dev platform but CI is Ubuntu-only; continue-on-error initially |
| 2026-03-05 | DEC-RSM-BOOTSTRAP-001 | robust-state-mgmt | Bootstrap paradox: document self-hosting gate risk | When gate infrastructure itself is broken, the gate blocks the fix; manual override required (#105) |
| 2026-03-05 | DEC-MODE-TAXONOMY-001 | operational-mode-system | 4-tier mode taxonomy: Observe/Amend/Patch/Build | Maps to 4 distinct risk profiles; monotonic escalation lattice validated by deep research |
| 2026-03-05 | DEC-MODE-STATE-001 | operational-mode-system | .op-mode state file with monotonic write_op_mode() | Pipe-delimited format; registered in _PROTECTED_STATE_FILES; atomic_write() for crash safety |
| 2026-03-05 | DEC-MODE-CLASSIFY-001 | operational-mode-system | Deterministic classifier in prompt-submit.sh | prompt-submit.sh already has keyword detection; conservative fallback to Mode 4 on ambiguity |
| 2026-03-05 | DEC-MODE-CONTRACT-001 | operational-mode-system | Component contract matrix enforced at hook level | Each hook reads .op-mode and conditionally engages gates per contract matrix |
| 2026-03-05 | DEC-MODE-ESCALATE-001 | operational-mode-system | One-way escalation engine with trigger rules | Irreversible within session; is_source_file() authoritative; audit trail for every escalation |
| 2026-03-05 | DEC-MODE-SAFETY-001 | operational-mode-system | 9 cross-mode safety invariants, never mode-conditional | Layer 1 enforcement (guard.sh) fires unconditionally; agent exploitation of lightweight paths documented |
| 2026-03-05 | DEC-MODE-PERSIST-001 | operational-mode-system | Re-classify mode after compaction with Previous Mode hint | Fresh classification safer than stale state; monotonic lattice prevents downgrade |
| 2026-03-05 | DEC-MODE-BRANCH-001 | operational-mode-system | Mode 2 relaxes branch-guard for non-source files | Guardian approval is sufficient; no protected-non-source list needed |
| 2026-03-05 | DEC-MODE-PLAN-001 | operational-mode-system | Mode 3 plan-check skip via .op-mode hook-level read | Skips MASTER_PLAN.md required but enforces staleness if plan exists |
| 2026-03-06 | DEC-DISPATCH-001 | dispatch-enforcement | Restore compact routing table to CLAUDE.md | Full table was extracted (DEC-DISPATCH-EXTRACT-001); model no longer sees "must invoke implementer" every turn |
| 2026-03-06 | DEC-DISPATCH-002 | dispatch-enforcement | SESSION_ID-based orchestrator detection in session-init.sh | SessionStart fires only for orchestrator; subagents get SubagentStart with different CLAUDE_SESSION_ID |
| 2026-03-06 | DEC-DISPATCH-003 | dispatch-enforcement | Gate 1.5 in pre-write.sh blocks orchestrator source writes | Closes the enforcement gap: implementer dispatch was instruction-only while Guardian was mechanically enforced |
| 2026-03-06 | DEC-XPLAT-001 | xplatform-reliability | _file_mtime() in core-lib.sh with OS detection at load time | 25 inline stat calls use macOS-first order; Linux stat -f %m returns mount point not mtime; single function with Linux-first detection prevents recurrence |
| 2026-03-06 | DEC-XPLAT-002 | xplatform-reliability | _with_timeout() wrapper using Perl fallback | Stock macOS lacks timeout command; Perl alarm+exec available everywhere; zero new dependencies |
| 2026-03-06 | DEC-XPLAT-003 | xplatform-reliability | Fix stale test references inline | Section names reference context-lib.sh (moved to core-lib.sh/source-lib.sh); CYCLE COMPLETE fixture for removed CYCLE_MODE; real fixes not suppression |
| 2026-03-06 | DEC-SQLITE-001 | sqlite-state-store | Global SQLite WAL database at $CLAUDE_DIR/state/state.db | WAL contention negligible for hook workloads; global simplifies cross-project queries and diagnostics |
| 2026-03-06 | DEC-SQLITE-002 | sqlite-state-store | workflow_id = {phash}_main / {phash}_{wt_basename} | Deterministic, stable across sessions; proof invalidation handles multi-instance safety |
| 2026-03-06 | DEC-SQLITE-003 | sqlite-state-store | Proof invalidation on write as multi-instance safety mechanism | Proof is about code state not instance identity; shared proof for shared worktree is correct |
| 2026-03-06 | DEC-SQLITE-004 | sqlite-state-store | PID-based liveness replaces TTL-based marker expiry | kill -0 is instantaneous and definitive; handles SIGKILL crashes that bypass cleanup hooks |
| 2026-03-06 | DEC-SQLITE-005 | sqlite-state-store | Automatic re-verification on proof invalidation (max 3 retries) | Keeps pipeline flowing without human intervention in multi-instance scenarios |
| 2026-03-06 | DEC-SQLITE-006 | sqlite-state-store | Dual-write/dual-read migration with 1-release soak period | Transparent migration; no data loss; flat files retained as fallback during transition |
| 2026-03-06 | DEC-SQLITE-007 | sqlite-state-store | One sqlite3 invocation per state operation | ~2-3ms per spawn well within budget; _state_sql() wrapper prepends WAL + busy_timeout pragmas |
| 2026-03-06 | DEC-SQLITE-008 | sqlite-state-store | History table replaces .audit-log and state.json history array | Structured history with SQL queries; capped at 500 entries per workflow via trigger |
| 2026-03-07 | DEC-PROMPT-001 | prompt-restoration | Hybrid CLAUDE.md: pre-metanoia voice + current procedural references | Pre-metanoia purpose language is sacred; current procedural references are useful but must follow purpose, not lead |
| 2026-03-07 | DEC-PROMPT-002 | prompt-restoration | Shared protocols injected via subagent-start.sh, not just referenced | Deterministic injection at dispatch time means agents don't need to remember to read a file; the hook ensures they see shared protocols (CWD safety, trace, return message) |
| 2026-03-07 | DEC-PROMPT-003 | prompt-restoration | "What Matters" section added to CLAUDE.md with quality-of-thought expectations | The model lacks explicit guidance on what deep work looks like; codifying it in purpose position produces better reasoning |
| 2026-03-07 | DEC-AUDIT-002 | governance-audit | Governance signal map as markdown in docs/governance-signal-map.md | One-time research artifact to inform optimization decisions; markdown is sufficient |
| 2026-03-09 | DEC-GOV-001 | governor-subagent | Use Opus for the governor agent | Governor's value is judgment quality; at ~2 dispatches/initiative, cost delta vs. Sonnet is negligible |
| 2026-03-09 | DEC-GOV-002 | governor-subagent | 4+4 dimension scoring rubric (initiative eval + meta-eval) | 4 initiative dimensions + 4 meta-evaluation dimensions; lean enough for ~15K tokens, structured for trend tracking |
| 2026-03-09 | DEC-GOV-003 | governor-subagent | Orchestrator instruction-based dispatch via DISPATCH.md | Follows existing auto-dispatch pattern; hook-based auto-dispatch is P2 upgrade path |
| 2026-03-09 | DEC-GOV-004 | governor-subagent | Bidirectional reckoning relationship — governor consumes AND provides | Governor reads recent reckoning verdict/trajectory; writes structured assessments for reckoning Phase 2 |
| 2026-03-09 | DEC-GOV-005 | governor-subagent | Read-only tools (Read, Grep, Glob) plus trace artifact writes | Enforces governor role — evaluates and reports, never acts; prevents scope creep |
| 2026-03-08 | DEC-LIFETIME-PERSIST-001 | statusline-ia | Read existing cache lifetime fields as fallback defaults in write_statusline_cache | write_statusline_cache() called from 7 hooks but only session-init.sh computes lifetime values; other callers were zeroing them out |
| 2026-03-08 | DEC-PROJECT-TOKEN-HISTORY-001 | statusline-ia | Add project_hash and project_name as columns 6+7 of .session-token-history | All sessions accumulated into one history; per-project columns enable project-scoped lifetime cost |
| 2026-03-08 | DEC-NO-TRIM-001 | statusline-ia | Remove 100-line trim from session history files | Each entry ~80 bytes; 10,000 entries (3 years) is under 1MB; trim caused data loss |
| 2026-03-09 | DEC-DUALBAR-001 | statusline-ia | Dual-color context bar: system overhead (dim) + conversation (severity-colored) | Single-color bar conflates system overhead with conversation usage; dual-color separates them |
| 2026-03-09 | DEC-DUALBAR-002 | statusline-ia | Baseline fingerprint: hash of config mtimes + model for invalidation | System overhead percentage needs recalculation when config changes; fingerprint detects drift |
| 2026-03-09 | DEC-DISPATCH-004 | dispatch-enforcement | Simple Task Fast Path for ≤2-file fixes | Orchestrator can handle trivial fixes (≤2 files, no new tests) directly without implementer dispatch; reduces overhead on easy tasks |
| 2026-03-09 | DEC-DISPATCH-005 | dispatch-enforcement | Interface Contracts and consumer-first pattern for multi-file features | Implementer defines interfaces in consumer code first, then implements providers; prevents integration surprises |
| 2026-03-09 | DEC-PROMPT-004 | prompt-restoration | Close initiative: 30-40% reduction target structurally unrealistic | shared-protocols supplements, doesn't replace; value delivered: Cornerstone Belief, What Matters, purpose-sandwich |
| 2026-03-09 | DEC-RECK-010 | reckoning-ops | Batch housekeeping: fix all 5 plan maintenance items | Breaks selectivity bias; one commit clears 5 persistent reckoning findings |
| 2026-03-09 | DEC-RECK-011 | reckoning-ops | Governance self-bypass: record and prevent | Simple Task Fast Path + Interface Contracts committed to main without worktrees; record and strengthen hooks |
| 2026-03-09 | DEC-RECK-012 | reckoning-ops | Structured issue triage session | 105 open issues; dedicate one session to close/park/refine |
| 2026-03-09 | DEC-RECK-013 | governance-audit | Close initiative — W1 delivered the value | Signal map + 7 proposals are the deliverable; W2 is busywork |
| 2026-03-09 | DEC-RECK-014 | reckoning-ops | Next strategic: Governance Efficiency | Directly addresses 60-310% overhead benchmark finding; 7 signal map proposals are starting point |
| 2026-03-09 | DEC-RECK-015 | reckoning-ops | Reckoning cadence: per-initiative boundaries | Natural checkpoint; enough time for findings to be acted on; typically every 1-2 weeks |
| 2026-03-09 | DEC-RECK-016 | reckoning-ops | Cap recursive evaluation at 3 layers, measure convergence | No new evaluative infrastructure until observatory+reckoning+governor prove value |
| 2026-03-09 | DEC-EFF-001 | governance-efficiency | Optimize-first, measure-after | Signal map proposals are thoroughly analyzed; measurement infrastructure would delay tangible improvement |
| 2026-03-09 | DEC-EFF-002 | governance-efficiency | Debug logging via .session-events.jsonl for demoted advisories | Preserves trace data for observatory/reckoning; model stops seeing noise but event log retains everything |
| 2026-03-09 | DEC-EFF-003 | governance-efficiency | File-mtime-based cache invalidation (DEC-PERF-004 pattern) | Existing stop.sh pattern proves the approach; no new cache mechanisms needed |
| 2026-03-09 | DEC-EFF-004 | governance-efficiency | Preserve all deny gates unconditionally | Deny gates are safety guarantees; advisory noise reduction yes, safety weakening never |
| 2026-03-09 | DEC-EFF-005 | governance-efficiency | Two-wave delivery: noise reduction then deduplication | Wave 1 low-risk advisory/caching; Wave 2 cross-hook changes need approve gate |
| 2026-03-09 | DEC-GOV-006 | governor-subagent | Two-tier evaluation model: health pulse + full evaluation | Full 8-dim eval at every trigger is expensive; health pulse provides quick deviation detection at ~3-5K tokens; orchestrator-judged frequency, no mechanical threshold |
| 2026-03-09 | DEC-GOV-HOOK-001 | governor-subagent | Layer A silent return recovery for governor hook | Empty governor response gets trace summary injected into additionalContext; mirrors check-implementer.sh pattern without blocking |
| 2026-03-09 | DEC-GOV-WIRE-002 | governor-subagent | check-planner.sh emits governor advisory for multi-wave plans | Mechanical trigger ensures governor dispatch isn't forgotten; instruction-compliance alone is insufficient for ephemeral orchestrators |
| 2026-03-09 | DEC-GOV-WIRE-003 | governor-subagent | session-init.sh surfaces last governor pulse timestamp and verdict | Orchestrator sees staleness at session start; meta-infrastructure recommends pulse if >7 days stale |
| 2026-03-09 | DEC-EFF-006 | governance-efficiency | Demote fast-mode bypass advisory to .session-events.jsonl | Fast mode is a Claude Code feature, not model-controlled; advisory added no behavioral value |
| 2026-03-09 | DEC-EFF-007 | governance-efficiency | Demote cold test-gate advisory to .session-events.jsonl | Deny gate (strike 2+) catches real failures; cold-start advisory added no blocking value |
| 2026-03-09 | DEC-EFF-008 | governance-efficiency | Churn cache with 300s TTL for pre-write.sh Gate 2 | <5% churn is genuinely trivial; cache saves nested git/grep on every source write |
| 2026-03-09 | DEC-EFF-009 | governance-efficiency | Doc-freshness fire-once-per-session via sentinel file | Model sees warning once (enough to act); deny gate is the real enforcement |
| 2026-03-09 | DEC-EFF-010 | governance-efficiency | Keyword match cache keyed on git+plan state fingerprint | Technical optimization; same signals produced, served from cache on identical context |
| 2026-03-09 | DEC-EFF-011 | governance-efficiency | Trajectory narrative cache keyed on git-state fingerprint | If nothing changed, same narrative is correct; stale cache invalidated on any mutation |
| 2026-03-09 | DEC-EFF-012 | governance-efficiency | Shared git state cache (5s TTL) in git-lib.sh | 5 hooks compute identical git state per event cycle; eliminates redundant subprocess spawns |
| 2026-03-09 | DEC-EFF-013 | governance-efficiency | Shared plan state cache (10s TTL, 18 vars) in plan-lib.sh | 5 hooks parse MASTER_PLAN.md per event cycle; eliminates redundant awk/grep passes |
| 2026-03-09 | DEC-EFF-014 | governance-efficiency | Keep prompt-vs-hook overlap (belt and suspenders) | Prompt compliance and hook enforcement serve different failure modes; defense-in-depth preserved |
| 2026-03-09 | DEC-DBSAFE-001 | db-safety | Defense-in-depth via 5-layer interception | 6-provider research consensus (129+ citations): shell-level hooks alone are insufficient; 5 layers needed (nuclear deny, CLI-aware, IaC/container, Database Guardian, MCP governance) |
| 2026-03-09 | DEC-DBSAFE-002 | db-safety | Environment tiering: dev=permissive, staging=approval, prod=read-only, unknown=deny | 3/3 Round 2 research providers converge on this exact model; unknown environments treated conservatively |
| 2026-03-09 | DEC-DBSAFE-003 | db-safety | Database Guardian subagent as sole database credential holder | Research consensus: agents are non-deterministic privileged entities requiring credential isolation; mirrors proven Git Guardian pattern |
| 2026-03-09 | DEC-DBSAFE-004 | db-safety | MCP governance via PreToolUse hook, not full proxy | Hook-based interception at JSON-RPC argument level provides governance without infrastructure changes; full proxy is P2 |
| 2026-03-09 | DEC-DBSAFE-005 | db-safety | Regex-based pattern matching at hook layer, no SQL AST parsing | Consistent with guard.sh approach; hook layer stays fast (<10ms); Database Guardian handles deeper analysis |
| 2026-03-09 | DEC-DBSAFE-006 | db-safety | Modular _db_check_*() functions for extensibility | Each CLI/IaC/container tool gets its own handler function; new databases added by writing a function and registering in early-exit gate |
| 2026-03-09 | DEC-STATE-UNIFY-001 | state-unification | BEGIN IMMEDIATE for all write transactions | Prevents read-then-write deadlock under WAL concurrent access; 3/3 deep research providers consensus |
| 2026-03-09 | DEC-STATE-UNIFY-002 | state-unification | _migrations table for schema versioning | Per-migration records with checksums; supports rollback detection; better than PRAGMA user_version for plugin systems |
| 2026-03-09 | DEC-STATE-UNIFY-003 | state-unification | Typed tables for structured state + KV for ad-hoc | proof_state, agent_markers, events get proper indexes and constraints; generic KV retained for ad-hoc state |
| 2026-03-09 | DEC-STATE-UNIFY-004 | state-unification | Dual-read for 2 releases during transition | SQLite primary, flat-file fallback covers in-flight worktree lifetimes; prevents data loss during migration |
| 2026-03-09 | DEC-STATE-UNIFY-005 | state-unification | Event ledger with consumer checkpoints | Append-only events table with per-consumer offsets; enables async governor triggers, observatory signals, cross-session coordination |
| 2026-03-09 | DEC-STATE-UNIFY-006 | state-unification | Lint enforcement gated on migration completion | Cannot deny dotfile I/O while hooks still use it; enforce only after W5-1 complete |
| 2026-03-09 | DEC-STATE-UNIFY-007 | state-unification | Version-gated fallback for backward compatibility | Graceful mixed-version handling during dual-read window; multiple Claude instances may run different code |
| 2026-03-12 | DEC-STATE-UNIFY-008 | state-unification | Single SQLite DB for state + events + observatory signals | ~365K events/year (~180MB); WAL handles concurrency; second DB only for large blobs |
| 2026-03-12 | DEC-STATE-UNIFY-009 | state-unification | Events are institutional memory — never deleted | User directive: archive to cold storage, never discard; observatory organizes history |
| 2026-03-12 | DEC-STATE-UNIFY-010 | state-unification | Observatory converges into event ledger as consumer | Unifies observatory into same coordination substrate as governor triggers and proof transitions |
| 2026-03-12 | DEC-STATE-KV-001 | state-unification | Orchestrator SID to SQLite KV with flat-file fallback | First KV migration; dual-write pattern established for session-scoped state |
| 2026-03-12 | DEC-STATE-KV-002 | state-unification | Session start epoch + prompt count to SQLite KV | Counter state migrated; flat-file fallback preserved |
| 2026-03-12 | DEC-STATE-KV-003 | state-unification | Token history to session_tokens table | Atomic lifetime tracking replaces awk-summed flat file; cost_usd column added |
| 2026-03-12 | DEC-STATE-KV-004 | state-unification | Session cost history to SQLite via cost_usd column | Leverages session_tokens table from KV-003; same INSERT pattern |
| 2026-03-13 | DEC-STATE-KV-005 | state-unification | Test status to SQLite KV | read_test_status() in core-lib.sh migrates all 11+ consumer hooks at once |
| 2026-03-13 | DEC-STATE-KV-006 | state-unification | Todo count to SQLite KV | Dual-write in session-init.sh, stop.sh, scripts/todo.sh |
| 2026-03-13 | DEC-STATE-KV-007 | state-unification | Agent findings audit trail via state_emit | Events are institutional memory (DEC-STATE-UNIFY-009); flat file preserved for consume-and-clear |
| 2026-03-14 | DEC-V4-LINT-001 | v4-release | Replace per-file lint cooldown sentinels with single-file approach | Per-file sentinels create 200+ orphaned files per session; single-file eliminates root cause |
| 2026-03-14 | DEC-V4-ORCH-001 | v4-release | Remove .orchestrator-sid flat-file write and fallback read | SQLite KV is sole authority (DEC-STATE-KV-001); flat-file paths are dead code |
| 2026-03-14 | DEC-V4-ORPHAN-001 | v4-release | Delete orphaned Governance Efficiency cache files | .git-state-cache and .plan-state-cache have zero writers/readers after revert 2b1f32a |
| 2026-03-14 | DEC-V4-KV-001 | v4-release | Migrate 3 MCP/DB-safety dotfiles to SQLite KV | Established dual-write pattern (KV-001 through KV-007); these files also lack session-end cleanup |
| 2026-03-14 | DEC-V4-GITIGNORE-001 | v4-release | Gitignore only files that legitimately must be flat files | User directive: eliminate root causes, not paper over; 3 categories: eliminate, migrate, gitignore |
| 2026-03-14 | DEC-V4-DOC-001 | v4-release | Documentation refresh independent of code changes | ARCHITECTURE/README/CHANGELOG fixes are pure docs; parallel execution cuts critical path |

---

## Active Initiatives

### Initiative: v4 Release Prep
**Status:** active
**Started:** 2026-03-14
**Goal:** Ship v4.0.0 — eliminate runtime file pollution, rework broken file mechanisms, migrate remaining dotfiles to SQLite KV, and update all documentation to reflect current system state.

> The codebase reached v4 maturity through 10 completed initiatives (State Unification, DB Safety, Governor, etc.) but the packaging has not kept pace. Repository hygiene shows 200+ untracked `.lint-cooldown-*` files per session (never cleaned up between sessions by the mechanism itself), orphaned cache files from reverted code, and 4 runtime dotfiles still using flat-file I/O despite SQLite being sole authority. Documentation claims "4 agents" when there are 6, "7 skills" when there are 12, and README still carries v3 branding. The user's directive: don't just gitignore these problems — think deeper about whether they should exist at all. Eliminate root causes, migrate meaningful state, gitignore only what legitimately must be a flat file.

**Dominant Constraint:** maintainability

#### Goals
- REQ-GOAL-V4-001: Repository is clean to clone — `git status` shows zero untracked runtime artifacts after fresh clone
- REQ-GOAL-V4-002: All documentation accurately reflects current system state (6 agents, 12 skills, 39 hooks, v4 branding)
- REQ-GOAL-V4-003: CHANGELOG.md has a consolidated v4.0.0 section covering all changes since v3.0.0
- REQ-GOAL-V4-004: MASTER_PLAN.md reflects reality — completed initiatives compressed, no stale active initiatives
- REQ-GOAL-V4-005: Zero remaining flat-file state I/O for session-scoped dotfiles — all 4 remaining files migrated to SQLite KV or eliminated

#### Non-Goals
- REQ-NOGO-V4-001: New features — v4 is a release checkpoint, not a feature release
- REQ-NOGO-V4-002: Test suite expansion beyond what release blockers require — existing 83 test files / 372+ tests are sufficient
- REQ-NOGO-V4-003: Resolving all 50+ open issues — issue triage is a separate effort (DEC-RECK-012)
- REQ-NOGO-V4-004: Statusline reorg changes — `feature/statusline-reorg` already merged to main; this initiative does not own that work
- REQ-NOGO-V4-005: Rearchitecting the AUTOVERIFY pipeline — document current operational state, not redesign

#### Requirements

**Must-Have (P0)**

- REQ-P0-V4-001: Rework `.lint-cooldown-*` mechanism — replace per-file sentinels with single-file approach
  Acceptance: Given lint.sh fires on a write, When cooldown is checked, Then a single file (e.g., `tmp/.lint-cooldowns` or SQLite KV) stores all cooldown timestamps instead of one file per edited path. Zero `.lint-cooldown-*` files created in project root.
- REQ-P0-V4-002: Remove `.orchestrator-sid` flat-file write — SQLite KV is sole authority (DEC-STATE-KV-001)
  Acceptance: Given session-init.sh writes orchestrator SID, When code is inspected, Then only `state_update("orchestrator_sid")` call exists — no flat-file write. Given pre-write.sh reads SID, When fallback path is inspected, Then flat-file fallback removed (KV is reliable).
- REQ-P0-V4-003: Delete orphaned `.git-state-cache` and `.plan-state-cache` files — dead artifacts from reverted Governance Efficiency
  Acceptance: Given these files exist on disk, When cleanup runs, Then files deleted and patterns added to `.gitignore` as safety net.
- REQ-P0-V4-004: Migrate `.db-safety-stats` to SQLite KV — session-scoped counters (checked/blocked/warned)
  Acceptance: Given db-safety hooks increment stats, When `_db_increment_stat()` fires, Then KV dual-write pattern used. Session-end cleanup added. Flat file gitignored.
- REQ-P0-V4-005: Migrate `.mcp-rate-state` to SQLite KV — window counter (count|start_epoch)
  Acceptance: Given MCP rate limiter fires, When state is read/written, Then KV used with flat-file fallback. Session-end cleanup added.
- REQ-P0-V4-006: Migrate `.mcp-credential-advisory-emitted` to SQLite KV — boolean sentinel
  Acceptance: Given first MCP DB call checks sentinel, When sentinel queried, Then `state_read("mcp_credential_advisory")` used. Session-end cleanup added.
- REQ-P0-V4-007: Gitignore all remaining runtime files that legitimately exist as flat files
  Acceptance: Given `.gitignore`, When patterns checked, Then covers: `.hooks-gen`, `.statusline-baseline`, `.session-events.jsonl`, `.db-safety-stats`, `.mcp-rate-state`, `.mcp-credential-advisory-emitted`, `.orchestrator-sid`, `.git-state-cache`, `.plan-state-cache`
- REQ-P0-V4-008: Remove `hooks/.claude/` directory — stale February artifacts (pre-metanoia), not git-tracked
  Acceptance: Given directory exists on disk, When cleanup runs, Then directory deleted. Pattern `hooks/.claude/` added to `.gitignore`.
- REQ-P0-V4-009: MASTER_PLAN.md — compress Database Safety Framework to Completed Initiatives
  Acceptance: Given DB Safety all 5 waves shipped, When MASTER_PLAN.md is read, Then initiative appears under `## Completed Initiatives` with summary narrative.
- REQ-P0-V4-010: ARCHITECTURE.md counts corrected — 6 agents, 12 skills, 39 hooks, 83 test files
  Acceptance: Given ARCHITECTURE.md, When counts are checked, Then they match actual filesystem (`ls agents/*.md | wc -l` minus shared-protocols = 6, etc.)
- REQ-P0-V4-011: README.md updated from v3 to v4 branding with accurate system counts
  Acceptance: Given README.md, When version references checked, Then all say v4 with correct counts.
- REQ-P0-V4-012: CHANGELOG.md `[Unreleased]` consolidated into `## [4.0.0] - 2026-03-14`
  Acceptance: Given CHANGELOG.md, When reading, Then v4.0.0 section exists with all post-v3 changes organized by Added/Changed/Fixed/Removed.
- REQ-P0-V4-013: AUTOVERIFY gate documented — current operational state captured in release notes
  Acceptance: Given AUTOVERIFY is operational in post-task.sh with guardian inference fallback (DEC-AV-GUARDIAN-001), When release notes read, Then current state and rationale documented.

**Nice-to-Have (P1)**

- REQ-P1-V4-001: Git tag `v4.0.0` created after all blockers resolved
- REQ-P1-V4-002: Session-end cleanup for `.db-safety-stats`, `.mcp-rate-state`, `.mcp-credential-advisory-emitted` (currently accumulate forever)
- REQ-P1-V4-003: Governor health pulse at release boundary (post-completion evaluation)

**Future Consideration (P2)**

- REQ-P2-V4-001: Automated release checklist hook that runs pre-tag validation
- REQ-P2-V4-002: Issue triage session to close/park 50+ open issues (DEC-RECK-012)

#### Definition of Done

All 13 P0 requirements pass acceptance criteria. `.lint-cooldown-*` mechanism reworked to single-file approach. `.orchestrator-sid` flat-file write removed. Orphaned cache files deleted. 3 dotfiles migrated to SQLite KV with session-end cleanup. All runtime files gitignored. `hooks/.claude/` removed. MASTER_PLAN.md current (DB Safety compressed). ARCHITECTURE.md and README.md counts accurate. CHANGELOG.md has v4.0.0 section. AUTOVERIFY documented. Satisfies: REQ-GOAL-V4-001 through REQ-GOAL-V4-005.

#### Architectural Decisions

- DEC-V4-LINT-001: Replace per-file lint cooldown sentinels with single-file approach
  Addresses: REQ-P0-V4-001.
  Rationale: Current mechanism in `hooks/lint.sh:63` creates one `.lint-cooldown-{path}` file per edited file, encoding the full path in the filename. A typical session edits 50-100 files, creating 50-100 sentinel files. `session-init.sh:955` cleans them up, but only at next session start — if the repo is cloned between sessions, all sentinels appear as untracked. Single-file approach (e.g., `tmp/.lint-cooldowns` with `path|timestamp` lines, or SQLite KV) eliminates the problem at its root while preserving the 3-second debounce behavior.

- DEC-V4-ORCH-001: Remove .orchestrator-sid flat-file write and fallback read
  Addresses: REQ-P0-V4-002.
  Rationale: DEC-STATE-KV-001 migrated this to SQLite KV. The flat-file write in `session-init.sh:161` and fallback read in `pre-write.sh:261-263` are dead code paths — KV always succeeds (SQLite is sole authority since State Unification W5-2). Removing the dual-write eliminates a file that appears untracked on dirty repos. The `session-end.sh:488` flat-file cleanup also becomes unnecessary.

- DEC-V4-ORPHAN-001: Delete orphaned Governance Efficiency cache files
  Addresses: REQ-P0-V4-003.
  Rationale: `.git-state-cache` and `.plan-state-cache` were created by `_cached_git_state()` and `_cached_plan_state()` in the Governance Efficiency initiative (W2). That code was fully reverted (commit 2b1f32a). No writers or readers exist in the codebase. These files are orphaned artifacts that will confuse anyone inspecting the repo.

- DEC-V4-KV-001: Migrate 3 MCP/DB-safety dotfiles to SQLite KV following established pattern
  Addresses: REQ-P0-V4-004, REQ-P0-V4-005, REQ-P0-V4-006.
  Rationale: DEC-STATE-KV-001 through KV-007 established the dual-write migration pattern. These 3 files (`.db-safety-stats`, `.mcp-rate-state`, `.mcp-credential-advisory-emitted`) are session-scoped counters/sentinels — the simplest KV migration category. All have exactly 1 writer and 1 reader. None have session-end cleanup (they accumulate forever), which is itself a bug. KV migration + session-end cleanup solves both problems.

- DEC-V4-GITIGNORE-001: Gitignore only files that legitimately must be flat files
  Addresses: REQ-P0-V4-007.
  Rationale: The user's directive: "think deeper about whether they should exist at all." Three categories emerged from analysis: (1) ELIMINATE — rework mechanism or remove dead code; (2) MIGRATE — meaningful state moves to KV; (3) GITIGNORE — only for files that legitimately need to be flat files (`.hooks-gen` written by git post-merge before session starts, `.statusline-baseline` workspace-scoped performance cache, `.session-events.jsonl` crash-recovery safety net).

- DEC-V4-DOC-001: Documentation refresh is independent of code changes
  Addresses: REQ-GOAL-V4-002, REQ-GOAL-V4-003.
  Rationale: ARCHITECTURE.md, README.md, and CHANGELOG.md fixes are pure documentation — no code dependencies on KV migrations or lint rework. Running them in parallel cuts the critical path.

#### Waves

##### Initiative Summary
- **Total items:** 5
- **Critical path:** 3 waves (W1 -> W2 -> W3)
- **Max width:** 2 (Waves 1 and 2)
- **Gates:** 2 review, 1 approve

##### Wave 1: Eliminate + Clean (no dependencies)
**Parallel dispatches:** 2

**W1-1: Lint cooldown rework + orphan cleanup + gitignore (#243)** — Weight: M, Gate: review
- Rework `hooks/lint.sh` cooldown mechanism: replace per-file `.lint-cooldown-{path}` sentinels with single-file approach. Options: (a) `tmp/.lint-cooldowns` with `path|timestamp` lines, read via grep, write via atomic append+rewrite; (b) SQLite KV with `lint_cooldown_{hash}` keys. Implementer decides based on lint.sh latency budget (<10ms).
- Remove `session-init.sh:955` bulk cleanup (`rm -f "${CLAUDE_DIR}/.lint-cooldown-"*`) — mechanism no longer creates these files.
- Update `hooks/lint.sh` state-dotfile-bypass allowlist (line 146) — `.lint-cooldown` pattern may need adjustment depending on new mechanism.
- Delete orphaned files from disk: `.git-state-cache`, `.plan-state-cache`
- Remove `.orchestrator-sid` flat-file write from `session-init.sh:160-161` (keep only `state_update` on line 158)
- Remove `.orchestrator-sid` flat-file fallback read from `pre-write.sh:259-263` (keep only `state_read` on line 258)
- Remove `.orchestrator-sid` flat-file cleanup from `session-end.sh:488` (keep only `state_delete` on line 486)
- Update tests: `test-orchestrator-guard.sh` assertions for flat-file behavior need updating to KV-only behavior
- Add `.gitignore` entries: `.hooks-gen`, `.statusline-baseline`, `.session-events.jsonl`, `.db-safety-stats`, `.mcp-rate-state`, `.mcp-credential-advisory-emitted`, `.orchestrator-sid`, `.git-state-cache`, `.plan-state-cache`, `hooks/.claude/`
- Remove `hooks/.claude/` directory from disk (stale pre-metanoia artifacts)
- **Integration:** `hooks/lint.sh`, `hooks/session-init.sh`, `hooks/pre-write.sh`, `hooks/session-end.sh`, `.gitignore`, `tests/test-orchestrator-guard.sh`

**W1-2: MASTER_PLAN.md maintenance — compress DB Safety (this planner session)** — Weight: S, Gate: none
- Move Database Safety Framework from `## Active Initiatives` to `## Completed Initiatives`
- Write completion summary (period, phases, key decisions, all P0 satisfied)
- Append new Decision Log entries for v4 Release initiative
- This is the current planner task (this plan itself)
- **Integration:** `MASTER_PLAN.md`

##### Wave 2: KV Migrations + Documentation Refresh
**Parallel dispatches:** 2
**Blocked by:** W1-1 (gitignore must cover files being migrated; lint rework must land first)

**W2-1: Final KV migrations — 3 dotfiles to SQLite (#244)** — Weight: M, Gate: review, Deps: W1-1
- `.db-safety-stats` -> SQLite KV:
  - `_db_increment_stat()` in `hooks/db-safety-lib.sh:1385`: add `state_update("db_safety_{category}", value)` dual-write alongside flat-file
  - `_db_session_summary()` in `hooks/db-safety-lib.sh:1436`: add `state_read("db_safety_checked")` primary read with flat-file fallback
  - `_db_read_session_stats()` in `hooks/db-safety-lib.sh:1471`: same dual-read pattern
  - Add `require_state` call at top of db-safety-lib.sh (or in caller hooks that source it)
  - Add session-end cleanup: `state_delete "db_safety_checked" && state_delete "db_safety_blocked" && state_delete "db_safety_warned"` + `rm -f .db-safety-stats`
- `.mcp-rate-state` -> SQLite KV:
  - `hooks/pre-mcp.sh:205-216`: replace flat-file read/write with `state_read("mcp_rate_count")` / `state_update("mcp_rate_count", $_RATE_COUNT)` and `state_read("mcp_rate_start")` / `state_update("mcp_rate_start", $_RATE_START)`
  - Add session-end cleanup: `state_delete "mcp_rate_count" && state_delete "mcp_rate_start"` + `rm -f .mcp-rate-state`
- `.mcp-credential-advisory-emitted` -> SQLite KV:
  - `hooks/pre-mcp.sh:145-152`: replace `touch` sentinel with `state_update("mcp_credential_advisory", "1")`. Replace `[[ -f ]]` check with `state_read("mcp_credential_advisory")`.
  - Add session-end cleanup: `state_delete "mcp_credential_advisory"` + `rm -f .mcp-credential-advisory-emitted`
- Tests: extend `tests/test-session-kv.sh` with KV assertions for all 3 migrations
- **Integration:** `hooks/db-safety-lib.sh`, `hooks/pre-mcp.sh`, `hooks/session-end.sh`, `tests/test-session-kv.sh`

**W2-2: Documentation refresh — ARCHITECTURE, README, CHANGELOG (#245)** — Weight: M, Gate: review, Deps: W1-2
- ARCHITECTURE.md: Fix counts — 6 agents (planner, implementer, tester, guardian, governor, db-guardian; shared-protocols is a library), 12 skills, 39 hooks, 83 test files. Update stale references to "~20 state files" (now SQLite sole authority). Update agent layer description.
- README.md: Update from v3 to v4 branding. Update system counts in overview section. Add DB Safety and Governor to feature highlights. Update hook/skill/agent counts. Document AUTOVERIFY current operational state (operational in post-task.sh with guardian inference fallback).
- CHANGELOG.md: Consolidate `[Unreleased]` into `## [4.0.0] - 2026-03-14`. Organize entries by Added/Changed/Fixed/Removed per Keep a Changelog. Add v4 summary header describing the release highlights.
- **Integration:** `ARCHITECTURE.md`, `README.md`, `CHANGELOG.md`

##### Wave 3: Release Validation + Tag
**Parallel dispatches:** 1
**Blocked by:** W2-1, W2-2 (all blockers must be resolved)

**W3-1: Release validation + v4.0.0 tag (#246)** — Weight: S, Gate: approve, Deps: W2-1, W2-2
- Run full test suite (`tests/run-hooks.sh`), verify all pass
- Verify `git status` shows minimal untracked files (only intentional non-repo files)
- Verify ARCHITECTURE.md counts match filesystem: `ls agents/*.md | grep -v shared | wc -l` = 6, `ls -d skills/*/ | grep -v .claude | wc -l` = 12
- Verify CHANGELOG.md has v4.0.0 section with date
- Verify MASTER_PLAN.md has no stale active initiatives
- Create git tag `v4.0.0` on main after merge
- **Integration:** Git tag; no file changes

##### Critical Files
- `hooks/lint.sh` — cooldown mechanism rework (lines 62-71)
- `hooks/session-init.sh` — orchestrator-sid flat-file removal, lint cooldown cleanup removal
- `hooks/pre-write.sh` — orchestrator-sid fallback read removal (lines 259-263)
- `hooks/session-end.sh` — session-end cleanup additions for KV-migrated state
- `hooks/db-safety-lib.sh` — db-safety-stats KV migration (lines 1385-1489)
- `hooks/pre-mcp.sh` — mcp-rate-state + credential advisory KV migration (lines 145-216)
- `.gitignore` — runtime file patterns
- `ARCHITECTURE.md` — system reference counts
- `README.md` — public-facing documentation and version branding
- `CHANGELOG.md` — release history

##### Decision Log
<!-- Guardian appends here after wave completion -->

#### v4 Release Worktree Strategy

Main is sacred. Each wave dispatches parallel worktrees:
- **Wave 1:** `.worktrees/v4-hygiene` on branch `feature/v4-hygiene` (W1-1), `.worktrees/v4-release` on branch `feature/v4-release` (W1-2 — this planner session)
- **Wave 2:** `.worktrees/v4-kv-final` on branch `feature/v4-kv-final` (W2-1), `.worktrees/v4-docs` on branch `feature/v4-docs` (W2-2)
- **Wave 3:** `.worktrees/v4-tag` on branch `feature/v4-tag` (W3-1)

#### v4 Release References

- Runtime file analysis: `traces/planner-20260313-235901-e61b6c/artifacts/analysis.md`
- KV migration pattern: DEC-STATE-KV-001 through KV-007 (State Unification initiative)
- Lint cooldown mechanism: `hooks/lint.sh:62-71`, `hooks/session-init.sh:952-955`
- Orphaned cache files: reverted in commit 2b1f32a (Governance Efficiency W1/W2 revert)
- Orchestrator SID migration: DEC-STATE-KV-001, `hooks/session-init.sh:147-162`
- Related issues: #238 (lint cooldown redesign), #234 (statusline data migration), #226 (DB-SAFE-A1 heredoc false positive), #223 (state.db protection gap)

---

## Completed Initiatives

| Initiative | Period | Phases | Key Decisions | Archived |
|-----------|--------|--------|---------------|----------|
| Governance Efficiency | 2026-03-09 | 2 (W1+W2) | DEC-EFF-001 through DEC-EFF-014 (14 decisions) — REVERTED 2026-03-10 | No |
| Production Remediation (Metanoia Suite) | 2026-02-28 to 2026-03-01 | 5 | DEC-HOOKS-001 thru DEC-TEST-006 | No |
| State Management Reliability | 2026-03-01 to 2026-03-02 | 5 | DEC-STATE-007, DEC-STATE-008 + 8 test decisions | No |
| Hook Consolidation Testing & Streamlining | 2026-03-02 | 4 | DEC-AUDIT-001, DEC-TIMING-001, DEC-DEDUP-001 | No |
| Statusline Information Architecture | 2026-03-02 | 2 | DEC-SL-LAYOUT-001, DEC-SL-TOKENS-001, DEC-SL-TODOCACHE-001, DEC-SL-COSTPERSIST-001 | No |
| Robust State Management | 2026-03-02 to 2026-03-05 | 2 (of 7 planned) | DEC-RSM-REGISTRY-001 through DEC-RSM-SELFCHECK-001 (6 decisions) | No |
| Prompt Purpose Restoration | 2026-03-07 to 2026-03-09 | 3 (W1-1, W1-2, W2-1) | DEC-PROMPT-001, DEC-PROMPT-002, DEC-PROMPT-003, DEC-PROMPT-004 | No |
| Governance Signal Audit | 2026-03-07 to 2026-03-09 | 1 (W1-3) | DEC-AUDIT-002, DEC-RECK-013 | No |
| State Unification | 2026-03-09 to 2026-03-13 | 7 (W1-W6 + KV migrations) | DEC-STATE-UNIFY-001 through 010 + DEC-STATE-KV-001 through 007 (17 decisions) | No |
| Database Safety Framework | 2026-03-09 to 2026-03-13 | 5 (W1-W5, all shipped) | DEC-DBSAFE-001 through 006 + DEC-DBGUARD-001 through 009 + DEC-MCP-001 through 003 (18 decisions) | No |

### Governance Efficiency — Summary

**REVERTED** (2b1f32a, 2026-03-10): All W1+W2 code removed. W1 keyword cache had 0% hit rate (GIT_DIRTY_COUNT invalidation). T2 backstop and governor wiring (out-of-scope) caused guardian failure cascades and context overload. Goal remains valid; approach was flawed. See #222 for governor wiring redesign.


Reduced governance overhead (60-310% excess on easy tasks) through 9 targeted optimizations across 2 waves, without weakening any deny gates. W1 (noise reduction): demoted 2 low-value advisories to debug log, added churn/keyword/trajectory caches, doc-freshness fire-once-per-session — 6 optimizations across 4 hooks. W2 (deduplication): created `_cached_git_state()` (5s TTL) and `_cached_plan_state()` (10s TTL, 18 variables) in shared libraries, wired into 8 consumer hooks. Performance: 9.2x speedup on prompt-submit.sh (1.5s to 0.17s cache hit), 21x on stop.sh (6.7s to 0.32s). Safety invariant DEC-EFF-004 held: all deny gate counts preserved (pre-write: 14, pre-bash: 32, task-track: 9). 68/68 tests across 3 suites.

### Production Remediation (Metanoia Suite) — Summary

Fixed defects left by the metanoia hook consolidation (17 hooks -> 4 entry points + 6 domain libraries). Five phases over 3 days:

1. **CI Green** (919a2f0): Migrated 131 tests to consolidated hooks, 0 failures.
2. **Trace Reliability** (1372603): Shellcheck clean, agent-type-aware classification, compliance.json race fix, repair-traces.sh, 15 trace classification tests.
3. **Planner Reliability** (3796e35): planner.md slimmed 641->389 lines via template extraction, max_turns 40->65, silent dispatch fixes.
4. **State Cleanup** (22aff13): Worktree-roster cleans breadcrumbs on removal, resolve_proof_file falls back gracefully, clean-state.sh audit script.
5. **Validation Harness** (b36f3ad): 20 trace fixtures across 4 agent types x 5 outcomes, validation harness with 95% accuracy gate, regression detection via baseline diffing.

All P0 requirements satisfied. 6 architectural decisions recorded (DEC-HOOKS-001 through DEC-TEST-006). Issues closed: #39, #40, #41, #42.

### State Management Reliability — Summary

Unified all proof-status reads to canonical `resolve_proof_file()` and hardened `validate_state_file()` across the hook system. Five phases over 2 days:

1. **Phase 1 — Proof-Read Unification** (6158a09): task-track.sh, pre-bash.sh, post-write.sh migrated to resolve_proof_file(). #48
2. **Phase 2 — Hardening** (d8dfe39): subagent-start.sh, session-end.sh, stop.sh, prompt-submit.sh migrated; validate_state_file guards all cut sites. #49
3. **Phase 3 — Lifecycle E2E** (a5ad943): 12 lifecycle tests + 6 resolver consistency tests. #50
4. **Phase 4 — Corruption + Concurrency** (dc965d3): 8 corruption tests + 6 concurrency tests. #51
5. **Phase 5 — Clean-state + Session Boundary** (9e16837): 8 clean-state E2E tests + 6 session boundary tests. #52

All 6 P0 requirements satisfied. 28 new tests added (total suite: 159 tests, 0 failures, 3 pre-existing skips). 10 decisions recorded (DEC-STATE-007, DEC-STATE-008, DEC-STATE-001, DEC-STATE-GOV-001, DEC-STATE-LIFECYCLE-001, DEC-STATE-CORRUPT-001, DEC-STATE-CONCURRENT-001, DEC-STATE-CLEAN-E2E-001, DEC-STATE-SESSION-BOUNDARY-001, DEC-STATE-AUDIT-001). Issues closed: #48, #49, #50, #51, #52.

### Hook Consolidation Testing & Streamlining — Summary

Validated, audited, and streamlined the hook system after the lazy-loading performance refactor (`require_*()` in source-lib.sh). Four phases in 1 day:

1. **Phase 1 — Testing & Timing Validation** (#44): 159/159 tests pass, hook-timing-report.sh created with p50/p95/max per hook type, all 11 `--scope` values validated including edge cases.
2. **Phase 2 — Hook Dependency Audit & Deduplication** (#45): Static analysis audit mapped every hook to its minimum required libraries, duplicate `require_*()` calls removed from task-track.sh and other hooks.
3. **Phase 3 — Dead Code Removal & Hot Path** (#46): Dead code paths removed, pre-bash.sh early-exit and pre-write.sh worktree-skip verified optimal, context-lib.sh retained as test/diagnose shim, state registry lint added to test runner.
4. **Phase 4 — Documentation Update** (43b7c5c): HOOKS.md updated with require_*() table and --scope docs, README.md updated with domain library entries and utility scripts, ARCHITECTURE.md rewritten with lazy loading diagram and performance notes.

All 6 P0 requirements satisfied. 3 architectural decisions recorded (DEC-AUDIT-001, DEC-TIMING-001, DEC-DEDUP-001). Issues closed: #44, #45, #46, #47.

### Statusline Information Architecture — Summary

Redesigned the statusline HUD from raw unlabeled numbers to a domain-clustered, labeled two-line display with data enrichment. Two phases in 1 day:

1. **Phase 1 — Rendering Overhaul** (feature/statusline-rendering): Domain-clustered layout with labels on all segments (`dirty:`, `wt:`, `agents:`, `todos:`, `tokens:`), aggregate token display in K/M notation, `~$` cost prefix. +12 tests (39 total). Issues: #71, #67, #68.
2. **Phase 2 — Data Pipeline** (feature/statusline-data, 86c6f59): Todo split display (`todos: 3p 7g` with project/global counts via `gh issue list`), session cost persistence to `.session-cost-history` (pipe-delimited, 100-entry cap), lifetime cost annotation (`Σ~$N.NN`). +9 tests (48 total). Issues: #72, #68, #69.

All 5 P0 requirements satisfied (REQ-P0-001 through REQ-P0-005). P1 cost persistence (REQ-P1-001) also delivered. 4 architectural decisions recorded (DEC-SL-LAYOUT-001, DEC-SL-TOKENS-001, DEC-SL-TODOCACHE-001, DEC-SL-COSTPERSIST-001) plus 8 implementation decisions. Issues closed: #67, #68, #69, #71, #72.

### Robust State Management — Summary

Hardened the state management infrastructure with protected file registry, POSIX advisory locks, and monotonic lattice enforcement. 2 of 7 planned phases delivered:

1. **Phase 1 — Registry + Locks** (feature/rsm-phase1): Protected state file registry in core-lib.sh, POSIX advisory locks via flock(), pre-write.sh Gate 0 registry check. #37
2. **Phase 2 — Lattice + Self-check** (feature/rsm-phase2): Monotonic lattice enforcement on proof-status transitions, triple self-validation at session startup. #38

Phases 3-5 (SQLite WAL, unified state directory, state daemon) superseded by the dedicated SQLite Unified State Store initiative (parked). 6 architectural decisions (DEC-RSM-REGISTRY-001 through DEC-RSM-SELFCHECK-001).

### Prompt Purpose Restoration — Summary

Restored purpose-to-enforcement ratio in CLAUDE.md and agent prompts after benchmark findings showed easy-task success dropped from 100% to 67%. Three waves:

1. **W1-1: Shared Protocols** (feature/shared-protocols): Created `agents/shared-protocols.md` (87 lines) with CWD safety, trace protocol, mandatory return message, session-end checklist. Wired injection in `hooks/subagent-start.sh` for all non-lightweight agents. #143
2. **W1-2: CLAUDE.md Restore** (feature/claude-md-restore): Rebuilt CLAUDE.md with purpose-sandwich structure — restored full Cornerstone Belief (8 sentences), added "What Matters" section, identity→purpose→quality→references→procedures flow. #144
3. **W2-1: Slim Agent Prompts** (#146): Targeted 30-40% reduction by removing shared boilerplate from 4 agent prompts. Actual reduction ~4.4% — shared-protocols injection supplements rather than replaces content (DEC-PROMPT-004). Purpose language strengthened in agent openings. Guardian merge presentation added (REQ-P1-004).

W3-1 (validation session) not executed — benchmark improvements validated through ongoing usage. 3 architectural decisions (DEC-PROMPT-001 through 003) plus closure decision (DEC-PROMPT-004). Issues closed: #143, #144, #146.

### Governor Subagent — Summary

Added the 5th agent — the governor — a mechanical feedback mechanism that evaluates initiatives against core intent and trajectory, and meta-evaluates the evaluative infrastructure itself (SESAP applied recursively). Two-tier model: health pulse (~3-5K tokens, quick deviation detection) and full 8-dimension evaluation (~15-20K tokens, initiative boundaries).

1. **W1-1: Agent prompt** (feature/governor-prompt): Created `agents/governor.md` — purpose-led prompt with 4 trigger contexts (health pulse, pre-implementation, post-completion, reckoning-input), 4+4 dimension rubric, read-only constraints. #182
2. **W1-2: SubagentStop hook** (feature/governor-hook): Created `hooks/check-governor.sh` — validates evaluation.json + summary, extracts verdict, Layer A silent return recovery. Advisory only (exit 0 always). #183
3. **W2-1: Dispatch wiring** (feature/governor-wiring): Wired into settings.json, subagent-start.sh (context injection), DISPATCH.md (routing + auto-dispatch), CLAUDE.md (Resources table), task-track.sh (gate exemption). #184
4. **W3-1: Trigger refinement + validation** (feature/governor-validation): Added two-tier evaluation model (DEC-GOV-006), health pulse mode, dispatch frequency guidance, pre-implementation defaults to pulse. Wired mechanical triggers: check-planner.sh advisory for multi-wave plans, session-init.sh pulse staleness surfacing, reckoning SKILL.md Phase 2e governor dispatch. 42 tests. #185

8 decisions (DEC-GOV-001 through DEC-GOV-006, DEC-GOV-HOOK-001, DEC-GOV-WIRE-002/003). Issues closed: #169, #182, #183, #184, #185. Live health pulse validated: verdict=drifting, 3 actionable flags (guardian failure rate, decision bifurcation, trace duplicates).

### Governance Signal Audit — Summary

Produced a comprehensive governance signal map documenting all 24 hook registrations, their context injection volume, timing, frequency, and overlap. One wave delivered:

1. **W1-3: Signal Map** (feature/signal-map): Created `docs/governance-signal-map.md` mapping all hooks by lifecycle event with byte counts, frequencies, and 7 optimization proposals. Total governance signal: ~15KB per session start, ~2KB per tool call. #145

W2-2 (formalize optimization proposals) deemed unnecessary (DEC-RECK-013) — the 7 proposals in the signal map are already actionable. 1 architectural decision (DEC-AUDIT-002) plus closure decision (DEC-RECK-013). Issue closed: #145.

### State Unification — Summary

Replaced four overlapping state management eras (dotfiles, state.json+jq, atomic tmp->mv, shadow SQLite) with SQLite as sole authority. Seven waves over 4 days:

1. **W1-1: Schema + Migration Framework** (feature/su-w1-schema): `_migrations` table, idempotent runner, `BEGIN IMMEDIATE` upgrade. #213
2. **W1-2: Proof State Typed Table** (feature/su-w1-proof-table): `proof_state` table with monotonic lattice, dual-read fallback. #214
3. **W2-1: Hook Migration** (feature/su-w2-proof-migration): 7 hooks migrated from flat-file proof I/O to proof_state API, dual-write preserved. #215
4. **W3-W4: Markers + Events** (merged earlier): `agent_markers` table with PID liveness, `events` + `event_checkpoints` tables with consumer pattern. #216-#218
5. **W5-1/W5-2: Completion** (feature/state-unify-w5-2): Removed all flat-file fallback paths, dual-read window closed, lint enforcement active, legacy code removed. Discovered and fixed critical bugs: epoch reset deadlock (#227 — lattice permanently blocked after first merge), silent error swallowing (#228 — `|| true` hiding sole-authority failures). #219-#220
6. **W6-1: Event Integration** (feature/state-unify-w6-1): Event GC removed per user directive — events are institutional memory, never deleted. Observatory and governor wired as event consumers. #221
7. **KV Migrations** (DEC-STATE-KV-001 through KV-007): Migrated 8 dotfiles to SQLite KV store — orchestrator-sid, session-start-epoch, prompt-count, session-token-history, session-cost-history, test-status, todo-count, agent-findings audit trail. Comprehensive dotfile audit: 16/16 migratable files resolved (4 sole, 8 dual, 2 already-migrated, 2 removed). 15 files classified NOT-APPLICABLE. Session cleanup: lint cooldown removal, stale state file archival.

All 9 P0 requirements satisfied. SQLite is the sole authoritative state store — zero flat-file state I/O. Key bugs fixed: epoch reset (DEC-EPOCH-RESET-001/002), error propagation (DEC-EPOCH-RESET-003), malformed workflow_id cleanup (DEC-EPOCH-RESET-004). Architectural decisions: single DB for all structured data (DEC-STATE-UNIFY-008), no event deletion (DEC-STATE-UNIFY-009), observatory convergence as follow-on (DEC-STATE-UNIFY-010). 17 decisions total (DEC-STATE-UNIFY-001 through 010 + DEC-STATE-KV-001 through 007). Issues closed: #213, #214, #215, #220, #221, #224, #225, #227, #228, #229. Remaining: #223 (state.db file-operation protection gap), #226 (DB-SAFE-A1 heredoc false positive).

### Database Safety Framework — Summary

Implemented defense-in-depth interception preventing AI agents from destroying databases through any interaction vector. Five waves over 4 days:

1. **W1: Internal DB Protection + Framework** (3 parallel): state.db sqlite3 access blocked in pre-bash.sh Check 0, `scripts/state-diag.sh` read-only diagnostics, backup-before-migration in state-lib.sh, modular `_db_check_*()` architecture in `hooks/db-safety-lib.sh`, `@modality database` annotations, extended Check 0 coverage (TRUNCATE without TABLE keyword, DELETE without WHERE). Test fixtures for all deny/allow patterns. #197, #198, #199
2. **W2: Multi-Vector CLI + IaC Interception** (2 parallel): 5 database CLI handlers (psql, mysql, sqlite3, mongosh, redis-cli) with destructive command detection, environment tiering (`_db_detect_env()`: prod/staging/dev/local/unknown), forced safety flags (psql `ON_ERROR_STOP`, mysql `--safe-updates`), migration framework allowlist (12 frameworks), non-interactive TTY fail-safe. IaC handlers (terraform, pulumi, aws cloudformation), container handlers (docker-compose, docker volume, kubectl PVC/PV), ORM detection (sequelize.sync, drop_all). #200, #201
3. **W3: Database Guardian Subagent**: `agents/db-guardian.md` — sole database credential holder with Supervisor-Worker architecture, deterministic policy engine (9 priority-ordered rules), EXPLAIN/ROLLBACK simulation helpers, human approval gate for production DDL, backup verification gate. Dispatch wiring following Governor pattern. #202
4. **W4: MCP Governance Layer**: `hooks/pre-mcp.sh` — PreToolUse hook for `mcp__*` database tools, SQL argument extraction from JSON-RPC payloads, per-tool capability filtering (readonly/write/DDL/admin), SQL injection detection (CVE-2025-53109 semicolon stacking), rate limiting (100 calls/60s). #203
5. **W5: Polish + P1 Items** (2 parallel): state.db integrity check (`PRAGMA integrity_check`), `_PROTECTED_STATE_FILES` registry entry, schema change advisory, connection string redaction, session safety summary, MySQL autocommit DDL warning, HOOKS.md documentation. MCP credential partitioning advisory (once per session), test fixture expansion. #204, #205

All 23 P0 requirements satisfied. 5-layer defense-in-depth operational: nuclear deny (Check 0), CLI-aware detection with environment tiering, IaC/container interception, Database Guardian subagent, MCP governance. 430 tests across 9 test scopes. 18 decisions (DEC-DBSAFE-001 through 006, DEC-DBGUARD-001 through 009, DEC-MCP-001 through 003). Issues closed: #197, #198, #199. P1 items deferred to standalone issues: #210 (D6 transaction wrapping), #211 (D7 pre-modify archiving), #212 (E5 MCP shadowing).

---

## Parked Issues

Issues not belonging to any active initiative. Tracked for future consideration.

| Issue | Description | Reason Parked |
|-------|-------------|---------------|
| #15 | ExitPlanMode spin loop fix | Blocked on upstream claude-code#26651 |
| #14 | PreToolUse updatedInput support | Blocked on upstream claude-code#26506 |
| #13 | Deterministic agent return size cap | Blocked on upstream claude-code#26681 |
| #37 | Close Write-tool loophole for .proof-status bypass | Mitigated — SQLite is sole authority (State Unification); flat-file bypass no longer affects proof gate. File-level state.db protection tracked in #223. |
| #36 | Evaluate Opus for implementer agent | Not in remediation scope |
| #25 | Create unified model provider library | Not in remediation scope |
| SQLite Unified State Store (#128-#134) | SQLite WAL state backend replacing flat-file state. 8 planning decisions (DEC-SQLITE-001 through 008). | **Superseded** — fully completed by State Unification initiative (2026-03-12). Wave 1 API was the foundation; all remaining waves delivered. |
| Operational Mode System (#114-#118) | 4-tier mode taxonomy (Observe/Amend/Patch/Build) with escalation engine and hook integration. 9 planning decisions. Deep-research validated. | Ambitious for current project scale. Revisit when multi-user or multi-project usage patterns emerge. |
| Backlog Auto-Capture (cancelled) | Automatic issue creation from conversation keywords. 5 planning decisions. | Cancelled (DEC-RECK-006): manual /backlog command is sufficient. prompt-submit.sh already auto-detects deferred-work language. |
