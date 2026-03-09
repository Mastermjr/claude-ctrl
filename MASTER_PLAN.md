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
**Created:** 2026-03-07
**Last updated:** 2026-03-07

The Claude Code configuration directory that shapes how Claude Code operates across all projects. It enforces development practices via hooks (deterministic shell scripts intercepting every tool call), four specialized agents (Planner, Implementer, Tester, Guardian), skills, and session instructions. Instructions guide; hooks enforce.

## Architecture

```
hooks/              — 24 hook scripts + 9 shared libraries; deterministic enforcement layer
agents/             — 4 agent prompt definitions (planner, implementer, tester, guardian)
skills/             — 7 skill directories (deep-research, decide, consume-content, etc.)
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

---

## Active Initiatives

### Initiative: Prompt Purpose Restoration
**Status:** active
**Started:** 2026-03-07
**Goal:** Restore the purpose-to-enforcement ratio in prompts so the model produces deep, purposeful work instead of perfunctory compliance.

> The configuration harness drifted from a 1:1 purpose-to-enforcement ratio (v21, 255-line CLAUDE.md with rich conviction language) to a 5.7:1 enforcement-heavy state (v30, 149 procedurally-dense lines). Agent prompts grew 7.3x (269 to 1,472 lines) with defensive boilerplate repeated across all four agents. Easy-task success dropped from 100% to 67%. This initiative restores the soul: purpose-sandwich CLAUDE.md, shared defensive protocols injected at dispatch time, and slimmed agent prompts that lead with purpose.

**Dominant Constraint:** simplicity

#### Goals
- REQ-GOAL-001: Restore purpose-to-enforcement ratio in CLAUDE.md to approximately 1:1 (from 5.7:1)
- REQ-GOAL-002: Reduce agent prompt total line count by ~40% by extracting shared defensive boilerplate into injected shared protocols
- REQ-GOAL-003: Improve easy-task success rate back toward 100% without regressing medium-task success

#### Non-Goals
- REQ-NOGO-001: Reducing hook count — hooks enforce deterministically and that works well; the goal is reducing cognitive noise in prompts, not removing enforcement
- REQ-NOGO-002: Rewriting hook implementations — this is about what the model reads (prompts, injected context), not what hooks do internally
- REQ-NOGO-003: Adding new features or capabilities — this is restoration and optimization, not expansion

#### Requirements

**Must-Have (P0)**

- REQ-P0-001: CLAUDE.md restored to purpose-sandwich structure (identity/purpose lead, procedural docs referenced, quality standards close)
  Acceptance: Given the current 149-line CLAUDE.md, When restoration is complete, Then:
  - [ ] Purpose/values language is at least 40% of the document
  - [ ] Full pre-metanoia Cornerstone Belief (8 sentences) is restored
  - [ ] Dispatch table lives in DISPATCH.md (referenced, not inlined)
  - [ ] New "What Matters" section explicitly describes quality-of-thought expectations
  - [ ] Document follows purpose-sandwich: identity → purpose → quality expectations → references → procedures

- REQ-P0-002: Shared defensive boilerplate extracted and injected at dispatch time
  Acceptance: Given 4 agent prompts totaling 1,472 lines with repeated CWD safety, trace protocol, mandatory return message, and session-end checklist, When extraction is complete, Then:
  - [ ] `agents/shared-protocols.md` contains all shared defensive content
  - [ ] `subagent-start.sh` injects shared-protocols.md content into additionalContext for all non-lightweight agents
  - [ ] Each agent prompt retains its unique purpose/workflow content without the shared boilerplate
  - [ ] Total agent prompt line count reduced by 30-40%

- REQ-P0-003: "What Matters" section in CLAUDE.md
  Acceptance: Given the current CLAUDE.md lacks quality-of-thought guidance, When the section is added, Then it explicitly addresses:
  - [ ] Deep analysis over surface compliance
  - [ ] Understanding WHY, not just WHAT
  - [ ] Hard numbers and evidence over vague claims
  - [ ] Acting with judgment, not perfunctory rule-following
  - [ ] Making meaningful connections between requirements and implementation

**Nice-to-Have (P1)**

- REQ-P1-001: Agent prompts strengthened with purpose language — each prompt's opening sections emphasize the agent's unique value proposition, not just its procedures
- REQ-P1-004: Guardian merge presentation — after every merge, the Guardian leads with "What should you expect to see?" — putting the value of what was built front and center before git mechanics. The user should understand what changed for them before seeing commit hashes.

**Future Consideration (P2)**

- REQ-P2-001: A/B testing framework for prompt changes — compare quality metrics pre/post to validate improvements

#### Definition of Done

All P0 requirements pass their acceptance criteria. CLAUDE.md follows purpose-sandwich structure with restored Cornerstone Belief and "What Matters" section. Agent prompts are slimmed by 30-40% with shared content injected via subagent-start.sh. Easy-task qualitative output improves (assessed via validation session in W3-1). Satisfies: REQ-GOAL-001, REQ-GOAL-002, REQ-GOAL-003.

#### Architectural Decisions

- DEC-PROMPT-001: Hybrid approach for CLAUDE.md — use pre-metanoia voice/structure but keep current procedural references as pointers
  Addresses: REQ-P0-001.
  Rationale: Pre-metanoia Cornerstone Belief (8 sentences of conviction) and purpose language produced better output. Current procedural references (dispatch table pointer, hook list, resource table) are useful but should follow purpose, not lead. Starting from pre-metanoia voice and selectively adding back what hooks don't enforce.

- DEC-PROMPT-002: Shared protocols injected via subagent-start.sh at dispatch time
  Addresses: REQ-P0-002.
  Rationale: User adjustment — reference-based reading (agent remembers to read a file) is non-deterministic. Hook injection via subagent-start.sh is deterministic — agents see shared protocols without needing to remember. The hook already fires on every agent dispatch and injects additionalContext. New injection point: after trace init, before agent-type-specific context. Content: CWD safety rules, trace protocol, mandatory return message format, session-end checklist.

- DEC-PROMPT-003: "What Matters" section codifies quality-of-thought expectations
  Addresses: REQ-P0-003.
  Rationale: The model lacks explicit guidance on what deep work looks like. Current prompts tell the model WHAT to do (procedures) but not HOW to think (quality expectations). Placing this in purpose position (early in CLAUDE.md) produces better reasoning by setting the frame before procedures.

#### Waves

##### Initiative Summary
- **Total items:** 4
- **Critical path:** 3 waves (W1-1 → W2-1 → W3-1)
- **Max width:** 2 (Wave 1)
- **Gates:** 3 review, 1 approve

##### Wave 1 (no dependencies)
**Parallel dispatches:** 2

**W1-1: Create shared-protocols.md and wire injection in subagent-start.sh (#143)** — Weight: M, Gate: review
- Create `agents/shared-protocols.md` containing:
  - CWD safety rules (never bare `cd` into worktrees, subshell pattern, safe_cleanup)
  - Trace protocol (TRACE_DIR usage, artifacts list per agent type, summary.md requirements)
  - Mandatory return message format (structure, 1500 token limit, never end on bare tool call)
  - Session-end checklist (verify tests pass, annotations present, worktree clean, summary written)
- Extract these sections from all 4 agent prompts — identify the common content by comparing `implementer.md`, `guardian.md`, `tester.md`, `planner.md`
- Modify `hooks/subagent-start.sh`:
  - After line 54 (trace init block), before line 56 (CTX_LINE), add a new block
  - Read `agents/shared-protocols.md` content
  - For non-lightweight agents (skip Bash, Explore), inject content into CONTEXT_PARTS
  - Use `head -c 3000` or similar to cap injection size — the content should be ~2KB
- **Integration:** `hooks/subagent-start.sh` must source the shared-protocols content; `agents/shared-protocols.md` must be a new file in the agents/ directory

**W1-2: Restore CLAUDE.md purpose-sandwich structure (#144)** — Weight: M, Gate: review
- Restructure CLAUDE.md following DEC-PROMPT-001 (hybrid approach):
  - **Lead:** Full Identity section + restored Cornerstone Belief (all 8 sentences from pre-metanoia commit 2eb16a9)
  - **Purpose:** New "What Matters" section (DEC-PROMPT-003) — deep analysis, WHY not just WHAT, hard numbers, judgment over compliance, meaningful connections
  - **Quality:** Interaction Style, Output Intelligence, Sacred Practices — these stay but move after purpose
  - **References:** Resource table, Commands & Skills — compact reference section
  - **Procedures:** Dispatch Rules (compact — full table stays in DISPATCH.md), Notes
- The document should be approximately 200-250 lines (up from 149, but with purpose language comprising ~40%)
- Pre-metanoia source: `git show 2eb16a9:CLAUDE.md` for the Cornerstone Belief text and purpose language
- Do NOT modify hooks, agents, or settings.json in this item
- **Integration:** CLAUDE.md is loaded every session by Claude Code runtime — no explicit import needed. The dispatch table reference should point to `docs/DISPATCH.md`.

##### Wave 2
**Parallel dispatches:** 1
**Blocked by:** W1-1, W1-2

**W2-1: Slim all 4 agent prompts (#146)** — Weight: L, Gate: approve, Deps: W1-1, W1-2
- For each of `agents/planner.md`, `agents/implementer.md`, `agents/tester.md`, `agents/guardian.md`:
  1. Remove sections now covered by shared-protocols.md injection (CWD safety, trace protocol, mandatory return message, session-end checklist)
  2. Keep all unique purpose, workflow, and phase content
  3. Strengthen opening sections with purpose language — each agent should lead with its unique value, not procedures
  4. **Guardian-specific (REQ-P1-004):** Add a "Merge Presentation" section requiring the Guardian to lead post-merge output with "What should you expect to see from this work?" — value delivered, what changed for the user, what they can now do — before git mechanics (commit hash, branch, files). Purpose-first output.
  5. Target: 30-40% line count reduction across all 4 prompts (from 1,472 total to ~900-1,000)
- Specific removals per agent:
  - **implementer.md** (222 lines): Remove "CWD safety" block (~10 lines), "Trace Protocol" section (~15 lines), "Mandatory Return Message" (~15 lines), "Session End Protocol" (~5 lines). Target: ~175 lines
  - **guardian.md** (502 lines): Remove CWD safety in worktree cleanup (~8 lines), trace references (~5 lines), remove session context format that overlaps with shared protocol. Target: ~420 lines
  - **tester.md** (286 lines): Remove "Worktree path safety" block (~5 lines), trace protocol section (~10 lines). Target: ~265 lines
  - **planner.md** (462 lines): Remove trace protocol section (~10 lines), mandatory return message (~10 lines), session end protocol checklist items that overlap. Target: ~440 lines
- Verify no content is lost — every defensive rule must exist in EITHER the agent prompt OR shared-protocols.md (never neither, okay in both for truly agent-specific variants)
- **Integration:** Agent prompts are loaded by Claude Code runtime from agents/ directory. No explicit import changes needed — subagent-start.sh injection ensures shared content reaches agents.

##### Wave 3
**Parallel dispatches:** 1
**Blocked by:** W2-1

**W3-1: Validation session (#147)** — Weight: S, Gate: review, Deps: W2-1
- Run a test session with the restored prompts to qualitatively assess output
- Compare against pre-restoration output quality:
  - Does the implementer produce deeper analysis?
  - Does the orchestrator exercise more judgment (fewer unnecessary permission asks)?
  - Do agent returns include more meaningful summaries?
- Document findings in trace artifacts
- If quality regression is observed, identify which changes caused it and propose adjustments
- **Integration:** No code changes — this is a verification-only item

##### Critical Files
- `CLAUDE.md` — session instructions; the primary prompt surface that shapes all agent behavior
- `agents/shared-protocols.md` — NEW; shared defensive boilerplate injected at dispatch time
- `hooks/subagent-start.sh` — dispatch-time context injection; modified to inject shared protocols
- `agents/implementer.md` — largest delta (222→~175 lines)
- `agents/guardian.md` — most complex agent prompt (502 lines)

##### Decision Log
<!-- Guardian appends here after wave completion -->

#### Prompt Restoration Worktree Strategy

Main is sacred. Each wave dispatches parallel worktrees:
- **Wave 1:** `.worktrees/shared-protocols` on branch `feature/shared-protocols` (W1-1), `.worktrees/claude-md-restore` on branch `feature/claude-md-restore` (W1-2)
- **Wave 2:** `.worktrees/slim-agents` on branch `feature/slim-agents` (W2-1)
- **Wave 3:** `.worktrees/validation` on branch `feature/prompt-validation` (W3-1)

#### Prompt Restoration References

- Pre-metanoia CLAUDE.md: `git show 2eb16a9:CLAUDE.md`
- Pre-metanoia implementer: `git show 2eb16a9:agents/implementer.md`
- Current hook registrations: `settings.json` (10 events, 24 hooks)
- Subagent injection mechanism: `hooks/subagent-start.sh` lines 42-311
- DISPATCH.md: `docs/DISPATCH.md` — full dispatch protocol

---

### Initiative: Governance Signal Audit
**Status:** active
**Started:** 2026-03-07
**Goal:** Produce a comprehensive governance signal map documenting all hooks, their context injection, and overlap to enable informed optimization.

> The hook system grew from 8 to 24 registrations across 10 lifecycle events. Each hook may inject context (additionalContext, systemMessage), deny actions, or produce side effects. No single document maps the total signal volume a model receives per session or per action. Without this map, optimization is guesswork. This initiative produces the map, then proposes smarter signal routing.

**Dominant Constraint:** maintainability

#### Goals
- REQ-GOAL-004: Produce a structured governance signal map documenting all 24 hook registrations, their context injection volume, timing, and overlap
- REQ-GOAL-005: Identify duplicate enforcement (hooks enforcing what prompts already repeat) with specific reduction proposals

#### Non-Goals
- REQ-NOGO-004: Implementing any signal routing changes in this initiative — this is research and proposal only
- REQ-NOGO-005: Changing hook implementations — the audit documents what exists, it does not modify it

#### Requirements

**Must-Have (P0)**

- REQ-P0-004: Governance signal map produced
  Acceptance: Given 24 hook registrations across 10 events, When the audit is complete, Then:
  - [ ] Each hook is documented with: event, matcher, purpose (1 line), output type (deny/allow/advisory/context), injection content summary, estimated byte count, frequency (per-session/per-action/per-agent)
  - [ ] Total signal volume per lifecycle event is calculated
  - [ ] Overlap between hooks is identified (hooks that enforce the same constraint as a prompt)
  - [ ] Document is in `docs/governance-signal-map.md`

**Nice-to-Have (P1)**

- REQ-P1-002: Optimization proposals — specific recommendations for reducing signal noise while maintaining enforcement coverage

**Future Consideration (P2)**

- REQ-P2-002: Implement the optimization proposals in a follow-up initiative

#### Definition of Done

Signal map document exists in `docs/governance-signal-map.md` with all 24 hooks documented. Total signal volume calculated per event. Overlap with prompt content identified. Satisfies: REQ-GOAL-004, REQ-GOAL-005.

#### Architectural Decisions

- DEC-AUDIT-002: Governance signal map as markdown in docs/governance-signal-map.md
  Addresses: REQ-P0-004.
  Rationale: One-time research artifact to inform optimization decisions. Markdown is human-readable and sufficient for this purpose. JSON would add complexity without value.

#### Waves

##### Initiative Summary
- **Total items:** 2
- **Critical path:** 2 waves (W1-3 → W2-2)
- **Max width:** 1
- **Gates:** 1 review, 1 approve

##### Wave 1 (no dependencies)
**Parallel dispatches:** 1

**W1-3: Produce governance signal map (#145)** — Weight: L, Gate: review
- Audit all hooks registered in `settings.json`:
  - For each hook: read the source, identify what it outputs (deny/allow/advisory/context injection)
  - Measure: approximate byte count of injected context per invocation
  - Document: frequency (how often it fires — per-session, per-tool-call, per-agent-dispatch)
- Map total signal volume per lifecycle event:
  - SessionStart: what the model sees at session start (session-init.sh injection)
  - UserPromptSubmit: what fires on every user message (prompt-submit.sh)
  - PreToolUse: what fires before each tool call (pre-bash.sh, pre-write.sh, task-track.sh, pre-ask.sh)
  - PostToolUse: what fires after each tool call (post-write.sh, lint.sh, etc.)
  - SubagentStart: what agents see at dispatch (subagent-start.sh)
  - SubagentStop: what fires when agents return (check-*.sh hooks)
  - Stop: what fires at session end (stop.sh)
- Identify overlap: places where hooks enforce rules that prompts also state
- Write output to `docs/governance-signal-map.md`
- **Integration:** New file in docs/ directory. No code changes. Referenced by future optimization work.

##### Wave 2
**Parallel dispatches:** 1
**Blocked by:** W1-3

**W2-2: Propose optimization plan (#148)** — Weight: M, Gate: approve, Deps: W1-3
- Based on signal map findings, propose:
  - Which signals can be removed from prompts because hooks enforce them deterministically
  - Which hook injections can be made conditional (only fire when relevant, not on every invocation)
  - Which context injections can be compressed (shorter messages, same information)
  - Priority-ranked list of changes with estimated token savings per session
- Write proposals as an addendum to `docs/governance-signal-map.md` or a separate `docs/signal-optimization-proposals.md`
- Do NOT implement any changes — this is proposal only, to be approved before a follow-up initiative
- **Integration:** Markdown document in docs/. No code changes.

##### Critical Files
- `settings.json` — hook registrations (source of truth for what hooks exist)
- `hooks/session-init.sh` — largest context injection (SessionStart)
- `hooks/subagent-start.sh` — per-agent context injection (SubagentStart)
- `hooks/prompt-submit.sh` — fires on every user message
- `hooks/pre-bash.sh` — fires before every Bash command

##### Decision Log
<!-- Guardian appends here after wave completion -->

#### Governance Audit Worktree Strategy

Main is sacred. Each wave dispatches parallel worktrees:
- **Wave 1:** `.worktrees/signal-map` on branch `feature/signal-map` (W1-3)
- **Wave 2:** `.worktrees/signal-optimization` on branch `feature/signal-optimization` (W2-2)

#### Governance Audit References

- Hook registrations: `settings.json`
- Hook source code: `hooks/*.sh`
- Hook documentation: `hooks/HOOKS.md`
- Architecture reference: `ARCHITECTURE.md` sections 2-5 (hook engine, gate hooks, feedback hooks, session lifecycle)

---

### Initiative: Governor Subagent
**Status:** active
**Started:** 2026-03-09
**Goal:** Add a 5th agent — the governor — that serves as the system's mechanical feedback mechanism, evaluating initiatives against the project's core intent and trajectory at critical junctures, and meta-evaluating the health of the evaluative infrastructure itself.

> The system has a well-defined Act pipeline (Planner -> Implementer -> Tester -> Guardian) and a deterministic Enforce layer (24 hooks), but evaluation of whether work serves the project's trajectory is manual and periodic (/reckoning on demand, /observatory on traces). No agent fires automatically at initiative boundaries to check whether planned work honors the Original Intent, whether completed work actually served the trajectory, or whether the evaluative infrastructure (observatory, reckoning, traces, plan) is itself healthy. The governor closes this loop. Like a centrifugal governor on a steam engine, it does not DO the work — it measures whether the work is staying within bounds and feeds that signal back to the controller. It fires at exactly three moments: before multi-wave implementation begins, when an initiative completes, and as structured input to reckoning. It is meta-evaluative: it evaluates both the work AND the systems that evaluate the work — the SESAP concept applied recursively to the system's own governance infrastructure.

**Dominant Constraint:** simplicity

#### Goals
- REQ-GOAL-006: Enable automatic trajectory evaluation at multi-wave initiative boundaries (before implementation, after completion)
- REQ-GOAL-007: Provide structured input to `/reckoning` pipeline and consume reckoning output (bidirectional) to ground assessments in the project's evolved trajectory state
- REQ-GOAL-008: Keep evaluation lean — under 50 tool calls and under 20K tokens per dispatch

#### Non-Goals
- REQ-NOGO-006: Replacing `/reckoning` — the governor evaluates per-initiative; reckoning evaluates the project; they are complementary, not redundant
- REQ-NOGO-007: Firing on every planner session — lightweight plans (Tier 1, single-wave) do not need evaluation; the governor only triggers for 2+ wave initiatives
- REQ-NOGO-008: Evaluating phase boundaries — that is the Guardian's domain; the governor operates at initiative level
- REQ-NOGO-009: Deep research, test execution, code analysis, or acting on findings — the governor reads and judges; it never writes to the project, runs commands, or invokes other agents

#### Requirements

**Must-Have (P0)**

- REQ-P0-005: Agent prompt definition at `agents/governor.md`
  Acceptance: Given the existing 4-agent system, When the governor prompt is created, Then:
  - [ ] Prompt leads with purpose (mechanical governor role, intent fidelity, meta-evaluation) not procedures
  - [ ] Defines exactly 3 trigger contexts: pre-implementation, post-completion, reckoning-input
  - [ ] Includes a scoring rubric with 4 initiative-evaluation dimensions (intent-alignment, priority-coherence, principle-adherence, scope-discipline) each scored 1-5
  - [ ] Includes 4 meta-evaluation dimensions (observatory-health, reckoning-health, trace-quality, plan-currency) each scored 1-5
  - [ ] Specifies output format: structured JSON (`evaluation.json`) + human-readable summary (`evaluation-summary.md`)
  - [ ] Specifies allowed tools: Read, Grep, Glob only (no Write, no Bash, no Agent)
  - [ ] Specifies full input set: MASTER_PLAN.md, most recent reckoning, traces, specific initiative being evaluated
  - [ ] Prompt is under 200 lines

- REQ-P0-006: Integration with dispatch system
  Acceptance: Given the dispatch infrastructure (DISPATCH.md, subagent-start.sh, task-track.sh), When the governor is wired in, Then:
  - [ ] DISPATCH.md routing table has a governor row with trigger conditions (after planner returns with 2+ waves, after initiative completion, before reckoning)
  - [ ] `subagent-start.sh` has a `governor` case injecting: MASTER_PLAN.md identity/principles/original-intent, active initiative being evaluated, most recent reckoning verdict and what-to-confront (if reckoning exists)
  - [ ] `task-track.sh` recognizes `governor` as a valid agent type (no proof-status gate — governor does not write code)
  - [ ] Governor is exempt from worktree gate (Gate C.1) — it evaluates, it does not implement

- REQ-P0-007: SubagentStop validation hook `hooks/check-governor.sh`
  Acceptance: Given the check-*.sh pattern for all existing agents, When the governor returns, Then:
  - [ ] Hook validates that the governor produced a scored assessment (not empty return)
  - [ ] Hook captures assessment to trace artifacts (`evaluation.json`, `evaluation-summary.md`)
  - [ ] Hook is registered in `settings.json` SubagentStop with matcher `governor`
  - [ ] Hook emits assessment verdict in additionalContext so orchestrator sees the result
  - [ ] Hook is under 80 lines (lean, like check-explore.sh, not heavy like check-tester.sh)

- REQ-P0-008: Governor output format and storage
  Acceptance: Given a governor dispatch, When the assessment is complete, Then:
  - [ ] Assessment written to `{TRACE_DIR}/artifacts/evaluation.json` with structure: `{ "dimensions": { "intent_alignment": {"score": N, "evidence": "..."}, ... }, "meta_dimensions": { "observatory_health": {"score": N, "evidence": "..."}, ... }, "verdict": "proceed|caution|block", "flags": [...], "narrative": "..." }`
  - [ ] Assessment also written as `{TRACE_DIR}/artifacts/evaluation-summary.md` (human-readable)
  - [ ] Assessment references specific DEC-IDs, REQ-IDs, and Principle numbers from MASTER_PLAN.md
  - [ ] Verdict logic: proceed (all initiative dimensions >= 3), caution (any 2, none 1), block (any 1)

**Nice-to-Have (P1)**

- REQ-P1-003: Reckoning integration — `/reckoning` reads the most recent governor assessments from traces when performing Phase 2 cross-reference, incorporating initiative-level and meta-evaluations into the Seven-Dimensional Analysis
- REQ-P1-005: Scoring rubric calibration test — a test that validates the governor's output JSON schema against a synthetic initiative block

**Future Consideration (P2)**

- REQ-P2-003: Auto-dispatch via hook — a PostToolUse:Task|Agent hook that detects planner completion with 2+ waves and auto-dispatches the governor
- REQ-P2-004: Historical trend tracking — store governor scores in a persistent file so reckoning can show intent-alignment trends over time

#### Definition of Done

All P0 requirements pass their acceptance criteria. `agents/governor.md` defines the 5th agent with purpose-led prompt, 4+4 dimension rubric, 3 trigger contexts, and read-only tool constraints. Dispatch infrastructure recognizes the governor type and injects appropriate context. `hooks/check-governor.sh` validates output and emits verdict. Governor can be dispatched against an existing initiative and produces valid `evaluation.json` + `evaluation-summary.md`. Satisfies: REQ-GOAL-006, REQ-GOAL-007, REQ-GOAL-008.

#### Architectural Decisions

- DEC-GOV-001: Use Opus for the governor agent
  Addresses: REQ-GOAL-008.
  Rationale: The governor's entire value is judgment quality — scoring intent alignment, detecting scope drift, assessing principle adherence, meta-evaluating infrastructure health. At ~2 dispatches per initiative, the cost delta between Opus (~$0.15/dispatch) and Sonnet (~$0.02/dispatch) is negligible. Sonnet is appropriate for high-volume agents (implementer, tester); Opus is appropriate for low-volume judgment agents (planner, guardian, governor).

- DEC-GOV-002: 4+4 dimension scoring rubric with narrative and verdict
  Addresses: REQ-P0-005, REQ-P0-008.
  Rationale: 4 initiative-evaluation dimensions (intent-alignment, priority-coherence, principle-adherence, scope-discipline) assess the work. 4 meta-evaluation dimensions (observatory-health, reckoning-health, trace-quality, plan-currency) assess the evaluative infrastructure itself — the SESAP concept applied recursively. Each scored 1-5 with evidence. Verdict: proceed (all initiative dims >= 3), caution (any 2, none 1), block (any 1). 7-dimension overlap with reckoning rejected; 3-tier-only too coarse for trend tracking.

- DEC-GOV-003: Orchestrator instruction-based dispatch via DISPATCH.md rules
  Addresses: REQ-P0-006, REQ-NOGO-007.
  Rationale: The system already successfully uses instruction-based auto-dispatch for tester (after implementer) and guardian (on verification). Adding a rule "dispatch governor after planner returns with 2+ waves" follows the same proven pattern. Hook-based auto-dispatch (P2) is the upgrade path if instruction compliance proves unreliable. Simpler now, no hook changes needed for trigger logic.

- DEC-GOV-004: Bidirectional reckoning relationship — governor consumes AND provides
  Addresses: REQ-P1-003, REQ-P0-005.
  Rationale: The governor reads the most recent reckoning (verdict, trajectory, what-to-confront) to ground its assessment in the project's evolved trajectory state — not just static plan text. The governor writes structured assessment JSON to trace artifacts that reckoning reads in Phase 2. One-directional (provide-only) would miss the insight that a recent reckoning reveals about where the project actually is vs. where the plan says it is. Governor's full input set: MASTER_PLAN.md, most recent reckoning, traces, and the specific initiative being evaluated.

- DEC-GOV-005: Read-only tools (Read, Grep, Glob) plus trace artifact writes
  Addresses: REQ-NOGO-009, REQ-GOAL-008.
  Rationale: The governor is a judgment agent, not an implementation agent. Giving it Write or Bash would invite scope creep (governor starts "fixing" things it finds). Read-only plus trace artifact writes (via standard trace protocol) enforces the governor role — it evaluates and reports, never acts. This is a hard constraint, not a suggestion.

#### Waves

##### Initiative Summary
- **Total items:** 4
- **Critical path:** 3 waves (W1-1 -> W2-1 -> W3-1)
- **Max width:** 2 (Wave 1)
- **Gates:** 2 review, 1 approve, 1 none

##### Wave 1 (no dependencies)
**Parallel dispatches:** 2

**W1-1: Create `agents/governor.md` agent prompt (#182)** — Weight: M, Gate: review
- Create `agents/governor.md` with purpose-led structure:
  - **Opening:** Governor identity — mechanical governor metaphor, feedback mechanism for a self-modifying system, evaluates both work and the systems that evaluate work
  - **Section 1: Trigger Contexts** — Define the 3 dispatch contexts:
    1. **Pre-implementation:** Planner completed a 2+ wave initiative. Governor reads initiative block, MASTER_PLAN.md principles/intent, most recent reckoning. Assesses: does this work serve the original intent? Are priorities ordered by trajectory? Does scope stay within declared bounds?
    2. **Post-completion:** All phases of an initiative merged. Governor reads completed initiative summary, decision log entries, traces. Assesses: did the work honor the intent? Did scope drift occur? What did the meta-evaluation dimensions reveal?
    3. **Reckoning-input:** Dispatched by reckoning skill during Phase 2. Governor produces a focused assessment of active initiatives for reckoning to consume.
  - **Section 2: Initiative Evaluation Rubric** — 4 dimensions scored 1-5:
    - `intent_alignment`: Does this initiative serve the Original Intent and active Principles?
    - `priority_coherence`: Are priorities ordered by trajectory awareness, not just urgency?
    - `principle_adherence`: Does the work reference and honor stated Principles by number?
    - `scope_discipline`: Does the work stay within declared goals/non-goals?
  - **Section 3: Meta-Evaluation Rubric** — 4 dimensions scored 1-5:
    - `observatory_health`: Is the observatory being run? Are suggestions acted on? Is the trace-to-improvement pipeline functional?
    - `reckoning_health`: Are reckonings produced at appropriate cadence? Are findings acted on? Is the reckoning-to-action pipeline functional?
    - `trace_quality`: Are agents producing traces? Are summaries substantive? Is the archive growing healthily?
    - `plan_currency`: Is MASTER_PLAN.md up to date? Are completed initiatives compressed? Are decision log entries appended? Are parked issues reviewed?
  - **Section 4: Output Format** — Specifies `evaluation.json` schema and `evaluation-summary.md` format
  - **Section 5: Verdict Logic** — proceed (all initiative dims >= 3), caution (any 2, none 1), block (any 1)
  - **Section 6: Behavioral Constraints** — Read-only tools, no acting on findings, no invoking other agents/skills, under 50 tool calls, return message under 1500 tokens
- Target: under 200 lines
- **Integration:** `agents/governor.md` is loaded by Claude Code runtime from agents/ directory. Referenced in DISPATCH.md routing table and CLAUDE.md Resources table.

**W1-2: Create `hooks/check-governor.sh` SubagentStop hook (#183)** — Weight: S, Gate: none
- Create `hooks/check-governor.sh` following the check-explore.sh pattern (lean, ~60-80 lines):
  - Source `source-lib.sh`, require session + trace
  - Read agent response from stdin
  - Track subagent stop + tokens + session event
  - Validate assessment output:
    - Check `TRACE_DIR/artifacts/evaluation.json` exists and is valid JSON
    - Check `TRACE_DIR/artifacts/evaluation-summary.md` exists and is non-empty
    - Extract verdict from evaluation.json
  - Finalize trace
  - Emit verdict in additionalContext: "Governor assessment: verdict=[proceed|caution|block]. [1-line summary]. Full assessment: {TRACE_DIR}/artifacts/evaluation-summary.md"
  - Handle silent return: if no evaluation artifacts, inject trace summary (Layer A pattern from check-implementer.sh)
  - Exit 0 (governor results are advisory, never blocking)
- **Integration:** Register in `settings.json` under SubagentStop with matcher `governor`. File at `hooks/check-governor.sh`.

##### Wave 2
**Parallel dispatches:** 1
**Blocked by:** W1-1, W1-2

**W2-1: Wire governor into dispatch infrastructure (#184)** — Weight: M, Gate: approve, Deps: W1-1, W1-2
- **DISPATCH.md** updates:
  - Add routing table row: `| Plan/initiative evaluation | **Governor** | No — dispatched automatically after planner (2+ waves), after initiative completion, before reckoning |`
  - Add "Auto-dispatch to Governor" section after "Auto-dispatch to Tester": "After the planner returns with a 2+ wave initiative, dispatch the governor automatically with the initiative block. Do NOT ask 'should I evaluate?' — dispatch. Governor results are advisory: proceed = continue normally, caution = present concerns to user before implementing, block = present to user and wait for guidance. After initiative completion (all phases merged, before compress_initiative), dispatch governor for post-completion assessment."
  - Add governor to Pre-Dispatch Gates note: "Governor dispatch: no proof-status gate, no worktree gate. Governor is read-only."
- **subagent-start.sh** updates:
  - Add `governor` case in the agent-type-specific context block (after `planner|Plan` case, before `implementer` case):
    ```
    governor)
        CONTEXT_PARTS+=("Role: Governor — mechanical feedback mechanism. Evaluate the initiative against project intent, principles, and trajectory. Produce scored assessment (evaluation.json + evaluation-summary.md). Read-only: do NOT write to the project, run commands, or invoke other agents.")
        # Inject MASTER_PLAN.md identity, principles, original intent (compact)
        # Inject most recent reckoning verdict + what-to-confront (if exists)
        # Inject TRACE_DIR
    ```
  - Read most recent reckoning from `{PROJECT_ROOT}/reckonings/` (most recent by filename date), extract verdict and "What to Confront" section, inject as context (cap at 2000 bytes)
  - Inject MASTER_PLAN.md `## Original Intent` and `## Principles` sections (compact, ~500 bytes)
- **task-track.sh** updates:
  - Add `governor` to the recognized agent types (alongside implementer, planner, guardian, tester)
  - Skip proof-status gate for governor (same pattern as planner — governor does not write code)
  - Skip worktree gate (Gate C.1) for governor — it evaluates, it does not need a worktree
- **settings.json** updates:
  - Add SubagentStop entry: `{ "matcher": "governor", "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/check-governor.sh", "timeout": 5 }] }`
- **CLAUDE.md** updates:
  - Add governor to Resources table: `| agents/governor.md | Evaluating initiatives against project trajectory |`
- **Integration:** This is the wiring wave — it connects the governor prompt (W1-1) and hook (W1-2) to the dispatch infrastructure. All modified files are existing infrastructure files.

##### Wave 3
**Parallel dispatches:** 1
**Blocked by:** W2-1

**W3-1: Validation — dispatch governor against existing initiative (#185)** — Weight: S, Gate: review, Deps: W2-1
- Dispatch the governor against the "Prompt Purpose Restoration" initiative (active, multi-wave, well-documented)
- Verify output:
  - `evaluation.json` is valid JSON with correct schema (4 initiative dimensions + 4 meta dimensions + verdict + flags + narrative)
  - `evaluation-summary.md` is non-empty and human-readable
  - Verdict is one of: proceed, caution, block
  - Each dimension has a score 1-5 and evidence referencing specific DEC-IDs, REQ-IDs, or Principle numbers
  - Meta-evaluation dimensions produce meaningful assessments of observatory, reckoning, trace, and plan health
- Document findings in trace artifacts
- If output quality is insufficient, identify which prompt sections need adjustment and propose changes
- **Integration:** No code changes — this is a verification-only item

##### Critical Files
- `agents/governor.md` — NEW; the 5th agent prompt defining the governor's identity, rubric, and behavioral constraints
- `hooks/check-governor.sh` — NEW; SubagentStop validation for governor returns
- `docs/DISPATCH.md` — routing table and auto-dispatch rules; governor row and dispatch instructions added
- `hooks/subagent-start.sh` — governor case with reckoning/plan context injection
- `hooks/task-track.sh` — governor type recognition and gate exemptions

##### Decision Log
<!-- Guardian appends here after wave completion -->

#### Governor Subagent Worktree Strategy

Main is sacred. Each wave dispatches parallel worktrees:
- **Wave 1:** `.worktrees/governor-prompt` on branch `feature/governor-prompt` (W1-1), `.worktrees/governor-hook` on branch `feature/governor-hook` (W1-2)
- **Wave 2:** `.worktrees/governor-wiring` on branch `feature/governor-wiring` (W2-1)
- **Wave 3:** `.worktrees/governor-validation` on branch `feature/governor-validation` (W3-1)

#### Governor Subagent References

- Existing agent prompts: `agents/implementer.md` (168 lines), `agents/tester.md` (236 lines), `agents/guardian.md` (481 lines), `agents/planner.md` (435 lines)
- Shared protocols (injected at spawn): `agents/shared-protocols.md` (87 lines)
- Dispatch infrastructure: `docs/DISPATCH.md`, `hooks/subagent-start.sh`, `hooks/task-track.sh`
- SubagentStop hook pattern (lean): `hooks/check-explore.sh`
- SubagentStop hook pattern (full): `hooks/check-tester.sh`, `hooks/check-implementer.sh`
- Hook registration: `settings.json` SubagentStop section
- Reckoning skill: `skills/reckoning/SKILL.md` — governor consumes reckoning output and provides structured input
- Observatory: `observatory/` — governor meta-evaluates observatory health
- Issue: #169

---

## Completed Initiatives

| Initiative | Period | Phases | Key Decisions | Archived |
|-----------|--------|--------|---------------|----------|
| Production Remediation (Metanoia Suite) | 2026-02-28 to 2026-03-01 | 5 | DEC-HOOKS-001 thru DEC-TEST-006 | No |
| State Management Reliability | 2026-03-01 to 2026-03-02 | 5 | DEC-STATE-007, DEC-STATE-008 + 8 test decisions | No |
| Hook Consolidation Testing & Streamlining | 2026-03-02 | 4 | DEC-AUDIT-001, DEC-TIMING-001, DEC-DEDUP-001 | No |
| Statusline Information Architecture | 2026-03-02 | 2 | DEC-SL-LAYOUT-001, DEC-SL-TOKENS-001, DEC-SL-TODOCACHE-001, DEC-SL-COSTPERSIST-001 | No |

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
| SQLite Unified State Store (#128-#134) | SQLite WAL state backend replacing flat-file state. Wave 1 (core API + tests) merged to main. Waves 2-4 pending: hook integration, migration, cleanup. 8 planning decisions (DEC-SQLITE-001 through 008). | Park until prompt restoration completes. Wave 1 code is stable and tested in main. Reactivate when ready to replace flat-file state system-wide. |
| Operational Mode System (#114-#118) | 4-tier mode taxonomy (Observe/Amend/Patch/Build) with escalation engine and hook integration. 9 planning decisions. Deep-research validated. | Ambitious for current project scale. Revisit when multi-user or multi-project usage patterns emerge. |
| Backlog Auto-Capture (cancelled) | Automatic issue creation from conversation keywords. 5 planning decisions. | Cancelled (DEC-RECK-006): manual /backlog command is sufficient. prompt-submit.sh already auto-detects deferred-work language. |
