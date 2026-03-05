# Dispatch Protocol

<!--
@decision DEC-DISPATCH-EXTRACT-001
@title Extract dispatch protocol from CLAUDE.md to docs/DISPATCH.md
@status accepted
@rationale The dispatch protocol section (~115 lines) loaded every session in CLAUDE.md
  but is only needed when agent dispatch is imminent. Extracting it to docs/DISPATCH.md
  reduces per-session token load while keeping the full protocol accessible on demand.
  CLAUDE.md retains a compact reference with the always-needed key rules.
-->

This file contains the full agent dispatch protocol for the Claude Code meta-infrastructure.
Referenced from `CLAUDE.md` — read when orchestrating agent dispatch or understanding routing rules.

## Agent Dispatch Table

The orchestrator dispatches to specialized agents — it does NOT write source code directly.

| Task | Agent | Orchestrator May? |
|------|-------|--------------------|
| Planning, architecture | **Planner** | No Write/Edit for source |
| Implementation, tests | **Implementer** | No — must invoke implementer. Auto-flow mode: implementer dispatches tester + guardian internally when `CYCLE_MODE: auto-flow` is set. |
| E2E verification, demos | **Tester** | No — must invoke tester |
| Commits, merges, branches | **Guardian** | No git commit/merge/push/branch -d/-D |
| Worktree creation (bootstrap) | Orchestrator | Yes — `git worktree add` before implementer dispatch |
| Research, reading code | Orchestrator / Explore | Read/Grep/Glob only |
| Post-guardian health check | Orchestrator | Invoke `/diagnose` when check-guardian.sh suggests it |
| Editing `~/.claude/` config | Orchestrator | Trivial edits only (gitignore, 1-line, typos). Features use worktrees. |

**Planner creates or amends the plan:** When MASTER_PLAN.md exists with `## Identity`, the Planner adds a new `### Initiative:` block rather than overwriting. When it does not exist, Planner creates the full living-document structure. Never dispatch Planner to replace an existing plan — dispatch to extend it.

Agents are interactive — they handle the full approval cycle (present → approve → execute → confirm). If an agent exits after asking approval, wait for user response, then resume with "The user approved. Proceed."

## Plan-to-Implementation Routing

Detection: `git ls-files --error-unmatch MASTER_PLAN.md` (exit 0 = tracked = amendment flow)

**Bootstrap** (MASTER_PLAN.md not yet tracked in git — sequential, never parallelize):
1. Dispatch **Planner** → creates MASTER_PLAN.md on main (Workflow A)
2. Dispatch **Guardian** → commits MASTER_PLAN.md to main (allowed because plan is untracked)
3. **Orchestrator** creates worktree: `git worktree add .worktrees/<phase> -b feature/<phase>`
4. Dispatch **Implementer** → works inside the worktree

**Amendment** (MASTER_PLAN.md already tracked in git):
1. **Orchestrator** creates worktree: `git worktree add .worktrees/<initiative> -b feature/<initiative>`
2. Dispatch **Planner** into the worktree → amends MASTER_PLAN.md there (Workflow B), creates issues
3. Dispatch **Implementer** into the same worktree → implements code
4. Dispatch **Tester** → verifies
5. Dispatch **Guardian** → merges worktree to main (plan amendment + code in a single approval)

The orchestrator owns worktree creation because it is infrastructure, not source code.
Gate C.1 in task-track.sh requires at least one non-main worktree before implementer dispatch.

## Auto-Flow vs Phase-Boundary Routing

- Routine work items (not completing a phase): dispatch implementer with `CYCLE_MODE: auto-flow` — it owns the full cycle (implement → test → verify → commit)
- Phase-completing work items: dispatch implementer with `CYCLE_MODE: phase-boundary` — orchestrator handles tester + user review + guardian
- When in doubt, use `phase-boundary` (conservative default)

**Auto-dispatch to Guardian:** When work is ready for commit, invoke Guardian directly with full context (files, issue numbers, push intent). Do NOT ask "should I commit?" before dispatching. Do NOT ask "want me to push?" after Guardian returns. Guardian owns the entire approval cycle — one user approval covers stage → commit → close → push.

**Decision Configurator Auto-Dispatch:** The Planner may invoke `/decide` during Phase 2 when 3+ architectural decisions have meaningful trade-offs. This is part of the Planner's workflow — the orchestrator doesn't separately dispatch `/decide`. If the Planner asks for guidance on a multi-option trade-off, suggest: "Consider `/decide plan` to let the user explore options interactively."

**Auto-dispatch to Tester:** After the implementer returns successfully (tests pass, no blocking issues), dispatch the tester automatically with the implementer's trace context. Do NOT ask "should I verify?" — just dispatch the tester.

**After tester returns:** Present the tester's full verification report to the user, including the Verification Assessment. Do NOT summarize it into a keyword demand. Engage in Q&A about the evidence. When the user expresses approval, prompt-submit.sh handles the gate transition automatically.

## Auto-Verify Fast Path

When post-task.sh detects `AUTOVERIFY: CLEAN` with High confidence, full coverage, and no caveats, it auto-writes `.proof-status = verified` and emits `AUTO-VERIFIED` in a system-reminder.

When the orchestrator receives this system-reminder:
1. Dispatch Guardian with `AUTO-VERIFY-APPROVED` in the prompt — this tells
   Guardian to skip its approval presentation and execute the merge cycle directly.
2. Present the tester's verification report to the user in the same response
   (user sees evidence while commit is in flight).
3. Do NOT wait for user approval before dispatching — the auto-verify IS the approval.

If auto-verify doesn't trigger, the manual flow applies: present the tester's
report, engage in Q&A, user approval triggers prompt-submit.sh gate transition.

**After implementer returns with CYCLE COMPLETE:** Do NOT dispatch tester or guardian — the implementer already completed the full cycle. Present the implementer's summary to the user. post-task.sh emits the "CYCLE COMPLETE" directive automatically when it detects this condition in the implementer's trace summary.

## Pre-Dispatch Gates (Mechanically Enforced)

- Tester dispatch: requires implementer to have returned with tests passing
- Guardian dispatch: requires `.proof-status = verified` when file exists (PreToolUse:Task gate in task-track.sh). Missing file = no gate (bootstrap path — implementer dispatch activates the gate by writing `needs-verification`)
- The user's approval (verified, approved, lgtm, looks good, ship it) triggers `.proof-status = verified` via prompt-submit.sh — no agent can write it

## Trace and Recovery Protocols

**Trace Protocol:** Agents write evidence to disk (TRACE_DIR/artifacts/) and return a cohesive summary of their work (aim for 200-500 tokens). Read TRACE_DIR/summary.md for full details on demand.

**Silent Return Recovery:** When an agent returns with no visible content, check-*.sh Layer A reads `$TRACE_DIR/summary.md` and injects its content directly into additionalContext (labeled "SILENT RETURN DETECTED"). Agents write summary.md incrementally after each phase, so the last-written version is always available. Act on the injected content — do NOT ask the user to investigate. If additionalContext says "no trace summary available", read the latest trace directly: `ls -t traces/<agent-type>-*/summary.md | head -1`.

**Session Acclimation:** MASTER_PLAN.md's `## Identity` and active initiative sections are
auto-injected at session start (bounded to ~200 lines regardless of plan age). This provides
project identity, architecture, and active work context. Development log digest (recent traces)
shows what agents did recently. Failed/crashed trace summaries are auto-injected — act on them
without prompting. When the task touches unfamiliar areas, read relevant files from the Resources table.

## Turn Budgets and Dispatch Sizing

**max_turns enforcement:** Every Task invocation MUST include max_turns.
- Implementer: max_turns=85
- Planner: max_turns=65
- Tester: max_turns=40
- Guardian: max_turns=35

Sub-agents dispatched from within an auto-flow implementer get their own budgets (tester: 40, guardian: 30). These do not consume the implementer's 85-turn budget.

**Implementer dispatch sizing:**
- Phases with 1–3 work items: dispatch all in one implementer call
- Phases with 4+ work items: split into multiple dispatches (group related items, max 3 per dispatch)
- Include a scope note in every dispatch prompt: "Budget: 85 turns. Scope: [N work items, M files]."
- If implementer returns PARTIAL (summary.md says work remains), re-dispatch for remaining items immediately without asking the user

## Task Interruption Protocol

When you receive a new task while agents from a previous dispatch are still running (system-reminder will show "ACTIVE AGENTS from previous dispatch"):

1. **Acknowledge** the active work — name the agent type and what it was doing
2. **Assess** both tasks — is the new task urgent? Is the old task near completion?
3. **Present options** via AskUserQuestion (never silently pivot):

| Option | When | What happens |
|--------|------|--------------|
| **Pivot** | Unrelated tasks (default) | Create `/backlog` issue with interrupted context (trace summary, branch, what remains), then proceed with new task. Non-optional — interrupted work MUST be captured. |
| **Queue** | Old task near completion | Finish old task first, then start new |
| **Parallel** | Old agent in final stage (tester/guardian) | Let old finish in background, start read-only exploration of new task. Never dispatch a second implementer. |
| **Merge** | Tasks overlap | Incorporate new requirements when current agent returns |

Two exceptions bypass AskUserQuestion:
- **Trivial tasks** (research, status checks, questions) that don't need agent dispatch — just answer and resume
- **Explicit cancellation** ("drop that", "forget it", "start fresh") — treat as Pivot, still MUST `/backlog` before proceeding
