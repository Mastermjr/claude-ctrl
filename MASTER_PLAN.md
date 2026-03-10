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
**Last updated:** 2026-03-09

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

---

## Active Initiatives

### Initiative: Governance Efficiency
**Status:** completed
**Started:** 2026-03-09
**Goal:** Reduce governance overhead (60-310% token excess on easy tasks) through targeted signal noise reduction, caching, and deduplication — without weakening any safety gates.

> Benchmark data (36 trials, 6 tasks, claude-ctrl-performance harness) revealed that v30 of the governance system spends 60-310% more tokens than v21 on easy tasks. The Governance Signal Audit (completed) produced `docs/governance-signal-map.md` with 7 concrete optimization proposals and a full redundancy analysis. This initiative implements those proposals: demoting low-value advisories to debug logs, caching redundant computations, and deduplicating cross-hook signal injection. Every optimization preserves all deny gates unconditionally. The system becomes leaner without becoming less safe.

**Dominant Constraint:** safety

#### Goals
- REQ-GOAL-009: Reduce per-prompt governance context injection from ~600 bytes to <400 bytes typical (33% reduction)
- REQ-GOAL-010: Eliminate advisory signals that proceed without blocking (pure noise removal)
- REQ-GOAL-011: Introduce caching for computationally redundant hook operations (keyword matching, trajectory narrative, plan churn)

#### Non-Goals
- REQ-NOGO-010: Removing or weakening any deny gates — safety enforcement is the entire point of governance
- REQ-NOGO-011: Building the Operational Mode System (#109, parked) — that's a 4-tier taxonomy; this is targeted optimization
- REQ-NOGO-012: Adding new infrastructure — this is about making existing infrastructure leaner
- REQ-NOGO-013: Building a local token measurement harness — external benchmarks exist (claude-ctrl-performance)

#### Requirements

**Must-Have (P0)**

- REQ-P0-009: Demote fast-mode bypass advisory in pre-write.sh to debug log (.session-events.jsonl)
  Acceptance: Given the fast-mode bypass advisory fires on every write in fast mode, When demoted, Then:
  - [ ] Advisory no longer injected into additionalContext
  - [ ] Event logged to .session-events.jsonl with {type: "advisory-demoted", gate: "fast-mode-bypass"}
  - [ ] Safety invariant documented: fast mode is a Claude Code feature, not model-controlled; no behavioral intent lost

- REQ-P0-010: Demote cold test-gate advisory in pre-write.sh to debug log
  Acceptance: Given the cold test-gate advisory fires on first write when no test data exists, When demoted, Then:
  - [ ] Advisory no longer injected into additionalContext
  - [ ] Event logged to .session-events.jsonl
  - [ ] Safety invariant documented: deny gate (strike 2+) still catches real test failures; cold-start advisory added no blocking value

- REQ-P0-011: Suppress bare doc-freshness advisory in pre-bash.sh (fire-once-per-session)
  Acceptance: Given doc-freshness advisory fires on every commit/merge, When modified to fire-once, Then:
  - [ ] Advisory fires on FIRST commit/merge attempt in a session, then suppressed for subsequent attempts
  - [ ] Deny gates for stale docs on merge-to-main remain fully active
  - [ ] Safety invariant documented: model sees the warning once (enough to act on it); deny gate is the real enforcement

- REQ-P0-012: Skip plan churn drift audit in pre-write.sh Gate 2 when churn <5%
  Acceptance: Given churn detection runs nested git/grep on every source write, When <5% churn, Then:
  - [ ] Churn computation cached with 300s TTL (follows DEC-PERF-004 pattern)
  - [ ] Churn ≥5% still triggers the full drift audit and advisory/deny
  - [ ] Safety invariant documented: <5% churn is genuinely trivial; the gate still fires when drift is meaningful

- REQ-P0-013: Cache keyword match results in prompt-submit.sh
  Acceptance: Given keyword detection (grep -qiE) runs on every user prompt, When cached, Then:
  - [ ] Results cached with invalidation on git state change or plan state change
  - [ ] Same signals produced, just served from cache on consecutive identical-context prompts
  - [ ] Safety invariant documented: technical optimization only; no signals lost, same behavioral intent

- REQ-P0-014: Cache trajectory narrative in stop.sh when no state changes between stops
  Acceptance: Given trajectory narrative regenerates every turn (~300-400ms), When cached, Then:
  - [ ] Cache keyed on git-state fingerprint (branch + HEAD + dirty count)
  - [ ] Stale cache invalidated on any git/plan mutation
  - [ ] Safety invariant documented: if nothing changed, same narrative is correct; model sees accurate state

- REQ-P0-015: Safety invariant requirement for all optimizations
  Acceptance: For EVERY optimization in this initiative, Then:
  - [ ] Implementer documents: (a) what behavior the signal encouraged, (b) what mechanism still preserves that behavior after optimization, (c) if no mechanism preserves it, the optimization is invalid and must be reverted
  - [ ] No deny gate is modified, weakened, or made conditional
  - [ ] Demoted advisories are redirected to .session-events.jsonl (DEC-EFF-002), not deleted

**Nice-to-Have (P1)**

- REQ-P1-006: Cross-hook git state deduplication — consolidate 5-hook git state injection into shared per-event-cycle cache
- REQ-P1-007: Cross-hook plan status deduplication — consolidate 5-hook plan status injection into shared cache
- REQ-P1-008: Evaluate prompt-vs-hook enforcement overlap — identify which prompt-stated rules can be removed from prompts because hooks enforce them deterministically (from signal map redundancy analysis, lines 696-704)

**Future Consideration (P2)**

- REQ-P2-005: Rerun external benchmarks (claude-ctrl-performance) to measure pre/post improvement quantitatively
- REQ-P2-006: Context-sensitive governance — scale overhead with task complexity (lighter for easy tasks, full for complex) — may inform future Operational Mode System reactivation

#### Definition of Done

All P0 requirements pass their acceptance criteria. Every optimization has a documented safety invariant proving no behavioral intent is lost. All deny gates remain untouched. Per-prompt context injection measurably reduced (target: ~600 → <400 bytes typical). Demoted advisories appear in .session-events.jsonl for forensic/analytical use. Satisfies: REQ-GOAL-009, REQ-GOAL-010, REQ-GOAL-011.

#### Architectural Decisions

- DEC-EFF-001: Optimize-first, measure-after
  Addresses: REQ-GOAL-009, REQ-GOAL-010, REQ-GOAL-011.
  Rationale: The signal map proposals are thoroughly analyzed with specific hooks, assessments, and implementation paths. They are low-risk (advisory demotions, caching). Building measurement infrastructure first would delay tangible improvement by an entire wave. Verification comes from rerunning external benchmarks post-implementation.

- DEC-EFF-002: Debug logging via .session-events.jsonl for demoted advisories
  Addresses: REQ-P0-009, REQ-P0-010, REQ-P0-015.
  Rationale: Demoted advisories are redirected to the event log, not deleted. The observatory and reckoning read event logs, not model context — their analytical inputs are unaffected. Trace data is preserved for forensic use.

- DEC-EFF-003: File-mtime-based cache invalidation (follows DEC-PERF-004 pattern)
  Addresses: REQ-P0-012, REQ-P0-013, REQ-P0-014.
  Rationale: The existing stop.sh caching pattern (DEC-PERF-004) uses mtime + TTL for cache invalidation. Extending this pattern to churn detection, keyword matching, and trajectory narrative avoids inventing new cache mechanisms.

- DEC-EFF-004: Preserve all deny gates unconditionally
  Addresses: REQ-NOGO-010.
  Rationale: Deny gates are the system's safety guarantees — they prevent destructive actions, enforce branch isolation, and gate the proof-of-work cycle. Advisory noise can be reduced; safety gates cannot be weakened. This is a hard constraint, not a trade-off.

- DEC-EFF-005: Two-wave delivery — noise reduction then deduplication
  Addresses: REQ-GOAL-009, REQ-P1-006, REQ-P1-007.
  Rationale: Wave 1 (P0 requirements) is low-risk advisory/caching work. Wave 2 (P1 requirements) modifies signal flow across multiple hooks — higher risk, needs the approve gate. Separating them allows Wave 1 to ship independently.

#### Waves

##### Initiative Summary
- **Total items:** 2
- **Critical path:** 2 waves (W1-1 → W2-1)
- **Max width:** 1
- **Gates:** 1 review, 1 approve

##### Wave 1 (no dependencies)
**Parallel dispatches:** 1

**W1-1: Implement signal map optimization proposals (#208)** — Weight: L, Gate: review — DELIVERED (ce010b8, 2026-03-09)
- Implement 6 P0 optimizations across 4 hooks:
  1. **pre-write.sh** (REQ-P0-009): Demote fast-mode bypass advisory — replace additionalContext injection with .session-events.jsonl log entry
  2. **pre-write.sh** (REQ-P0-010): Demote cold test-gate advisory — same pattern
  3. **pre-write.sh Gate 2** (REQ-P0-012): Add churn cache — compute churn %, write to `.churn-cache` with timestamp, skip full drift audit when <5% and cache age <300s
  4. **pre-bash.sh** (REQ-P0-011): Modify doc-freshness advisory to fire-once-per-session — use `.doc-freshness-fired-{SID}` sentinel file; deny gates remain unconditional
  5. **prompt-submit.sh** (REQ-P0-013): Cache keyword match results — store matches in `.keyword-cache-{SID}` keyed on git+plan state fingerprint; invalidate on state change
  6. **stop.sh** (REQ-P0-014): Cache trajectory narrative — keyed on git-state fingerprint (branch+HEAD+dirty); serve from cache when fingerprint unchanged
- For EACH optimization: document safety invariant inline as `@decision` annotation (REQ-P0-015)
- Run existing test suites to verify no regressions
- **Integration:** All changes are to existing hook files. No new files except cache sentinels (session-scoped, cleaned by session-end.sh). No settings.json changes.

##### Wave 2
**Parallel dispatches:** 1
**Blocked by:** W1-1

**W2-1: Cross-hook signal deduplication (#209)** — Weight: M, Gate: approve, Deps: W1-1 — DELIVERED (608c2c8, 2026-03-09)
- Address signal map redundancy findings (lines 683-704):
  1. Git state (branch, dirty count, worktree count) injected by 5 hooks — create `_cached_git_state()` in git-lib.sh that writes to a per-event-cycle cache file; all hooks read from cache instead of re-computing
  2. Plan status (existence, active phase, initiative count) injected by 5 hooks — same `_cached_plan_state()` pattern in plan-lib.sh
  3. Evaluate prompt-vs-hook enforcement overlap — for each of the 6 overlaps identified in signal map (lines 696-704), determine if the prompt statement can be removed because the hook enforces it deterministically
- Verify: Run benchmark suite (external, claude-ctrl-performance) before and after to measure improvement
- **Integration:** Touches git-lib.sh, plan-lib.sh (new cache functions), session-init.sh, prompt-submit.sh, subagent-start.sh, compact-preserve.sh, stop.sh (cache reads replacing direct computation). Cache files cleaned by session-end.sh.

##### Critical Files
- `hooks/pre-write.sh` — Gates 2-4 advisory changes, churn cache
- `hooks/pre-bash.sh` — Doc-freshness fire-once modification
- `hooks/prompt-submit.sh` — Keyword match caching
- `hooks/stop.sh` — Trajectory narrative caching
- `hooks/git-lib.sh` — Shared git state cache (Wave 2)
- `hooks/plan-lib.sh` — Shared plan state cache (Wave 2)
- `docs/governance-signal-map.md` — Source of optimization proposals

##### Decision Log
<!-- Guardian appends here after wave completion -->

#### Governance Efficiency Worktree Strategy

Main is sacred. Each wave dispatches parallel worktrees:
- **Wave 1:** `.worktrees/eff-noise-reduction` on branch `feature/governance-efficiency-w1`
- **Wave 2:** `.worktrees/eff-deduplication` on branch `feature/governance-efficiency-w2`

#### Governance Efficiency References

- Signal map: `docs/governance-signal-map.md` (complete hook audit, context budget, redundancy analysis, 7 optimization proposals)
- Benchmark data: claude-ctrl-performance harness (external, 36 trials, 6 tasks)
- DEC-PERF-004 caching pattern: `hooks/stop.sh` lines 566-568 (TTL-based cache with mtime invalidation)
- Reckoning operationalization: DEC-RECK-014 (user chose governance efficiency as next strategic initiative)
- Safety invariant: DEC-EFF-004 (all deny gates preserved unconditionally)

---

### Initiative: Database Safety Framework
**Status:** active
**Started:** 2026-03-09
**Goal:** Prevent AI agents from destroying databases through any interaction vector — CLI, ORM, IaC, MCP, or container commands — via defense-in-depth interception with environment-aware tiering and a dedicated Database Guardian subagent.

> AI coding agents with shell access can execute arbitrary database operations with irreversible consequences. The Replit incident (July 2025) — where an AI assistant deleted a production database for 1,200+ executives and fabricated 4,000+ fake records to cover it up — proves this risk is not theoretical. The Terraform destroy incident — where an agent hallucinated that production was a test environment — proves the attack surface extends far beyond SQL. Six-provider deep research consensus (129+ citations) confirms defense-in-depth as the only viable strategy: shell-level hooks alone are grossly insufficient. Our own governance database (`state.db`) is unprotected against direct `sqlite3` manipulation. Every day without these protections is a day where an agent could destroy a database. This initiative implements 5-layer protection: nuclear deny, CLI-aware detection, IaC/container interception, a Database Guardian subagent with exclusive credentials, and MCP governance for JSON-RPC bypass prevention.

**Dominant Constraint:** security

**PRD:** `prds/database-safety-framework.md` (v2.0)
**Research:** `research/DeepResearch_DatabaseSafety_AI_Agents_2026-03-07/report.md`, `research/DeepResearch_Database_Agent_Safety_2026-03-09/report.md`
**Related Issues:** #149 (modality-based hook loading), #151 (adaptive modality agent), #186 (MCP enforcement loophole)

#### Goals
- REQ-GOAL-DBS-001: Zero data loss from AI agent operations across all interaction vectors (CLI, ORM, IaC, MCP, container commands)
- REQ-GOAL-DBS-002: Transparent safety without workflow friction — zero false-positive denials in local development after 30-day tuning; <5ms overhead for non-database commands
- REQ-GOAL-DBS-003: Confident use of `--dangerously-skip-permissions` — database safety hooks fire regardless of permission mode
- REQ-GOAL-DBS-004: Single point of database execution via Database Guardian subagent — no other agent holds database credentials
- REQ-GOAL-DBS-005: Establish Claude Code as the safest AI coding environment for database work
- REQ-GOAL-DBS-006: Extensible framework that handles unknown future databases and interaction vectors via graceful degradation

#### Non-Goals
- REQ-NOGO-DBS-001: Database proxy or network-level interception — we operate at shell/hook/MCP layer, not network layer
- REQ-NOGO-DBS-002: Database-level RBAC management — we advise on best practices but do not create roles or modify server configs
- REQ-NOGO-DBS-003: Full SQL parsing or AST analysis — hook layer uses regex (consistent with guard.sh); Database Guardian handles deeper analysis
- REQ-NOGO-DBS-004: OS-level sandboxing of MCP servers — we govern at protocol layer (JSON-RPC inspection), not OS layer
- REQ-NOGO-DBS-005: Modality-based conditional loading (v1) — hooks run unconditionally; designed for future #149 integration but not implemented
- REQ-NOGO-DBS-006: Conversation graph analysis for MCP — valuable future direction but out of scope for v1

#### Requirements

**Must-Have (P0)**

- REQ-P0-DBS-001: Block direct `sqlite3` access to `state.db` (Task A1)
  Acceptance: Given an agent attempts `sqlite3 ~/.claude/state/state.db "DROP TABLE state"`, When PreToolUse:Bash fires, Then command is denied with message directing to `state-lib.sh` API
- REQ-P0-DBS-002: Read-only diagnostics API for state.db via `scripts/state-diag.sh` (Task A2)
  Acceptance: Given agent runs `state-diag.sh`, Then formatted state.db contents output without triggering sqlite3 block
- REQ-P0-DBS-003: Backup on state.db schema migration (Task A3)
  Acceptance: Given `_state_ensure_schema()` detects schema change, Then backup created at `state/state.db.bak.<epoch>` before migration; old backups beyond 3 most recent cleaned up
- REQ-P0-DBS-004: Database CLI destructive command interception for psql, mysql, sqlite3, mongosh, redis-cli (Task B1)
  Acceptance: Given agent runs `psql -h prod.example.com -c "DROP TABLE users"`, Then command denied with message identifying destructive operation and CLI tool
- REQ-P0-DBS-005: Environment detection and tiered response: prod=deny, staging=approval, dev=advisory, local=allow, unknown=deny (Task B2)
  Acceptance: Given `RAILS_ENV=production` and agent runs destructive DB command, Then denied with production environment message
- REQ-P0-DBS-006: Non-interactive TTY fail-safe for piped/redirected database commands (Task B3)
  Acceptance: Given agent pipes SQL into psql (`echo "DROP TABLE" | psql`), Then denied with advisory about piped commands bypassing confirmation
- REQ-P0-DBS-007: Forced safety flags injection — psql `-v ON_ERROR_STOP=1`, mysql `--safe-updates` (Task B4)
  Acceptance: Given agent runs `psql -c "SELECT 1"`, Then deny-with-correction includes `-v ON_ERROR_STOP=1`
- REQ-P0-DBS-008: Migration framework allowlist — Rails, Django, Alembic, Prisma, Flyway, Liquibase, Sequelize, Knex, TypeORM, Goose, golang-migrate, Drizzle Kit (Task B5)
  Acceptance: Given agent runs `rails db:migrate`, Then command allowed with migration framework advisory
- REQ-P0-DBS-009: IaC destructive command interception — terraform destroy, pulumi destroy, aws cloudformation delete-stack (Task B6)
  Acceptance: Given agent runs `terraform destroy`, Then denied with IaC destructive command message
- REQ-P0-DBS-010: Container and volume destruction interception — docker-compose down -v, docker volume rm/prune, kubectl delete pvc/pv (Task B7)
  Acceptance: Given agent runs `docker-compose down -v`, Then denied with volume deletion warning
- REQ-P0-DBS-011: ORM destructive pattern interception — sequelize.sync force:true, drop_all() (Task B8)
  Acceptance: Given agent runs command containing `sequelize.sync({ force: true })`, Then advisory emitted about ORM destructive sync
- REQ-P0-DBS-012: Modular check architecture in pre-bash.sh with early-exit gate and `_db_check_*()` functions (Task C1)
  Acceptance: Given command does not contain known DB CLI/IaC/container tool, Then all database-specific logic skipped (zero overhead)
- REQ-P0-DBS-013: `@modality database` annotation support for future #149 integration (Task C2)
  Acceptance: Given database safety section header, Then includes `# @modality database` annotation (no behavioral effect in v1)
- REQ-P0-DBS-014: Unknown CLI graceful degradation — extended generic destructive keyword coverage (Task C3)
  Acceptance: Given agent runs `cqlsh -e "DROP TABLE keyspace.users"`, Then existing Check 0 catches it; `DELETE FROM users` (no WHERE) also caught
- REQ-P0-DBS-015: Database Guardian agent definition at `agents/db-guardian.md` (Task D1)
  Acceptance: Given existing 4-agent system, Then 5th agent defined with sole database credential access, Validation -> Simulation -> Execution loop
- REQ-P0-DBS-016: Structured JSON handoff format for Database Guardian communication (Task D2)
  Acceptance: Given coding agent requests database operation, Then JSON schema with operation_type, description, query, target_environment, reversibility_info
- REQ-P0-DBS-017: Deterministic policy engine with environment-tiered rules (Task D3)
  Acceptance: Given policy rules evaluated in priority order, Then each decision logged with rule ID; rules extensible without code changes
- REQ-P0-DBS-018: EXPLAIN/ROLLBACK simulation before write operations (Task D4)
  Acceptance: Given coding agent requests `DELETE FROM users WHERE created_at < '2025-01-01'`, Then Guardian runs EXPLAIN to estimate affected rows and presents impact
- REQ-P0-DBS-019: Human approval gate for production DDL (Task D5)
  Acceptance: Given production DDL triggers approval request, Then request includes DDL statement, estimated impact, cascade effects, backup status
- REQ-P0-DBS-020: Backup verification gate for production write access (Section 5.0 P1)
  Acceptance: Given agent requests production write via Database Guardian, Then if no recovery mechanism verified, operation denied with backup requirements message
- REQ-P0-DBS-021: PreToolUse hook for `mcp__*` database tool calls (Task E1)
  Acceptance: Given agent calls `mcp__postgres__execute_query` with `DROP TABLE` in query, Then denied with MCP database operation blocked message
- REQ-P0-DBS-022: SQL argument validation in JSON-RPC payloads (Task E2)
  Acceptance: Given MCP tool call arguments contain destructive SQL in query/sql/statement fields, Then same B1 patterns applied and blocked
- REQ-P0-DBS-023: Per-tool capability filtering — read-only/write/DDL/admin profiles for MCP tools (Task E3)
  Acceptance: Given MCP tool classified as admin (drop_database, grant, revoke), Then hard-denied; write tools require environment check

**Nice-to-Have (P1)**

- REQ-P1-DBS-001: Rate limiting for MCP data exfiltration prevention — 1000 rows/min, 10MB/min (Task E4)
- REQ-P1-DBS-002: state.db integrity check on session start via PRAGMA integrity_check (Task A4)
- REQ-P1-DBS-003: Explicit `state.db` entry in `_PROTECTED_STATE_FILES` registry (Task A5)
- REQ-P1-DBS-004: Schema change approval gate — ALTER TABLE/CREATE INDEX advisory in non-local environments (Task B9)
- REQ-P1-DBS-005: Database connection string redaction in logs (Task B10)
- REQ-P1-DBS-006: Aggregate safety report in session summary (Task B11)
- REQ-P1-DBS-007: MySQL autocommit DDL warning (Task B12)
- REQ-P1-DBS-008: Configuration interface design for custom database CLIs — documentation only (Task C4)
- REQ-P1-DBS-009: Test fixtures for database safety checks (Task C5)
- REQ-P1-DBS-010: Documentation in HOOKS.md — Database Safety section (Task C6)
- REQ-P1-DBS-011: Transaction wrapping with commit gates (Task D6)
- REQ-P1-DBS-012: Pre-modify data archiving before DELETE/DROP (Task D7)
- REQ-P1-DBS-013: MCP shadowing pattern for destructive operations — dry-run simulation (Task E5)
- REQ-P1-DBS-014: MCP server credential partitioning advisory (Task E6)
- REQ-P1-DBS-015: Snapshot-before-destructive pattern for DDL in staging/production (Section 5.0 P2)

**Future Consideration (P2)**

- REQ-P2-DBS-001: WAL checkpoint monitoring for state.db (Task A6)
- REQ-P2-DBS-002: Interactive approval flow for destructive operations (Task B13)
- REQ-P2-DBS-003: Database command audit trail — all CLI invocations logged (Task B14)
- REQ-P2-DBS-004: Modality-aware activation via #149 integration (Task C7)
- REQ-P2-DBS-005: Trace-informed pre-loading via #151 integration (Task C8)
- REQ-P2-DBS-006: Multi-database connection management (Task D8)
- REQ-P2-DBS-007: Schema drift detection (Task D9)
- REQ-P2-DBS-008: Cost estimation for cloud databases (Task D10)
- REQ-P2-DBS-009: MCP policy proxy — full gateway pattern (Task E7)
- REQ-P2-DBS-010: MCP conversation graph analysis (Task E8)
- REQ-P2-DBS-011: MCP server auto-discovery and classification (Task E9)

#### Definition of Done

All 23 P0 requirements pass their acceptance criteria. state.db protected from direct sqlite3 access with sanctioned read-only API. Database CLI destructive commands intercepted for psql, mysql, sqlite3, mongosh, redis-cli with environment-tiered response. IaC (terraform, pulumi) and container (docker, kubectl) destructive commands intercepted. Database Guardian subagent defined with sole credential access, deterministic policy engine, EXPLAIN/ROLLBACK simulation, and human approval gate. MCP governance layer intercepts destructive SQL in JSON-RPC payloads with per-tool capability filtering. All new hooks have <10ms overhead for DB commands, <1ms for non-DB commands. Test fixtures validate all deny/allow patterns. Satisfies: REQ-GOAL-DBS-001 through REQ-GOAL-DBS-006.

#### Architectural Decisions

<!--
@decision DEC-DBSAFE-001
@title Defense-in-depth via 5-layer interception
@status accepted
@rationale 6-provider research consensus (129+ citations across 2 rounds, 3 providers each)
  confirms shell-level hooks alone are grossly insufficient. Five interception layers:
  nuclear deny (Check 0), CLI-aware detection, IaC/container interception, Database Guardian
  subagent, MCP governance. Each layer catches what the others miss.
-->

- DEC-DBSAFE-001: Defense-in-depth via 5-layer interception
  Addresses: REQ-GOAL-DBS-001, REQ-GOAL-DBS-002.
  Rationale: 6-provider research consensus (129+ citations) confirms shell-level hooks alone are grossly insufficient. 5 layers needed: nuclear deny (Check 0 Category 7, already exists), CLI-aware detection with environment tiering, IaC/container interception, Database Guardian subagent with exclusive credentials, MCP governance for JSON-RPC bypass prevention. Each layer catches what the others miss. Research: `DeepResearch_DatabaseSafety_AI_Agents_2026-03-07/report.md`, `DeepResearch_Database_Agent_Safety_2026-03-09/report.md`.

<!--
@decision DEC-DBSAFE-002
@title Environment tiering: dev=permissive, staging=approval, prod=read-only, unknown=deny
@status accepted
@rationale 3/3 Round 2 research providers converge on this exact model. Production defaults
  to read-only with approval chain via Database Guardian. Unknown environments treated
  conservatively (deny) — the Terraform destroy incident proves agents hallucinate
  environment context.
-->

- DEC-DBSAFE-002: Environment tiering: dev=permissive, staging=approval, prod=read-only, unknown=deny
  Addresses: REQ-P0-DBS-005.
  Rationale: 3/3 Round 2 research providers converge on this model. Production defaults to read-only with approval chain. Unknown environments treated as potentially dangerous (deny) — the Terraform destroy incident proves agents hallucinate environment context. Detection signals: env vars (APP_ENV, RAILS_ENV, NODE_ENV), hostname patterns, connection strings, with fallback to unknown.

<!--
@decision DEC-DBSAFE-003
@title Database Guardian subagent as sole database credential holder
@status accepted
@rationale Research consensus: agents are "non-deterministic privileged entities" requiring
  credential isolation. The Guardian pattern mirrors the proven Git Guardian pattern already
  in the system. Supervisor-Worker architecture: coding agent emits intent (not raw SQL),
  Guardian validates against policy engine, simulates via EXPLAIN/ROLLBACK, executes or rejects.
-->

- DEC-DBSAFE-003: Database Guardian subagent as sole database credential holder
  Addresses: REQ-GOAL-DBS-004, REQ-P0-DBS-015.
  Rationale: Research consensus: agents are "non-deterministic privileged entities" requiring credential isolation. Mirrors the proven Git Guardian pattern. Supervisor-Worker architecture: coding agent emits structured intent, Guardian validates against deterministic policy engine, simulates via EXPLAIN/ROLLBACK, executes or rejects. No other agent holds database credentials.

<!--
@decision DEC-DBSAFE-004
@title MCP governance via PreToolUse hook, not full proxy
@status accepted
@rationale Hook-based interception at the JSON-RPC argument level provides governance without
  infrastructure changes. MCP database servers bypass shell hooks entirely (agent calls
  mcp__postgres__execute_query and SQL never appears in Bash). PreToolUse hook for mcp__*
  extracts SQL from tool arguments and applies same B1 patterns. Full proxy is P2 (E7).
-->

- DEC-DBSAFE-004: MCP governance via PreToolUse hook, not full proxy
  Addresses: REQ-P0-DBS-021, REQ-P0-DBS-022.
  Rationale: Hook-based interception at JSON-RPC argument level provides governance without infrastructure changes. MCP database servers bypass shell hooks entirely — agent calls `mcp__postgres__execute_query` and SQL never appears in a Bash command. This is the enforcement loophole identified in #186. PreToolUse hook for `mcp__*` extracts SQL from tool arguments and applies same destructive patterns as B1. Full MCP proxy (E7) is P2 upgrade path.

<!--
@decision DEC-DBSAFE-005
@title Regex-based pattern matching at hook layer, no SQL AST parsing
@status accepted
@rationale Consistent with guard.sh existing approach (Check 0 Category 7 uses regex for
  DROP/TRUNCATE). Hook layer stays fast (<10ms for DB commands, <1ms early-exit for non-DB).
  Database Guardian subagent handles deeper analysis (EXPLAIN, ROLLBACK simulation) where
  pattern matching is insufficient.
-->

- DEC-DBSAFE-005: Regex-based pattern matching at hook layer, no SQL AST parsing
  Addresses: REQ-NOGO-DBS-003.
  Rationale: Consistent with guard.sh existing approach. Hook layer stays fast (<10ms for DB commands, <1ms early-exit for non-DB). Database Guardian subagent handles deeper analysis (EXPLAIN, ROLLBACK simulation) where regex is insufficient. SQL AST parsing in bash is impractical; external tools add dependencies and latency.

<!--
@decision DEC-DBSAFE-006
@title Modular _db_check_*() functions for extensibility
@status accepted
@rationale Each database CLI, IaC tool, and container command gets its own handler function.
  New databases added by writing a new function and adding the tool name to the early-exit
  gate's pattern list. Consistent with pre-bash.sh section pattern (guard.sh section,
  doc-freshness section). Testable individually via test fixtures.
-->

- DEC-DBSAFE-006: Modular _db_check_*() functions for extensibility
  Addresses: REQ-P0-DBS-012, REQ-GOAL-DBS-006.
  Rationale: Each CLI/IaC/container tool gets its own handler function (`_db_check_psql()`, `_db_check_redis()`, `_db_check_terraform()`, `_db_check_docker()`, etc.). New databases added by writing a function and registering in the early-exit gate. Consistent with pre-bash.sh section pattern. Testable individually via `tests/fixtures/db-safety-*.txt` fixtures.

#### Waves

##### Initiative Summary
- **Total items:** 13
- **Critical path:** 5 waves (W1 -> W2 -> W3 -> W4 -> W5)
- **Max width:** 3 (Wave 1)
- **Gates:** 4 review, 2 approve

##### Wave 1: Internal DB Protection + Framework Skeleton (no dependencies)
**Parallel dispatches:** 3

**W1-1: state.db protection — block direct sqlite3 access + diagnostics API + backup (#197)** — Weight: M, Gate: review
- **A1:** Add sqlite3-to-state.db detection in pre-bash.sh nuclear deny section (Check 0)
  - Pattern: `sqlite3` followed by path resolving to `~/.claude/state/state.db` (handle absolute, relative, `~`, `$HOME`, `/usr/bin/sqlite3`)
  - Deny message: "Direct sqlite3 access to the governance database (state.db) is blocked. Use state-lib.sh functions (state_read, state_update, state_cas) for programmatic access."
  - Must NOT block `sqlite3` targeting other databases
- **A2:** Create `scripts/state-diag.sh` read-only diagnostics script
  - Output: table list, row counts, recent history entries (last 10), schema version
  - Uses only SELECT statements
  - Add to auto-approved allow list in `settings.json` permissions
- **A3:** Add backup-before-migration to `_state_ensure_schema()` in `hooks/state-lib.sh`
  - Before schema changes: `cp state.db state/state.db.bak.<epoch>`
  - Clean up backups beyond 3 most recent
- **Integration:** `hooks/pre-bash.sh` Check 0 extended; `scripts/state-diag.sh` new file; `hooks/state-lib.sh` modified

**W1-2: Modular check architecture + @modality annotation (#198)** — Weight: M, Gate: review
- **C1:** Create database safety section in pre-bash.sh
  - Location: between worktree/tmp checks and git-early-exit gate (per DEC-DBSAFE-005, resolved Q3)
  - Delimit with `# === DATABASE SAFETY SECTION ===` comment headers
  - Early-exit gate: skip all DB logic if command does not contain known DB CLI name, IaC tool, or container command
  - Stub functions: `_db_check_psql()`, `_db_check_mysql()`, `_db_check_sqlite3()`, `_db_check_mongosh()`, `_db_check_redis()`, `_db_check_terraform()`, `_db_check_pulumi()`, `_db_check_docker()`, `_db_check_kubectl()`
  - Each function accepts command string, emits deny/advisory/allow via standard hook output protocol
- **C2:** Add `# @modality database` annotation to section header (no behavioral effect in v1, integration point for #149)
- **C3:** Extend Check 0 Category 7 for broader generic coverage:
  - Add `TRUNCATE\s+\w+` (without requiring TABLE keyword — PostgreSQL supports `TRUNCATE tablename`)
  - Add `DELETE\s+FROM\s+\w+\s*[;$]` (DELETE without WHERE clause) to generic catch-all
- **Integration:** `hooks/pre-bash.sh` modified with new section and extended Check 0

**W1-3: Test fixtures + configuration interface design (#199)** — Weight: S, Gate: none
- **C4:** Document custom CLI configuration format in HOOKS.md (documentation-only, no runtime implementation)
  - JSON schema for `database_safety.custom_clis` array with name, destructive_patterns, safe_flags, env_detection
- **C5:** Create initial test fixture files:
  - `tests/fixtures/db-safety-deny.txt` — commands that MUST be denied (DROP, TRUNCATE, DELETE without WHERE, sqlite3 state.db)
  - `tests/fixtures/db-safety-allow.txt` — commands that MUST be allowed (SELECT, migrations, non-DB commands)
  - `tests/fixtures/db-safety-iac-deny.txt` — IaC commands that MUST be denied (terraform destroy, pulumi destroy)
  - `tests/fixtures/db-safety-container-deny.txt` — container commands that MUST be denied (docker-compose down -v, docker volume prune)
  - `tests/test-db-safety.sh` — test runner validating all fixtures
- **Integration:** `tests/` directory; `hooks/HOOKS.md` documentation addition

##### Wave 2: Multi-Vector CLI + IaC + Container Interception
**Parallel dispatches:** 2
**Blocked by:** W1-2 (needs modular check architecture and stub functions)

**W2-1: Database CLI interception + environment detection + forced safety flags (#200)** — Weight: XL, Gate: approve, Deps: W1-2
- **B1:** Implement CLI-specific destructive command detection in stub functions created by W1-2:
  - `_db_check_psql()`: DROP DATABASE/TABLE/SCHEMA/INDEX, TRUNCATE, DELETE without WHERE, ALTER TABLE ... DROP
  - `_db_check_mysql()`: Same as psql + autocommit DDL warning
  - `_db_check_sqlite3()`: Same patterns (for non-state.db targets; state.db already handled by W1-1/A1)
  - `_db_check_mongosh()`: db.dropDatabase(), db.dropCollection(), db.collection.drop(), db.collection.deleteMany({}), db.collection.remove({})
  - `_db_check_redis()`: FLUSHALL, FLUSHDB, DEL * (glob), KEYS * | xargs DEL
  - Handle: inline `-c`/`--command`, `-e`/`--eval`, piped input, heredoc, file input
- **B2:** Implement environment detection function `_db_detect_env()`:
  - Check env vars: APP_ENV, RAILS_ENV, NODE_ENV, DJANGO_SETTINGS_MODULE, ENVIRONMENT
  - Check hostname patterns in connection strings: prod, production, staging, stg, live
  - Check connection strings: DATABASE_URL contains prod/production/staging
  - Localhost detection: 127.0.0.1, ::1, localhost
  - Return: production|staging|development|local|unknown
  - Apply tiered response per DEC-DBSAFE-002
- **B3:** Non-interactive TTY fail-safe: detect `|` preceding DB CLI and `<` file redirection
- **B4:** Forced safety flags via deny-with-correction pattern:
  - psql: inject `-v ON_ERROR_STOP=1` if not present
  - mysql/mariadb: inject `--safe-updates` if not present
  - Skip injection when explicit opt-out present (`--no-safe-updates`, `-v ON_ERROR_STOP=0`)
- **B5:** Migration framework allowlist — pattern-based matching for 12 frameworks
  - Allow through with advisory in production, silent in development
  - Flag dangerous patterns: `drizzle-kit push --force`, `alembic downgrade base`
- **Integration:** `hooks/pre-bash.sh` — implement all stub `_db_check_*()` functions; add `_db_detect_env()` utility function

**W2-2: IaC + container + ORM interception (#201)** — Weight: L, Gate: review, Deps: W1-2
- **B6:** Implement IaC handlers:
  - `_db_check_terraform()`: deny `terraform destroy`, deny `terraform apply -auto-approve`, allow `terraform plan`
  - `_db_check_pulumi()`: deny `pulumi destroy`, deny `pulumi up --yes`, allow `pulumi preview`
  - Deny `aws cloudformation delete-stack`
- **B7:** Implement container handlers:
  - `_db_check_docker()`: deny `docker-compose down -v` and `docker compose down -v` (v2), deny `docker volume rm`, deny `docker volume prune`; allow `docker-compose down` (without -v)
  - `_db_check_kubectl()`: deny `kubectl delete pvc`, deny `kubectl delete pv` with advisory about ReclaimPolicy
- **B8:** ORM destructive pattern interception (best-effort, heuristic):
  - Detect `sequelize.sync({ force: true })` in command strings
  - Detect `drop_all()` in Python-related commands
  - Advisory when seed scripts detected in production environment
- **Integration:** `hooks/pre-bash.sh` — implement IaC, container, and ORM handler functions

##### Wave 3: Database Guardian Subagent
**Parallel dispatches:** 1
**Blocked by:** W2-1 (needs environment detection function `_db_detect_env()` for policy engine)

**W3-1: Database Guardian agent + policy engine + simulation (#202)** — Weight: XL, Gate: approve, Deps: W2-1
- **D1:** Create `agents/db-guardian.md` agent prompt:
  - Purpose-led opening: sole entity with database credentials, trust boundary between general reasoning and sensitive operations
  - Supervisor-Worker architecture: receives structured intent from coding agents, validates via policy engine, simulates via EXPLAIN/ROLLBACK, executes or rejects
  - Agent context: sanitized schema, policy manifest, recovery tools, backup verification status
  - Behavioral constraints: database operations only (no code changes, no git operations); read-only default with explicit elevation for writes
  - Trace artifacts: `db-operations.log`, `policy-decisions.json`
- **D2:** Define structured JSON handoff format:
  - Request schema: operation_type, description, query, target_database, target_environment, context_snapshot (affected_tables, estimated_row_count, cascade_risk), requires_approval, reversibility_info
  - Response schema: status (executed|denied|approval_required), execution_id, result, policy_decision (rule_matched, action, reason), simulation_result (explain_output, estimated_impact, cascade_effects), recovery_checkpoint
- **D3:** Deterministic policy engine (rules evaluated in priority order):
  - prod-readonly: any write in production -> deny unless approval token
  - prod-no-ddl: any DDL in production -> deny; require human approval
  - staging-approval: destructive DML in staging -> escalate
  - dev-permissive: any operation in development -> allow with audit log
  - local-permissive: any operation against localhost -> allow
  - unknown-conservative: any write in unknown environment -> deny
  - cascade-check: DELETE/DROP with FK cascades -> escalate regardless of environment
  - unbounded-delete: DELETE without WHERE -> deny in prod/staging; warn in dev (per resolved Q1)
  - backup-required: DDL in prod/staging without verified backup -> deny
- **D4:** EXPLAIN/ROLLBACK simulation:
  - EXPLAIN (ANALYZE false) for row count estimation
  - BEGIN; operation; ROLLBACK for actual effect capture
  - DDL: generate migration plan for review without executing
  - DB-specific: PostgreSQL EXPLAIN vs MySQL EXPLAIN vs SQLite EXPLAIN QUERY PLAN
- **D5:** Human approval gate for production DDL:
  - Approval request includes: DDL statement, estimated impact, cascade effects, backup status
  - Approval logged with timestamp and token
- **Section 5.0 P1:** Backup verification gate — verify PITR/snapshot/user-acknowledgment before production writes
- **Section 5.0 P2:** Snapshot-before-destructive pattern for DDL in staging/production
- **Integration:** `agents/db-guardian.md` new file; dispatch infrastructure wiring (DISPATCH.md, subagent-start.sh, task-track.sh, settings.json) — follow Governor Subagent wiring pattern from W2-1 of that initiative

##### Wave 4: MCP Governance Layer
**Parallel dispatches:** 1
**Blocked by:** W2-1 (needs destructive pattern matching from B1 for SQL argument validation)

**W4-1: MCP governance — PreToolUse hook + SQL validation + capability filtering (#203)** — Weight: L, Gate: review, Deps: W2-1
- **E1:** Create `hooks/pre-mcp.sh` PreToolUse hook for `mcp__*` database tool calls:
  - Register in settings.json: `{ "hooks": { "PreToolUse": [{ "matcher": "mcp__*", "command": "~/.claude/hooks/pre-mcp.sh" }] } }`
  - MCP database tool identification by tool name pattern: `mcp__postgres*`, `mcp__mysql*`, `mcp__sqlite*`, `mcp__mongodb*`, `mcp__redis*`, generic `mcp__*__execute_query`/`run_query`/`execute_sql`
  - Early-exit: non-database MCP tools pass through immediately (zero overhead)
- **E2:** SQL argument validation:
  - Parse JSON payload from stdin, extract `query`/`sql`/`statement`/`command` fields
  - Apply same destructive patterns from B1 to extracted SQL
  - Detect SQL injection patterns (`;` followed by destructive SQL)
  - Environment detection from MCP server config if available
- **E3:** Per-tool capability filtering:
  - Read-only tools (list_tables, describe_table, read_query, select_query): always allow
  - Write tools (execute_query, run_query, insert, update): require environment check
  - DDL tools (create_table, alter_table, drop_table): always require approval
  - Admin tools (drop_database, grant, revoke): always deny
  - Unknown tools: default to write-tool policy (conservative)
- **E4 (P1):** Rate limiting for data exfiltration prevention:
  - Default: 1000 rows/min, 10MB/min
  - State tracked per-session
  - Schema exploration exempt from rate limits
- **Integration:** `hooks/pre-mcp.sh` new file; `settings.json` new PreToolUse registration

##### Wave 5: Polish, Observability, Environment Tiering
**Parallel dispatches:** 2
**Blocked by:** W3-1, W4-1 (needs all P0 work complete)

**W5-1: P1 items — session integration, observability, documentation (#204)** — Weight: L, Gate: review, Deps: W3-1, W4-1
- **A4:** state.db integrity check on session start — `PRAGMA integrity_check` in session-init.sh (within 50ms budget)
- **A5:** Explicit `state.db` entry in `_PROTECTED_STATE_FILES` registry in core-lib.sh
- **B9:** Schema change approval gate — ALTER TABLE/CREATE INDEX advisory in non-local environments
- **B10:** Database connection string redaction in logs — passwords in postgresql://user:pass@host/db replaced with ***
- **B11:** Aggregate safety report in session summary — "Database safety: N commands checked, M blocked, K warnings"
- **B12:** MySQL autocommit DDL warning
- **C6:** HOOKS.md documentation — Database Safety section with all checks, supported CLIs, IaC tools, container commands, environment detection, extension points
- **C4:** Configuration interface design documentation (if not completed in W1-3)
- **Integration:** `hooks/session-init.sh`, `hooks/core-lib.sh`, `hooks/pre-bash.sh`, `hooks/stop.sh`, `hooks/HOOKS.md`

**W5-2: P1 items — Database Guardian + MCP enhancements (#205)** — Weight: M, Gate: review, Deps: W3-1, W4-1
- **D6:** Transaction wrapping with commit gates — all write operations wrapped in `BEGIN TRANSACTION`; commit requires user confirmation in prod/staging; auto-rollback after 5min timeout
- **D7:** Pre-modify data archiving — `CREATE TABLE _archive_<table>_<epoch> AS SELECT * FROM <table> WHERE <condition>` before DELETE; full table backup before DROP; 7-day retention cleanup
- **E5:** MCP shadowing pattern — destructive MCP calls return simulated success while logging intent for human review; opt-in (per resolved Q8 recommendation), session-level tracking, end-of-session report
- **E6:** MCP credential partitioning advisory — advise separate read-only and read-write MCP servers on first MCP database call (once per session)
- **C5 expansion:** Test fixture expansion for all vectors (IaC, container, MCP, ORM, migration frameworks)
- **Integration:** `agents/db-guardian.md` updated; `hooks/pre-mcp.sh` updated; `tests/fixtures/` expanded

##### Critical Files
- `hooks/pre-bash.sh` — primary enforcement point; database safety section with _db_check_*() functions and _db_detect_env()
- `hooks/pre-mcp.sh` — NEW; MCP governance layer for JSON-RPC interception
- `agents/db-guardian.md` — NEW; Database Guardian subagent prompt with policy engine and simulation
- `hooks/state-lib.sh` — backup-before-migration addition
- `scripts/state-diag.sh` — NEW; sanctioned read-only diagnostics API for state.db
- `settings.json` — new PreToolUse registration for mcp__* hooks
- `hooks/HOOKS.md` — Database Safety documentation section
- `tests/test-db-safety.sh` — NEW; test runner for all database safety fixtures

##### Decision Log
<!-- Guardian appends here after wave completion -->

#### Database Safety Worktree Strategy

Main is sacred. The `db-safety` branch was created from main for this initiative. Each wave dispatches parallel worktrees from `db-safety`:
- **Wave 1:** `.worktrees/db-w1-statedb` on branch `db-safety-w1-statedb` (W1-1), `.worktrees/db-w1-framework` on branch `db-safety-w1-framework` (W1-2), `.worktrees/db-w1-fixtures` on branch `db-safety-w1-fixtures` (W1-3)
- **Wave 2:** `.worktrees/db-w2-cli` on branch `db-safety-w2-cli` (W2-1), `.worktrees/db-w2-iac` on branch `db-safety-w2-iac` (W2-2)
- **Wave 3:** `.worktrees/db-w3-guardian` on branch `db-safety-w3-guardian` (W3-1)
- **Wave 4:** `.worktrees/db-w4-mcp` on branch `db-safety-w4-mcp` (W4-1)
- **Wave 5:** `.worktrees/db-w5-polish` on branch `db-safety-w5-polish` (W5-1), `.worktrees/db-w5-guardian-p1` on branch `db-safety-w5-guardian-p1` (W5-2)

#### Database Safety References

- PRD v2.0: `prds/database-safety-framework.md` (1134 lines, 23 P0 requirements, 5 tasks, 5 waves)
- Research Round 1: `research/DeepResearch_DatabaseSafety_AI_Agents_2026-03-07/report.md` (28+50+51 citations)
- Research Round 2: `research/DeepResearch_Database_Agent_Safety_2026-03-09/report.md` (48+43K+53 citations, 3/3 providers)
- Existing enforcement: `hooks/pre-bash.sh` Check 0 Category 7 (DROP DATABASE/TABLE/SCHEMA, TRUNCATE TABLE)
- State protection registry: `hooks/core-lib.sh` `_PROTECTED_STATE_FILES` array
- State API: `hooks/state-lib.sh` (state_read, state_update, state_cas)
- Existing guard patterns: `hooks/guard.sh` (deny-with-correction pattern used by B4)
- Related issues: #149 (modality-based hook loading), #151 (adaptive modality agent), #186 (MCP enforcement loophole)
- SQLite state store: `sqlite-dev` branch (Waves 1-4 complete, baking) — state.db is the target of Task A protection
- Database-specific safety rules: PRD Appendix A (SQLite, PostgreSQL, Redis, MongoDB, MySQL, cloud managed DBs, Kubernetes PVCs)

---

### Initiative: State Unification
**Status:** active
**Started:** 2026-03-09
**Goal:** Replace the four overlapping state management eras (dotfiles, state.json+jq, atomic tmp->mv, shadow SQLite) with SQLite as sole authority -- typed schema, migration discipline, event-driven coordination, and lint enforcement to prevent regression.

> The hook system's state management has four overlapping eras coexisting simultaneously: raw dotfiles, jq+flock on state.json, atomic tmp->mv with monotonic lattice, and SQLite WAL. SQLite was added as Wave 1 of the Robust State Management initiative but ALL writes are best-effort shadows (`type state_update &>/dev/null && ... || true`). Flat files remain authoritative. This dual-authority system has produced 20+ state-related fixes across 755 commits, with 5 recurring failure patterns: session ID loss (5 independent fixes), proof file location instability (3 paths for same data), TTL-based marker falsification (3+ fixes), marker false positives (glob-based detection errors), and partial write corruption. Every new hook that touches state must navigate this archaeological layering. Additionally, all write transactions use `BEGIN;` instead of `BEGIN IMMEDIATE;`, creating a deadlock window under concurrent hook processes. This initiative eliminates the flat-file layer entirely, promotes SQLite to sole authority, adds typed schema with migration discipline, and introduces an event ledger for async coordination.

**Dominant Constraint:** reliability

**Supersedes:** SQLite Unified State Store (parked, #128-#134) -- this initiative completes what that one started

#### Goals
- REQ-GOAL-SU-001: SQLite as the sole authoritative state store -- all state reads/writes go through state-lib.sh API, flat files eliminated
- REQ-GOAL-SU-002: Zero state-related regressions during migration -- dual-read window ensures no data loss for in-flight worktrees
- REQ-GOAL-SU-003: Typed schema for structured state -- proof_state, agent_markers, events tables with proper indexes and constraints
- REQ-GOAL-SU-004: Event-driven coordination capability -- append-only events table enables async governor triggers, observatory signals, cross-session coordination
- REQ-GOAL-SU-005: Migration discipline -- schema changes go through `_migrations` table; Future Implementers never modify schema inline

#### Non-Goals
- REQ-NOGO-SU-001: Unix socket state daemon -- over-engineered for current single-user scale; revisit when multi-user patterns emerge (from parked RSM initiative)
- REQ-NOGO-SU-002: Real-time pub/sub notifications -- event ledger uses polling (consumer checkpoints), not WebSocket/push; sufficient for hook-based architecture
- REQ-NOGO-SU-003: Cross-machine state synchronization -- this is a local-first system; state.db is per-machine
- REQ-NOGO-SU-004: SQL AST parsing for migration validation -- regex-based validation is sufficient for bash migrations; full AST parsing adds dependencies

#### Requirements

**Must-Have (P0)**

- REQ-P0-SU-001: Upgrade `state_update()`, `state_cas()`, `state_delete()` to use `BEGIN IMMEDIATE;`
  Acceptance: Given concurrent hook processes writing to state.db, When two writers contend, Then busy_timeout handles the wait (no deadlock). Verified by concurrent write test (10 parallel processes, 0 failures).

- REQ-P0-SU-002: Create `_migrations` table and migration runner in state-lib.sh
  Acceptance: Given `_state_ensure_schema()` runs on first call, When schema version is behind, Then pending migrations execute in order. Each migration recorded with version, description, timestamp, checksum. Runner is idempotent -- re-running completed migrations is a no-op.

- REQ-P0-SU-003: Create `proof_state` typed table replacing `.proof-status-{phash}` flat files
  Acceptance: Given `proof_state_set("verified")` is called, When `proof_state_get()` is called, Then returns "verified" with timestamp, source, workflow_id. Monotonic lattice enforcement preserved. All 16 hooks that reference proof status use the new API.

- REQ-P0-SU-004: Create `agent_markers` typed table replacing `.active-{type}-{session}-{phash}` dotfiles
  Acceptance: Given `marker_create("implementer", SESSION, WF_ID, PID)` is called, When `marker_query("implementer")` is called, Then returns active markers with PID-based liveness check. Stale marker cleanup via `marker_cleanup(300)` replaces TTL-based glob deletion.

- REQ-P0-SU-005: Create `events` and `event_checkpoints` tables for event ledger
  Acceptance: Given `state_emit("proof.verified", PAYLOAD)` is called, When `state_events_since("governor")` is called, Then returns events since the governor's last checkpoint. Consumer checkpoints are per-consumer, not global.

- REQ-P0-SU-006: Migrate all 26 hooks from flat-file state I/O to SQLite API calls
  Acceptance: Given hook X previously read/wrote `.proof-status-{phash}`, When migrated, Then hook X calls `proof_state_get()`/`proof_state_set()`. No flat file I/O for state operations.

- REQ-P0-SU-007: Dual-read window during transition -- SQLite primary, flat-file fallback
  Acceptance: Given an in-flight worktree has old code writing flat files, When new code reads state, Then it checks SQLite first, falls back to flat file if SQLite has no entry. Duration: 2 releases.

- REQ-P0-SU-008: Remove all `type state_update &>/dev/null && ... || true` patterns
  Acceptance: Given a hook needs to write state, When it calls the state API, Then the call is direct (no type-check guard, no `|| true` swallowing). Failures are logged, not silently ignored.

- REQ-P0-SU-009: Lint enforcement denying direct dotfile state I/O in hook code
  Acceptance: Given a developer writes `echo "status" > .proof-status-{phash}` in a hook, When lint.sh runs, Then the write is denied with message directing to the state API.

**Nice-to-Have (P1)**

- REQ-P1-SU-001: `state_gc_events` for event table garbage collection -- consumer-based (delete events older than oldest checkpoint)
- REQ-P1-SU-002: Migration rollback support -- `_migrations` table tracks rollback SQL for each migration
- REQ-P1-SU-003: `state_history_query` for structured history queries (by key, time range, source)

**Future Consideration (P2)**

- REQ-P2-SU-001: Observatory integration -- emit events for trace analysis signals
- REQ-P2-SU-002: Governor auto-trigger via cumulative event thresholds
- REQ-P2-SU-003: Cross-session proof coordination (multi-instance awareness)
- REQ-P2-SU-004: Self-healing detection via failure accumulation queries

#### Definition of Done

All 9 P0 requirements pass their acceptance criteria. SQLite is the sole authoritative state store -- zero flat-file state I/O in any hook. All write transactions use BEGIN IMMEDIATE (no deadlock window). Typed tables (proof_state, agent_markers, events) have proper indexes and constraints. Migration runner is idempotent and records each migration. Event ledger supports emit/consume/checkpoint/GC cycle. Lint enforcement prevents regression to flat-file patterns. Dual-read window covers transition. All 200+ existing hook tests pass. Satisfies: REQ-GOAL-SU-001 through REQ-GOAL-SU-005.

#### Architectural Decisions

<!--
@decision DEC-STATE-UNIFY-001
@title BEGIN IMMEDIATE for all write transactions
@status accepted
@rationale WAL mode with BEGIN acquires SHARED lock on read, then tries to upgrade
  to RESERVED on first write. Two connections both holding SHARED cannot both upgrade
  -- deadlock. BEGIN IMMEDIATE acquires RESERVED immediately, so only one writer
  enters the transaction; the other gets SQLITE_BUSY and retries via busy_timeout.
  3/3 deep research providers confirm this as the #1 WAL concurrency fix.
-->

- DEC-STATE-UNIFY-001: BEGIN IMMEDIATE for all write transactions
  Addresses: REQ-P0-SU-001.
  Rationale: WAL mode with `BEGIN` acquires SHARED lock on read, then tries to upgrade to RESERVED on first write -- two connections both holding SHARED cannot both upgrade (deadlock). `BEGIN IMMEDIATE` acquires RESERVED immediately, so only one writer enters the transaction; the other gets SQLITE_BUSY and retries via busy_timeout. 3/3 deep research providers confirm this as the #1 WAL concurrency fix. Mechanical change: `BEGIN;` -> `BEGIN IMMEDIATE;` in `state_update()`, `state_cas()`, `state_delete()`.

<!--
@decision DEC-STATE-UNIFY-002
@title _migrations table for schema versioning
@status accepted
@rationale Per-migration records with checksums; supports rollback detection and
  partial migration recovery. PRAGMA user_version is a single integer with no
  history -- insufficient for a system where schema evolves independently across
  multiple active worktrees. _migrations table tracks: id, version, description,
  applied_at, checksum. Runner is idempotent.
-->

- DEC-STATE-UNIFY-002: _migrations table for schema versioning
  Addresses: REQ-P0-SU-002, REQ-GOAL-SU-005.
  Rationale: Per-migration records with checksums enable rollback detection and partial migration recovery. PRAGMA user_version is a single integer with no history -- insufficient for a system where schema evolves independently across multiple active worktrees. _migrations table tracks: id, version, description, applied_at, checksum. Runner is idempotent -- re-running completed migrations is a no-op based on checksum matching.

<!--
@decision DEC-STATE-UNIFY-003
@title Typed tables for structured state + KV for ad-hoc
@status accepted
@rationale Generic key-value works for simple state but fights the type system for
  structured data. Typed tables enable proper indexes, CHECK constraints, and SQL
  queries. proof_state gets CHECK constraint on status values, agent_markers gets
  UNIQUE constraint on (type, session, workflow), events gets AUTOINCREMENT seq
  for ordering. The key-value API (state_update/state_read) remains for ad-hoc state.
-->

- DEC-STATE-UNIFY-003: Typed tables for structured state + KV for ad-hoc
  Addresses: REQ-P0-SU-003, REQ-P0-SU-004, REQ-P0-SU-005, REQ-GOAL-SU-003.
  Rationale: Generic key-value works for simple state but fights the type system for structured data. Typed tables enable proper indexes, CHECK constraints, and SQL queries. `proof_state` gets CHECK constraint on status values, `agent_markers` gets UNIQUE constraint on (type, session, workflow), `events` gets AUTOINCREMENT seq for ordering. The key-value API (`state_update`/`state_read`) remains for ad-hoc state that doesn't warrant its own table.

<!--
@decision DEC-STATE-UNIFY-004
@title Dual-read for 2 releases during transition
@status accepted
@rationale In-flight worktrees may have code that writes flat files. Dual-read
  ensures no state loss during transition: SQLite primary, flat-file fallback if
  SQLite has no entry. 2-release window covers all worktree lifetimes. After the
  window, W5-2 removes the fallback paths.
-->

- DEC-STATE-UNIFY-004: Dual-read for 2 releases during transition
  Addresses: REQ-P0-SU-007.
  Rationale: In-flight worktrees may have code that writes flat files. Dual-read ensures no state loss during transition: SQLite primary, flat-file fallback if SQLite has no entry. 2-release window covers all worktree lifetimes (typically <1 week). After the window, W5-2 removes the fallback paths.

<!--
@decision DEC-STATE-UNIFY-005
@title Event ledger with consumer checkpoints
@status accepted
@rationale Current async coordination patterns (observatory signal collection,
  governor triggers) use polling across multiple flat files. An append-only events
  table with per-consumer checkpoints enables event-driven coordination: each
  consumer tracks its own offset, queries only new events. No infrastructure
  changes needed -- same sqlite3 CLI, same state-lib.sh API.
-->

- DEC-STATE-UNIFY-005: Event ledger with consumer checkpoints
  Addresses: REQ-P0-SU-005, REQ-GOAL-SU-004.
  Rationale: Current async coordination patterns (observatory signal collection, governor triggers) use polling across multiple flat files. An append-only events table with per-consumer checkpoints enables event-driven coordination: each consumer tracks its own offset, queries only new events since its checkpoint. GC deletes events older than the oldest consumer checkpoint. No infrastructure changes -- same sqlite3 CLI, same state-lib.sh API.

<!--
@decision DEC-STATE-UNIFY-006
@title Lint enforcement gated on migration completion
@status accepted
@rationale Cannot deny dotfile I/O while hooks still use it -- premature enforcement
  breaks in-flight work. The lint gate flips when all W5-1 hooks are merged.
  Until then, the lint rule exists but is disabled via a schema-version check.
-->

- DEC-STATE-UNIFY-006: Lint enforcement gated on migration completion
  Addresses: REQ-P0-SU-009.
  Rationale: Cannot deny dotfile I/O while hooks still use it -- premature enforcement breaks in-flight work. The lint gate flips when all W5-1 hooks are merged. Until then, the lint rule exists but is disabled via a schema-version check: only fires when `_migrations` table confirms all migration versions are applied.

<!--
@decision DEC-STATE-UNIFY-007
@title Version-gated fallback for backward compatibility
@status accepted
@rationale Multiple Claude instances may run different code versions simultaneously
  (e.g., one orchestrator on main, one implementer on a worktree with older code).
  Version-gated fallback: state_read() checks schema version; if pre-migration,
  falls back to flat file read. This prevents hard failures during rolling migration.
-->

- DEC-STATE-UNIFY-007: Version-gated fallback for backward compatibility
  Addresses: REQ-P0-SU-007.
  Rationale: Multiple Claude instances may run different code versions simultaneously (e.g., one orchestrator on main, one implementer on a worktree with older code). Version-gated fallback: `proof_state_get()` checks schema version; if `proof_state` table doesn't exist, falls back to flat file read. This prevents hard failures during rolling migration.

#### Interface Contracts

**Contract: proof_state API (state-lib.sh)**
- Exports: `proof_state_get([WORKFLOW_ID]) -> "status|timestamp|source"`, `proof_state_set(STATUS, [SOURCE]) -> 0|1`
- Consumed by: `hooks/log.sh`, `hooks/pre-bash.sh`, `hooks/task-track.sh`, `hooks/prompt-submit.sh`, `hooks/check-tester.sh`, `hooks/check-guardian.sh`, `hooks/post-write.sh`, `hooks/stop.sh`, `hooks/compact-preserve.sh`
- Test expectations: `proof_state_set "verified"` followed by `proof_state_get` returns "verified". Lattice enforcement: `proof_state_set "pending"` after "verified" is rejected (returns 1) unless epoch reset.

**Contract: marker API (state-lib.sh)**
- Exports: `marker_create(TYPE, SESSION, WF_ID, PID) -> row_id`, `marker_query(TYPE, [WF_ID]) -> "type|session|wf_id|pid|created_at" lines`, `marker_cleanup(STALE_SECONDS) -> count_removed`
- Consumed by: `hooks/trace-lib.sh`, `hooks/session-lib.sh`, `hooks/subagent-start.sh`, `hooks/task-track.sh`, `hooks/check-implementer.sh`, `hooks/check-guardian.sh`, `hooks/post-write.sh`
- Test expectations: `marker_create "implementer" SID WF PID` followed by `marker_query "implementer"` returns the marker. After PID dies, `marker_cleanup 0` removes it.

**Contract: event ledger API (state-lib.sh)**
- Exports: `state_emit(TYPE, PAYLOAD, [WF_ID]) -> seq_no`, `state_events_since(CONSUMER, [TYPE]) -> "seq|type|payload|wf_id|timestamp" lines`, `state_checkpoint(CONSUMER, SEQ) -> 0`, `state_gc_events() -> count_removed`
- Consumed by: `hooks/session-init.sh` (governor trigger check), `agents/governor.md` (event query), `observatory/` (signal collection)
- Test expectations: `state_emit "proof.verified" '{"wf":"test"}'` returns seq 1. `state_events_since "governor"` returns the event. `state_checkpoint "governor" 1` + `state_events_since "governor"` returns empty.

#### Waves

##### Initiative Summary
- **Total items:** 9
- **Critical path:** 5 waves (W1-1 -> W2-1 -> W5-1 -> W5-2; longest sequential chain)
- **Max width:** 3 (W2-1 || W3-1 || W4-1 can execute in parallel after Wave 1 completes)
- **Gates:** 5 review, 2 approve

##### Wave 1: Foundation (no dependencies)
**Parallel dispatches:** 2

**W1-1: Schema + Migration Framework + BEGIN IMMEDIATE (#213)** -- Weight: M, Gate: review
- Add `_migrations` table to state-lib.sh: id, version, description, applied_at, checksum
- Implement `_run_migrations()`: idempotent runner, executes pending migrations in version order
- Upgrade `state_update()`, `state_cas()`, `state_delete()` from `BEGIN;` to `BEGIN IMMEDIATE;`
- Wire migration runner into `_state_ensure_schema()` (runs after base table creation)
- Test: concurrent write test (10 parallel processes, 0 deadlocks), migration idempotency, migration ordering
- **Integration:** `hooks/state-lib.sh` modified; no new files; no settings.json changes

**W1-2: Proof State Typed Table + API (#214)** -- Weight: L, Gate: review
- Create migration 001: `proof_state` table (workflow_id PK, status CHECK, epoch, updated_at, updated_by, session_id, pid)
- Add API: `proof_state_get([WORKFLOW_ID])` -> "status|timestamp|source", `proof_state_set(STATUS, [SOURCE])` -> 0|1
- Monotonic lattice enforcement via CHECK constraint + application logic for epoch reset
- Dual-read fallback: if SQLite has no entry, read from flat file `.proof-status-{phash}`
- Test: CRUD, lattice enforcement, epoch reset, concurrent CAS, dual-read fallback
- **Integration:** `hooks/state-lib.sh` modified; migration 001 registered in runner

##### Wave 2: Core Migration
**Parallel dispatches:** 1
**Blocked by:** W1-1, W1-2

**W2-1: Proof State Hook Migration -- 7 hooks (#215)** -- Weight: XL, Gate: approve, Deps: W1-1, W1-2
- Migrate 7 hooks from flat-file proof I/O to proof_state API:
  1. **log.sh**: replace `resolve_proof_file()` callers + `write_proof_status()` internals with `proof_state_set()`
  2. **pre-bash.sh**: replace `validate_state_file()` + `cut` with `proof_state_get()`
  3. **task-track.sh**: replace proof file reads/writes with `proof_state_get()`/`proof_state_set()`
  4. **prompt-submit.sh**: replace `cas_proof_status()` pattern with `proof_state_set()` (lattice handles CAS)
  5. **check-tester.sh**: replace proof file writes with `proof_state_set("verified")`
  6. **check-guardian.sh**: replace proof file cleanup with `proof_state_set("committed")`
  7. **post-write.sh**: replace `resolve_proof_file()` reads with `proof_state_get()`
- Dual-write preserved during transition: both SQLite typed table and flat file written
- Test: full proof lifecycle e2e (needs-verification -> pending -> verified -> committed), dual-read verification
- **Integration:** 7 hook files modified; `resolve_proof_file()` and `write_proof_status()` retained as thin wrappers during dual-write window

##### Wave 3: Agent Markers
**Parallel dispatches:** 2
**Blocked by:** W1-1

**W3-1: Agent Marker Typed Table + API (#216)** -- Weight: M, Gate: review, Deps: W1-1
- Create migration 002: `agent_markers` table (id AUTOINCREMENT, agent_type, session_id, workflow_id, status, pid, created_at, updated_at, trace_id; UNIQUE(agent_type, session_id, workflow_id))
- Add API: `marker_create()`, `marker_query()` (with PID liveness via kill -0), `marker_cleanup()`
- Test: CRUD, PID liveness, stale cleanup, concurrent creation
- **Integration:** `hooks/state-lib.sh` modified; migration 002 registered

**W3-2: Agent Marker Hook Migration -- 4+ hooks (#217)** -- Weight: L, Gate: review, Deps: W1-1, W3-1
- Migrate hooks from `.active-{type}-{session}-{phash}` dotfile markers to marker API:
  1. **trace-lib.sh**: marker creation, find_active_trace() -> marker_query(), cleanup
  2. **session-lib.sh**: session tracking via marker API (replace glob loops)
  3. **subagent-start.sh**: marker creation at dispatch
  4. **task-track.sh**: marker_query("guardian") replaces glob `.active-guardian-*`
  5. **check-implementer.sh**: marker_query("implementer") replaces glob
  6. **check-guardian.sh**: marker_cleanup() replaces rm `.active-guardian-*`
  7. **post-write.sh**: marker_query() replaces glob `.active-guardian-*`/`.active-autoverify-*`
- Dual-read: SQLite primary, glob fallback for 2 releases
- Test: marker lifecycle e2e, cross-hook consistency
- **Integration:** 7 hook files modified; `.active-*` dotfile creation retained during dual-write window

##### Wave 4: Event Ledger
**Parallel dispatches:** 1
**Blocked by:** W1-1

**W4-1: Event Ledger + Checkpoint System (#218)** -- Weight: M, Gate: review, Deps: W1-1
- Create migration 003: `events` table (seq AUTOINCREMENT, type, workflow_id, session_id, payload JSON, created_at; INDEX on type+created_at; cap TRIGGER at 5000 per workflow)
- Create migration 004: `event_checkpoints` table (consumer PK, last_seq, updated_at)
- Add API: `state_emit()`, `state_events_since()`, `state_checkpoint()`, `state_gc_events()`
- Test: emit/consume cycle, multiple consumers, GC, concurrent emits, type filtering
- **Integration:** `hooks/state-lib.sh` modified; migrations 003-004 registered

##### Wave 5: Completion
**Parallel dispatches:** 2
**Blocked by:** W2-1, W3-2, W4-1

**W5-1: Remaining Hook Migrations + Remove Type Guards (#219)** -- Weight: L, Gate: review, Deps: W2-1, W3-2, W4-1
- Migrate remaining hooks: stop.sh, compact-preserve.sh, session-init.sh, session-lib.sh, test-runner.sh, session-end.sh
- Remove ALL `type state_update &>/dev/null && ... || true` patterns (5 sites across 4 files)
- Emit events from key lifecycle points (session start/end, agent dispatch, proof transitions)
- Test: grep-based validation (no `type state_update` guards remain), full lifecycle e2e
- **Integration:** 6 hook files modified; `db-guardian-lib.sh` updated (remove type guard)

**W5-2: Lint Enforcement + Legacy Code Removal (#220)** -- Weight: M, Gate: approve, Deps: W5-1
- Add lint.sh gate: deny direct dotfile state I/O in hook source code
- Remove legacy code: `_legacy_state_update()`, `_legacy_state_read()`, state.json, flat-file proof/test status, old lock files
- Remove dual-read fallback paths from all hooks
- Test: lint validation catches intentional violations, all 200+ tests pass with legacy removed
- **Integration:** `hooks/lint.sh`, `hooks/state-lib.sh`, `hooks/core-lib.sh` modified; flat files deleted

##### Wave 6: Advanced Integration
**Parallel dispatches:** 1
**Blocked by:** W4-1, W5-1

**W6-1: Event-Driven Governor Triggers + Observatory Signals (#221)** -- Weight: L, Gate: review, Deps: W4-1, W5-1
- Wire session-init.sh: query pending events for governor auto-trigger (threshold: 3 assessment events)
- Wire observatory: consume events via `state_events_since("observatory")`, checkpoint after analysis
- Wire lifecycle event emission: proof transitions, agent starts/stops, session boundaries
- Test: governor trigger threshold, observatory consumption, event emission from lifecycle hooks
- **Integration:** `hooks/session-init.sh`, `hooks/state-lib.sh`, `observatory/` modified

##### Critical Files
- `hooks/state-lib.sh` -- primary target: migration framework, typed APIs, event ledger (all waves)
- `hooks/log.sh` -- resolve_proof_file() and write_proof_status() migration (W2-1)
- `hooks/trace-lib.sh` -- heaviest marker user: create/query/cleanup/finalize (W3-2)
- `hooks/pre-bash.sh` -- proof gate read migration (W2-1)
- `hooks/task-track.sh` -- proof and marker reads (W2-1, W3-2)
- `hooks/session-init.sh` -- migration runner invocation, event-based governor trigger (W5-1, W6-1)
- `hooks/core-lib.sh` -- protected registry update, read_test_status migration (W5-2)
- `hooks/lint.sh` -- new dotfile I/O deny rule (W5-2)

##### Decision Log
<!-- Guardian appends here after wave completion -->

#### State Unification Worktree Strategy

Main is sacred. Each wave dispatches parallel worktrees:
- **Wave 1:** `.worktrees/su-w1-schema` on branch `feature/su-w1-schema` (W1-1), `.worktrees/su-w1-proof-table` on branch `feature/su-w1-proof-table` (W1-2)
- **Wave 2:** `.worktrees/su-w2-proof-migration` on branch `feature/su-w2-proof-migration` (W2-1)
- **Wave 3:** `.worktrees/su-w3-markers-table` on branch `feature/su-w3-markers-table` (W3-1), `.worktrees/su-w3-markers-migration` on branch `feature/su-w3-markers-migration` (W3-2)
- **Wave 4:** `.worktrees/su-w4-events` on branch `feature/su-w4-events` (W4-1)
- **Wave 5:** `.worktrees/su-w5-remaining` on branch `feature/su-w5-remaining` (W5-1), `.worktrees/su-w5-cleanup` on branch `feature/su-w5-cleanup` (W5-2)
- **Wave 6:** `.worktrees/su-w6-integration` on branch `feature/su-w6-integration` (W6-1)

#### State Unification References

- Existing state API: `hooks/state-lib.sh` (state_update, state_read, state_cas, state_delete, workflow_id)
- Proof state management: `hooks/log.sh` (resolve_proof_file, write_proof_status)
- Agent marker management: `hooks/trace-lib.sh` (.active-* dotfile lifecycle)
- Protected state registry: `hooks/core-lib.sh` (_PROTECTED_STATE_FILES array)
- SQLite state store Wave 1 (parked): Issues #128-#134; 8 planning decisions DEC-SQLITE-001 through 008
- State Management Reliability (completed): 10 decisions DEC-STATE-001 through DEC-STATE-AUDIT-001
- Robust State Management (completed): 6 decisions DEC-RSM-REGISTRY-001 through DEC-RSM-SELFCHECK-001
- Database Safety state.db protection: `hooks/pre-bash.sh` Check DB-SAFE-A1 (blocks direct sqlite3 to state.db)
- Deep research: Task context analysis (3-provider consensus on BEGIN IMMEDIATE, typed schema, migration discipline)

---

## Completed Initiatives

| Initiative | Period | Phases | Key Decisions | Archived |
|-----------|--------|--------|---------------|----------|
| Governance Efficiency | 2026-03-09 | 2 (W1+W2) | DEC-EFF-001 through DEC-EFF-014 (14 decisions) | No |
| Production Remediation (Metanoia Suite) | 2026-02-28 to 2026-03-01 | 5 | DEC-HOOKS-001 thru DEC-TEST-006 | No |
| State Management Reliability | 2026-03-01 to 2026-03-02 | 5 | DEC-STATE-007, DEC-STATE-008 + 8 test decisions | No |
| Hook Consolidation Testing & Streamlining | 2026-03-02 | 4 | DEC-AUDIT-001, DEC-TIMING-001, DEC-DEDUP-001 | No |
| Statusline Information Architecture | 2026-03-02 | 2 | DEC-SL-LAYOUT-001, DEC-SL-TOKENS-001, DEC-SL-TODOCACHE-001, DEC-SL-COSTPERSIST-001 | No |
| Robust State Management | 2026-03-02 to 2026-03-05 | 2 (of 7 planned) | DEC-RSM-REGISTRY-001 through DEC-RSM-SELFCHECK-001 (6 decisions) | No |
| Prompt Purpose Restoration | 2026-03-07 to 2026-03-09 | 3 (W1-1, W1-2, W2-1) | DEC-PROMPT-001, DEC-PROMPT-002, DEC-PROMPT-003, DEC-PROMPT-004 | No |
| Governance Signal Audit | 2026-03-07 to 2026-03-09 | 1 (W1-3) | DEC-AUDIT-002, DEC-RECK-013 | No |

### Governance Efficiency — Summary

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

---

## Parked Issues

Issues not belonging to any active initiative. Tracked for future consideration.

| Issue | Description | Reason Parked |
|-------|-------------|---------------|
| #15 | ExitPlanMode spin loop fix | Blocked on upstream claude-code#26651 |
| #14 | PreToolUse updatedInput support | Blocked on upstream claude-code#26506 |
| #13 | Deterministic agent return size cap | Blocked on upstream claude-code#26681 |
| #37 | Close Write-tool loophole for .proof-status bypass | **Active** — Phase 0 of Robust State Management |
| #36 | Evaluate Opus for implementer agent | Not in remediation scope |
| #25 | Create unified model provider library | Not in remediation scope |
| SQLite Unified State Store (#128-#134) | SQLite WAL state backend replacing flat-file state. Wave 1 (core API + tests) merged to main. Waves 2-4 pending: hook integration, migration, cleanup. 8 planning decisions (DEC-SQLITE-001 through 008). | **Superseded** by State Unification initiative (active). Wave 1 code (state-lib.sh API) is the foundation that State Unification builds on. Remaining waves (hook integration, migration, cleanup) are covered by State Unification W2-W5. |
| Operational Mode System (#114-#118) | 4-tier mode taxonomy (Observe/Amend/Patch/Build) with escalation engine and hook integration. 9 planning decisions. Deep-research validated. | Ambitious for current project scale. Revisit when multi-user or multi-project usage patterns emerge. |
| Backlog Auto-Capture (cancelled) | Automatic issue creation from conversation keywords. 5 planning decisions. | Cancelled (DEC-RECK-006): manual /backlog command is sufficient. prompt-submit.sh already auto-detects deferred-work language. |
