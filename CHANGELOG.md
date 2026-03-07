# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.1.0] - 2026-03-07

### Added
- `feature/sqlite-w1`: SQLite WAL-based state store (Wave 1) — rewrite hooks/state-lib.sh with sqlite3 backend (state_update, state_read, state_cas, state_delete, workflow_id), WAL mode with busy_timeout=5000ms, per-workflow isolation via workflow_id column, SQL injection prevention, lattice-enforced CAS, legacy jq functions preserved as _legacy_* for Wave 2 migration; 20-test suite in test-sqlite-state.sh covering schema, CRUD, CAS, lattice, concurrency, and injection; `--scope sqlite` in run-hooks.sh (DEC-SQLITE-001 through DEC-SQLITE-010, closes #128, #129)
- `feature/sqlite-state-store`: SQLite Unified State Store initiative added to MASTER_PLAN.md — 4-wave implementation plan replacing scattered flat-file state with single SQLite WAL database, 8 architectural decisions (DEC-SQLITE-001 through 008), 9 P0 requirements, issues #128-#134
- `feature/lint-on-write`: Multi-language lint-on-write hook (hooks/lint.sh) — synchronous PostToolUse on Write/Edit runs shellcheck/ruff/go vet/cargo clippy with CI-matching exclusions, 3s cooldown per file, linter install suggestions; Check 6b post-commit shellcheck advisory in check-guardian.sh; 38 lint-scope tests in run-hooks.sh; fix SC2116 and SC2059 x2 in existing scripts (DEC-LINT-001)
- `feature/dispatch-enforcement-tests`: Orchestrator guard test suite — 8 tests across 6 scenarios for Gate 1.5 (DEC-DISPATCH-003): deny orchestrator, allow subagent, backward compat (missing SID), non-source bypass, and protected file registry (DEC-TEST-ORCH-GUARD-001)
- `feature/dispatch-enforcement`: Gate 1.5 in pre-write.sh blocks orchestrator from writing source code directly — compares CLAUDE_SESSION_ID against .orchestrator-sid (written by session-init.sh) to detect orchestrator context; dispatch routing table restored to CLAUDE.md; .orchestrator-sid lifecycle managed by session-init/session-end (DEC-DISPATCH-001, DEC-DISPATCH-002, DEC-DISPATCH-003)
- `feature/operational-mode-system`: Operational Mode System initiative added to MASTER_PLAN.md — 4-tier mode taxonomy (Observe/Amend/Patch/Build) with proportional governance, 5 waves of 15 work items, 9 architectural decisions (DEC-MODE-*), issues #114-#118
- `feature/rsm-phase4`: Self-validation infrastructure — version sentinels in all library files, `bash -n` syntax preflight in session-init.sh, `hooks-gen` integrity check via post-merge git hook, 292-line self-validation test suite (test-self-validation.sh), source-lib.sh `lib_files()` enumerator for consistent library discovery
- `feature/dispatch-gate`: Gate 0 (dispatch-confirmation-deny) in pre-ask.sh — mechanically blocks orchestrator dispatch-confirmation questions ("Want me to dispatch Guardian?") enforcing CLAUDE.md auto-dispatch rules; fires before orchestrator bypass so it catches this specific anti-pattern while allowing legitimate questions through; 3 new test fixtures + 3 new test cases (DEC-ASK-GATE-001 updated)
- `feature/production-reliability`: Production Reliability Phase 4+5 — macOS CI matrix (ubuntu-latest + macos-latest) with 10min timeout, shellcheck extended to tests/ and scripts/; README.md and ARCHITECTURE.md updated from old individual hook names to consolidated entry points (pre-bash.sh, pre-write.sh, post-write.sh, stop.sh)
- `feature/phase2-state-consolidation`: State management consolidation — `_lock_fd()` wired into state-lib.sh and log.sh replacing inline flock fallback chains; `cas_proof_status()` in prompt-submit.sh rewritten for true atomic CAS with lattice validation; Gate C.2 in task-track.sh routed through `write_proof_status()`; check-guardian.sh adds "committed" transition before cleanup; pre-bash.sh Checks 9+10 adopt `is_protected_state_file()` registry (DEC-STATE-REGISTRY-002); `state_write_locked()` removed (dead code); 15 concurrency tests updated (DEC-STATE-CAS-002, DEC-STATE-LATTICE-001)
- `feature/production-reliability`: Production Reliability Phase 1+2 — CI auto-discovers test files via `find` instead of hardcoded list in validate.yml; grep-to-jq JSON parsing conversions in test-pre-ask.sh and test-ci-feedback.sh; `run_hook()`/`run_hook_ec()` capture stderr to `$HOOK_STDERR` instead of swallowing; cleanup traps added to 31 test files; JSONL rotation (1000 lines), timing log rotation, orphan marker sweep in session-init.sh; TTL sentinels scoped to `$CLAUDE_SESSION_ID` in stop.sh; MASTER_PLAN.md amended with new initiative (5 phases, 16 work items)
- `feature/integration-gates`: Strengthen integration wiring gates — declaration-trap warnings in tester Phase 2.5 and implementer checklist (catch `mod`/`import` declarations without actual consumers); phantom-reference Check 7b in check-implementer.sh verifies settings.json hook command paths resolve to existing files (DEC-IWIRE-002)
- `feature/phase1-coordination`: Phase 1 coordination protocol — protected state file registry in core-lib.sh with `is_protected_state_file()`, CAS (compare-and-swap) semantics via `state_write_locked()` in state-lib.sh, `.proof-epoch` session initialization, `cas_proof_status()` delegation in prompt-submit.sh, Gate 0 refactored to use registry; 12 new concurrency tests + `--scope concurrency` in run-hooks.sh (DEC-STATE-REGISTRY-001, DEC-STATE-CAS-001, DEC-PROOF-CAS-REFACTOR-001, DEC-CONCURRENCY-TEST-001) (#76)
- `feature/responsive-statusline`: Priority-based responsive segment dropping — when terminal width is insufficient, segments drop from lowest priority first (fully, not mid-word); `ansi_visible_width()` helper; cold-start cache fix in track-agent-tokens.sh writes full 14-field schema; SIGPIPE fix in test-statusline.sh (exit 141) converting 22 direct-pipe patterns to capture-then-extract; 6 new responsive tests + 1 cold-start test (66/66 + 11/11) (DEC-RESPONSIVE-001)
- `feature/backlog-gaps`: Phase 3 unified gaps report — gaps-report.sh (575 lines) combines debt markers, missing @decision annotations, stale issues, unclosed worktrees, and hook coverage into a single accountability report; /gaps command wrapper; hook dead-code cleanup in log.sh, prompt-submit.sh, state-lib.sh, task-track.sh; 13 new gaps tests (78 total) (#83)
- `feature/backlog-scanner`: scan-backlog.sh rg-based codebase debt marker scanner (TODO, FIXME, HACK, WORKAROUND, OPTIMIZE, TEMP, XXX) with JSON/table/text output formats, grep fallback, recursive directory scanning; /scan command wrapper for orchestrator dispatch; 15 new scan tests (#82)
- `feature/statusline-banner`: Redesign initiative segment as Line 0 banner — replace cryptic inline "Robust+1:P0" with dedicated top-line showing full initiative name, phase progress (N/M), and phase title with em dash subtitle; statusline is now 3 lines when active initiative exists, 2 lines otherwise (backward compatible); per-initiative phase counting (DEC-STATUSLINE-004); Group 12 rewritten with 6 banner tests (#91)
- `feature/statusline-initiative`: Initiative/phase context in statusline — shows active initiative name and in-progress phase (e.g. "Backlog:P3") between workspace and git clusters; truncates long names, +N suffix for multiple initiatives; 6 new tests (#91)
- `feature/subagent-token-tracking`: Universal SubagentStop hook parses agent transcript JSONL to accumulate token usage; statusline shows combined tokens as `tokens: 145k` with sigma grand total; 10 new tests
- `feature/backlog-foundation`: todo.sh backlog backing layer (hud/count/claim/create) + fire-and-forget auto-capture of deferred-work language in prompt-submit.sh; 15 new tests (#81)
- `feature/cache-audit`: @decision annotations for statusline dependency chain (DEC-STATUSLINE-DEPS-001) and prompt cache semantics (DEC-CACHE-RESEARCH-001); .gitignore entries for `.session-cost-history` and `.test-status` (#66, #70)
- `feature/project-isolation`: Cross-project state isolation via 8-char SHA-256 project hash — scopes .proof-status, .active-worktree-path, and trace markers per project root to prevent state contamination across concurrent Claude Code sessions; three-tier backward-compatible lookup; 20 new isolation tests
- `feature/plan-redesign-tests`: Phase 4 test suite for living plan format — 16 new tests across 2 suites (test-plan-lifecycle.sh, test-plan-injection.sh) validating initiative lifecycle edge cases and bounded session injection; bug fix for empty Active Initiatives section returning active instead of dormant (#142)
- Documentation audit — 38 discrepancies resolved: hardcoded hook counts removed, 3 undocumented hooks documented, updatedInput contradiction corrected, tester max_turns fixed
- doc-freshness.sh — PreToolUse:Bash hook enforcing documentation freshness at merge time; blocks merges to main when tracked docs are critically stale
- check-explore.sh — SubagentStop:Explore hook for post-exploration validation of Explore agent output quality
- check-general-purpose.sh — SubagentStop:general-purpose hook for post-execution validation of general-purpose agent output quality
- Worktree Sweep — Three-way reconciliation (filesystem/git/registry) with session-init orphan scan, post-merge Check 7b auto-cleanup, and proof-status leak fix
- Trace Analysis System — Agent trace indexing and outcome classification
- Tester Agent — Fourth agent for end-to-end verification with auto-verify fast path
- Checkpoint System — Git ref-based snapshots before writes with `/rewind` restore skill
- CWD Recovery — Three-path system for worktree deletion CWD death spiral: directed recovery, canary-based recovery, prevention in guard.sh
- Cross-Session Learning — Session-aware hooks with trajectory guidance, friction pattern detection
- Session Summaries in Commits — Structured session context embedded in commit metadata
- SDLC Integrity Layer — Guard hardening, state hygiene, preflight checks
- Tester Completeness Gate — Check 3 in check-tester.sh validates verification coverage
- Environment Variable Handoff — Implementer-to-tester environment variable propagation
- /diagnose Skill — System health checks integrated into agent pipeline
- Guard Check 0.75 — Subshell containment for `cd` into `.worktrees/` directories
- Security policy (SECURITY.md) with vulnerability reporting guidelines
- ARCHITECTURE.md comprehensive technical reference (18 sections)

### Changed
- `feature/statusline-data`: Phase 2 data pipeline — todo split display (`todos: 3p 7g` with project/global counts), session cost persistence to `.session-cost-history`, lifetime cost annotation next to session cost; +9 new tests (48 total dedicated) (#72)
- `feature/statusline-rendering`: Statusline rendering overhaul — domain-clustered labels (`dirty:`, `wt:`, `agents:`, `todos:`), aggregate token segment with K/M notation, `~$` cost prefix; +12 new tests (39 total dedicated)
- `feature/statusline-redesign`: Two-line status HUD — line 1 shows project context (model, workspace, dirty files, worktrees, agents, todos), line 2 shows session metrics (context window bar, cost, duration, lines changed, cache efficiency); 26 new dedicated tests
- `feature/dispatch-reliability`: Dispatch sizing rules, turn-budget discipline, and planner dispatch plans — orchestrator splits large phases into 2-3 item batches, implementer self-regulates with budget notes and early return at 15 turns, planner generates per-phase dispatch plans (#43)
- `feature/observatory-stdout`: Observatory report.sh now prints a concise stdout summary (regressions, health, signals, batches) after writing the full report file
- `feature/living-plan-hooks`: Living MASTER_PLAN format — initiative-level lifecycle with dormant/active states, get_plan_status() rewrite, plan-validate.sh structural validation, bounded session-init injection (796->81 lines), compress_initiative() for archival (#140)
- `refactor/shared-library`: Phase 8 shared library consolidation — 13 hooks converted from raw jq to `get_field()`, `get_session_changes()` ported to context-lib.sh with glob fallback, SOURCE_EXTENSIONS unified; plus DEC-PROOF-PATH-003 meta-repo proof-status double-nesting fix (#7, #137)
- Planner create-or-amend workflow — `agents/planner.md` rewritten (391->629 lines) to support both creating new MASTER_PLAN.md and amending existing living documents with new initiatives; auto-detects plan format via `## Identity` marker (#139)
- Tester agent rewrite — 8 targeted fixes for 37.5% failure rate: feature-match validation, test infrastructure discovery, early proof-status write, hook/script table split, worktree path safety, meta-infra exception, retry limits, mandatory trace protocol
- Auto-verify restructured — Runs before heavy I/O for faster verification path
- Observatory assessment overhaul — Comprehensive reports, comparison matrix, deferred lifecycle management
- Observatory signal catalog — Extended from 5 to 12 signals across 4 categories
- Session-init performance — Startup latency reduced from 2-10s to 0.3-2s with 4 targeted fixes
- Guardian auto-cleans worktrees after merge instead of delegating to user
- GitHub Actions now pin to commit SHAs for supply chain security
- Guard rewrite calls converted to deny — `updatedInput` not supported in PreToolUse hooks
- `feature/impl-perf-fixes`: Remove CYCLE_MODE auto-flow entirely; slim implementer.md 289->223 lines; fix subagent token cache path; raise stale marker threshold 15min->60min; add TEST_SCOPE signal for proportional testing
- `feature/rsm-phase3`: Unified state directory with dual-write migration — `state_dir()` in state-lib.sh provides `state/{phash}/` per-project directories; proof-status, test-status, and session hooks migrated; breadcrumb system retired; 50+ new tests (DEC-RSM-STATEDIR-001)
- `feature/fix-subagent-latency`: Subagent latency remediation — deduplicate dispatch work, cap trace scanning loops, merge token tracking into check-*.sh hooks
- `feature/wave-planning-metrics`: Replace serial phase-based planning with DAG-based wave decomposition — dependency graphs, per-item metrics (Weight, Gate, Deps), initiative-level summary metrics (critical path, max width)

### Fixed
- `fix/ci-sqlite-tests`: Update 4 failing CI tests for SQLite WAL state backend
- `fix/lint-full-coverage`: Extend `--scope lint` from 34 hooks to 97 files (hooks + tests + scripts) matching CI's full shellcheck coverage — 101 total lint tests (#127)
- `fix/shellcheck-directive`: Rename comment to avoid shellcheck directive false positive
- `v3-concurrency-fixes`: Stale markers, proof isolation, workflow scoping
- `fix/125-autoverify-sort`: Fix auto-verify trace discovery — replace `sort -r` (alphabetical) with `ls -t` (mtime-ordered); add ghost trace detection (DEC-AV-GHOST-001)
- `feature/xplatform-reliability`: Portable `_file_mtime()` and `_with_timeout()` wrappers in core-lib.sh — replace 25 inline `stat -f %m` patterns with cross-platform function (DEC-XPLAT-001, DEC-XPLAT-002)
- `feature/xplat-w1b`: Update 10 stale context-lib.sh section names in run-hooks.sh after metanoia decomposition (#120)
- `worktree-test-cleanup`: Test infrastructure cleanup — delete 23 dead test files (~10K lines), fix 12 failing standalones
- `feature/fix-ci-round2`: Fix remaining 4 Ubuntu CI failures
- `feature/fix-ci`: Resolve 15+ CI failures across shellcheck and validate-hooks jobs
- `worktree-fix-test-failures`: Fix remaining test failures — trap stacking, proof-gate markers, lifecycle timeout
- `feature/fix-dispatch-integrity`: Restore dispatch protocol integrity after Task-to-Agent rename
- `feature/proof-sweep-marker-based`: Replace TTL-based proof-status sweep with marker-based ownership check
- `feature/fix-proof-lifecycle`: Proof lifecycle fixes — stable hash resolution (#106); AUTOVERIFY agent_type validation (#4)
- `feature/fix-dispatch-reliability`: Dispatch reliability — CI ask pattern (#107) + per-gate error isolation (#63)
- `feature/fix-housekeeping`: Plan status sync, CHANGELOG dedup, context-lib.sh removal (#65)
- `feature/statusline-cache-scope`: Per-instance statusline cache prevents multi-instance state collision
- `feature/fix-bootstrap-paradox`: CAS failure diagnostic + plan-only bypass (#105)
- `feature/fix-proof-status-accumulation`: Prevent .proof-status-* dotfile accumulation (5 bugs fixed)
- `feature/fix-guardian-double-ask`: Include AUTO-VERIFY-APPROVED in manual approval dispatch
- `feature/fix-prompt-submit-104`: Verification gate silent failure — fast path, CAS locks, breadcrumb notification
- `feature/fix-statusline-bugs`: Terminal width clamping, empty banner, token path bugs
- `feature/fix-zombie-code`: 5-layer zombie code prevention
- `feature/fix-statusline-flicker`: Consolidated 13 jq calls to 1; stable 3-line height
- `feature/fix-wiring-gate-bugs`: 3 integration wiring gate bugs (#101, #102, #103)
- `feature/fix-fd-leak`: Background heartbeat FD inheritance causing 5min test hangs
- `fix/test-health-audit`: Stale test cleanup and CI coverage
- `fix/guardian-perf`: Guardian performance overhaul — fail-fast, merge tiers, duplicate detection, heartbeat ceiling
- `fix/native-lock`: OS-native file locking — `lockf` on macOS, `flock` on Linux; zero external dependencies
- `fix/remediation-silent-failures`: Phase 1 hook cleanup path silent failures
- `fix/flock-macos`: Portable flock(1) for macOS with homebrew discovery and graceful degradation
- `feature/fix-silent-return`: Silent return bug — 73% of agent completions bypassed post-task.sh
- PostToolUse matcher `Task` -> `Task|Agent` — auto-verify hook never fired
- `feature/fix-bootstrap-amendment`: Bootstrap vs amendment flow
- `feature/fix-comment-false-positive`: Strip bash comments from guard analysis (DEC-GUARD-002)
- `feature/autoverify-race-fix`: Auto-verify race condition with `.active-autoverify-*` markers
- `feature/proof-lifecycle`: Proof lifecycle reliability — 11 new tests
- `fix/sigpipe-crashes`: SIGPIPE (exit 141) crashes — 20 pipe patterns replaced; 14-test suite
- `fix/stale-marker-blocking-tester`: Stale `.active-*` marker race condition
- Observatory SUG-ID instability, duration UTC timezone bug
- Guard long-form force-deletion variant detection
- Worktree-remove crash on paths with spaces
- Proof-status path mismatch in git worktree scenarios
- Verification gate: escape hatch, empty-prompt awareness, env whitelist
- Tester AND logic for completeness gate + finalize_trace verification fallback
- Post-compaction amnesia with computed resume directives
- Meta-repo exemption for guard.sh proof-status deletion check
- Hook library race condition during git merge (session-scoped caching)
- Cross-platform stat for Linux CI
- Shellcheck failures: tilde bug + expanded exclusions

### Removed
- `archive/legacy-hooks/` — 17 v2-era hook scripts (4,342 LOC). All functionality consolidated into v3 entry points (pre-bash.sh, pre-write.sh, post-write.sh, stop.sh) during the Metanoia refactor.
- `prds/` — Internal PRDs excluded from public distribution.
- MASTER_PLAN.md moved to `docs/v3-development-history.md` — development history preserved as reference; root cleared for users who fork.

### Security
- Cross-project git guard prevents accidental operations on wrong repositories
- Credential exposure protection via `.env` read deny rules
- SECURITY.md contact email corrected

## [3.0.0] - 2026-03-05

### Fixed
- Proof lifecycle fixes — stable hash resolution (#106); AUTOVERIFY agent_type validation (#4)
- Dispatch reliability — CI ask pattern (#107) + per-gate error isolation (#63)
- Housekeeping — plan status sync, CHANGELOG dedup, context-lib.sh removal (#65)
- Per-instance statusline cache prevents multi-instance state collision
- Bootstrap paradox mitigation — CAS failure diagnostic + plan-only bypass (#105)
- Prevent .proof-status-* dotfile accumulation (5 bugs fixed)
- Statusline term_w clamping, guardian double-ask, verification gate silent failure
- 5-layer zombie code prevention, startup banner flicker, wiring gate bugs
- FD inheritance bug, guardian performance overhaul, OS-native file locking
- Silent return bug — 73% of agent completions bypassed post-task.sh (#158)
- Auto-verify race condition, proof lifecycle reliability, SIGPIPE crashes
- Stale marker race condition, comment false-positive in guard analysis
- Bootstrap vs amendment flow, observatory bugs, worktree-remove crash

### Added
- Dispatch gate, production reliability (macOS CI, shellcheck extension)
- State management consolidation, integration wiring gates
- Responsive statusline, backlog gaps report, backlog scanner
- Statusline banner, subagent token tracking, backlog foundation
- Cross-project state isolation, living plan format tests
- Documentation audit, doc-freshness enforcement, agent quality gates
- Worktree sweep, trace analysis, tester agent, checkpoint system
- CWD recovery, cross-session learning, SDLC integrity layer
- ARCHITECTURE.md comprehensive technical reference

### Changed
- Statusline redesign — two-line HUD with domain clustering
- Living MASTER_PLAN format, shared library consolidation
- Planner create-or-amend workflow, tester agent rewrite
- Session-init performance — 2-10s reduced to 0.3-2s
- Guardian auto-cleans worktrees, GitHub Actions pinned to commit SHAs

### Security
- Cross-project git guard prevents accidental operations on wrong repositories
- Credential exposure protection via `.env` read deny rules

## [2.0.0] - 2026-02-08

### Added
- **Core System Architecture**
  - Three-agent system: Planner, Implementer, Guardian with role separation
  - 20+ deterministic hooks across 8 lifecycle events
  - Worktree-based isolation with main branch protection
  - Test-first enforcement via `test-gate.sh` and proof-of-work verification
  - Documentation requirements via `doc-gate.sh` for 50+ line files

- **Decision Intelligence**
  - `/decide` skill: Interactive decision configurator with HTML wizards
  - Bidirectional decision tracking: `MASTER_PLAN.md` <-> `@decision` annotations in code
  - Plan lifecycle state machine with completed-plan source write protection

- **Research & Context**
  - `deep-research` skill: Multi-model synthesis across research providers
  - `prd` skill: Deep-dive product requirement documents
  - `context-preservation` skill: Structured summaries across compaction

- **Backlog Management**
  - `/backlog` command: Unified todo interface over GitHub Issues
  - Global and project-scoped issue tracking

- **Safety & Enforcement**
  - `guard.sh`: Nuclear deny for destructive commands, transparent rewrites for `/tmp/` -> `tmp/`, `--force` -> `--force-with-lease`
  - `branch-guard.sh`: Blocks source writes on main, enforces worktree workflow
  - `mock-gate.sh`: Prevents internal mocking, allows external boundary mocks only
  - `plan-check.sh`: Requires MASTER_PLAN.md before implementation

- **Session Lifecycle**
  - `session-init.sh`: Git state, plan status, worktrees, todo HUD injection on startup
  - `prompt-submit.sh`: Keyword-based context injection, deferred-work detection
  - `session-summary.sh`: Decision audit, worktree status, forward momentum check

- **Subagent Quality Gates**
  - `check-planner.sh`, `check-implementer.sh`, `check-guardian.sh`
  - Task tracking via `task-track.sh` for subagent state monitoring

- **Testing Infrastructure**
  - Contract tests for all hooks (`tests/run-hooks.sh`)
  - 54/54 passing test suite
  - GitHub Actions CI with shellcheck and contract validation

### Changed
- Promoted 16 safe utilities to global allow list in `settings.json`
- Professionalized repository structure with issue templates

### Fixed
- Inlined update-check into session-init to eliminate startup race condition
- Guardian bypass via git global flags
- Test harness subshell bug that silently swallowed failures
- CWD-deletion ENOENT in Stop hooks

### Security
- Cross-project git guard prevents accidental operations on wrong repositories
- Credential exposure protection via `.env` read deny rules
- Hook input sanitization via `log.sh` shared library

[3.1.0]: https://github.com/juanandresgs/claude-ctrl/compare/v3.0.0...v3.1.0
[3.0.0]: https://github.com/juanandresgs/claude-ctrl/compare/v2.0.0...v3.0.0
[2.0.0]: https://github.com/juanandresgs/claude-ctrl/releases/tag/v2.0.0
