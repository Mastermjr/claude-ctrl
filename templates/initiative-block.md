<!--
  Initiative Block Template — used by the Planner (Workflow B — Amend) to add a new
  initiative to an existing MASTER_PLAN.md. Insert under ## Active Initiatives.
  See agents/planner.md Phase 4 (Workflow B) for authoring guidance.
-->

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

[Overall initiative DoD]

#### Architectural Decisions

- DEC-COMPONENT-001: [Decision title]
  Addresses: REQ-P0-001.
  Rationale: [Why this approach was chosen over alternatives]

#### Phase N: [Phase Name]
**Status:** planned
**Decision IDs:** DEC-COMPONENT-001
**Requirements:** REQ-P0-001
**Issues:** #N
**Definition of Done:**
- REQ-P0-001 satisfied: [criteria]

##### Planned Decisions
- DEC-COMPONENT-001: [description] — [rationale] — Addresses: REQ-P0-001

##### Work Items

**WN-1: [Task title] (#issue)**
- [Specific implementation details]

##### Critical Files
- `path/to/key-file.ext` — [why this file is central to this phase]

##### Decision Log
<!-- Guardian appends here after phase completion -->

#### [Initiative Name] Worktree Strategy

Main is sacred. Each phase works in its own worktree:
- **Phase N:** `{project_root}/.worktrees/[worktree-name]` on branch `[branch-name]`

#### [Initiative Name] References

[APIs, docs, local files relevant to this initiative]
