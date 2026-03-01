# MASTER_PLAN.md Template Reference

<!--
@decision DEC-PLAN-TMPL-001
@title Extracted template for MASTER_PLAN.md generation
@status accepted
@rationale Separates the document specification (this file) from agent instructions (planner.md).
The planner reads this at runtime during Phase 4. Reduces planner.md by ~140 lines and makes
the template independently maintainable.
-->

This file is read by the planner agent during Phase 4 (MASTER_PLAN.md Generation).
It defines the document structure for both workflows.

## Workflow A — Full Document Structure

Produce this structure at the project root when no MASTER_PLAN.md exists.

```markdown
# MASTER_PLAN: [Project Name]

## Identity

**Type:** [meta-infrastructure | web-app | CLI | library | API | ...]
**Languages:** [primary (X%), secondary (Y%), ...]
**Root:** [absolute path]
**Created:** [YYYY-MM-DD]
**Last updated:** [YYYY-MM-DD]

[2-3 sentence description of what this project is and what it does]

## Architecture

  dir1/    — [role, 1 line]
  dir2/    — [role, 1 line]
  dir3/    — [role, 1 line]
[Key directories and their roles — 1 line per directory, only meaningful dirs]

## Original Intent

> [Verbatim user request, as sacred text — quoted block]

## Principles

These are the project's enduring design principles. They do not change between initiatives.

1. **[Principle Name]** — [Description]
2. **[Principle Name]** — [Description]
[3-5 principles that will guide all future work]

---

## Decision Log

Append-only record of significant decisions across all initiatives. Each entry references
the initiative and decision ID. This log persists across initiative boundaries — it is the
project's institutional memory.

| Date | DEC-ID | Initiative | Decision | Rationale |
|------|--------|-----------|----------|-----------|
| [YYYY-MM-DD] | DEC-COMPONENT-001 | [initiative-slug] | [Decision title] | [Brief rationale] |

---

## Active Initiatives

[Insert initiative block here — see Initiative Block Template below]

---

## Completed Initiatives

| Initiative | Period | Phases | Key Decisions | Archived |
|-----------|--------|--------|---------------|----------|
[Empty at project start — Guardian/compress_initiative() appends when initiatives complete]

---

## Parked Issues

Issues not belonging to any active initiative. Tracked for future consideration.

| Issue | Description | Reason Parked |
|-------|-------------|---------------|
[Empty at project start]
```

## Initiative Block Template

Used by both Workflow A (first initiative in new document) and Workflow B (new initiative added to existing document).

```markdown
### Initiative: [Initiative Name]
**Status:** active
**Started:** [YYYY-MM-DD]
**Goal:** [One-sentence goal]

> [2-4 sentence narrative: what problem this initiative solves and why now]

**Dominant Constraint:** [reliability | security | performance | maintainability | simplicity | balanced]

#### Goals
- REQ-GOAL-001: [Measurable outcome]
- REQ-GOAL-002: [Measurable outcome]

#### Non-Goals
- REQ-NOGO-001: [Exclusion] — [why excluded]
- REQ-NOGO-002: [Exclusion] — [why excluded]

#### Requirements

**Must-Have (P0)**

- REQ-P0-001: [Requirement]
  Acceptance: Given [context], When [action], Then [outcome]

**Nice-to-Have (P1)**

- REQ-P1-001: [Requirement]

**Future Consideration (P2)**

- REQ-P2-001: [Requirement — design to support later]

#### Definition of Done

[Overall initiative DoD — what does "done" mean for this initiative?]

#### Architectural Decisions

- DEC-COMPONENT-001: [Decision title]
  Addresses: REQ-P0-001.
  Rationale: [Why this approach was chosen over alternatives]

#### Phase N: [Phase Name]
**Status:** planned
**Decision IDs:** DEC-COMPONENT-001
**Requirements:** REQ-P0-001, REQ-P0-002
**Issues:** #1, #2
**Definition of Done:**
- REQ-P0-001 satisfied: [criteria]

##### Planned Decisions
- DEC-COMPONENT-001: [description] — [rationale] — Addresses: REQ-P0-001

##### Work Items

**WN-1: [Task title] (#issue)**
- [Specific implementation details]
- [File locations, line numbers if known]

##### Critical Files
- `path/to/key-file.ext` — [why this file is central to this phase]

##### Decision Log
<!-- Guardian appends here after phase completion -->

#### [Initiative Name] Worktree Strategy

Main is sacred. Each phase works in its own worktree:
- **Phase N:** `{project_root}/.worktrees/[worktree-name]` on branch `[branch-name]`

#### [Initiative Name] References

[APIs, docs, local files relevant to this initiative]
```

## Workflow B — Amendment Rules

When adding an initiative to an existing MASTER_PLAN.md:

1. Insert the Initiative Block Template under `## Active Initiatives` (before the closing `---`)
2. Append one row per new decision to the `## Decision Log` table:
   ```
   | [YYYY-MM-DD] | DEC-COMPONENT-001 | [initiative-slug] | [Decision title] | [Brief rationale] |
   ```
3. Do NOT modify permanent sections (`## Identity`, `## Architecture`, `## Principles`)
4. Do NOT modify other active initiatives
5. Do NOT remove rows from `## Decision Log`

## Format Rules

- **Header levels**: `##` for top-level document sections, `###` for initiatives under `## Active Initiatives`, `####` for initiative sub-sections (Goals, Requirements, Architectural Decisions, Phase headers), `#####` for phase sub-sections (Planned Decisions, Work Items, Critical Files, Decision Log)
- **Pre-assign Decision IDs**: Every significant decision gets a `DEC-COMPONENT-NNN` ID in the plan. Implementers use these exact IDs in their `@decision` code annotations.
- **REQ-ID traceability**: DEC-IDs include `Addresses: REQ-xxx` to link decisions to requirements. Phase DoD fields reference which REQ-IDs are satisfied.
- **Status field is mandatory**: Every phase starts as `planned`. Guardian updates to `in-progress` when work begins and `completed` after merge approval.
- **Phase Decision Log is Guardian-maintained**: Phase `##### Decision Log` sections start empty. Guardian appends after each phase completion.
- **Top-level `## Decision Log` is append-only**: Add new rows at the bottom. Never edit or remove existing rows.
