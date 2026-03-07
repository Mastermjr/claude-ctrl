# Shared Agent Protocols

<!--
@decision DEC-PROMPT-002
@title Extract shared defensive protocols into shared-protocols.md
@status accepted
@rationale CWD safety, trace protocol, and return message rules were duplicated
  verbatim across implementer.md, tester.md, guardian.md, and planner.md.
  Extracting them here and injecting via subagent-start.sh means a single edit
  propagates to all agents. Economy matters — injected into every non-lightweight
  agent's context, so it stays under 3000 bytes.
-->

Applied to all agents (implementer, tester, guardian, planner) at spawn time.

---

## CWD Safety Rules

Never use bare `cd` into worktree directories. guard.sh denies all
`cd .worktrees/` commands. Violations brick the shell's CWD for the
rest of the session — all subsequent Bash operations return ENOENT.

Safe patterns:
- Git commands: `git -C .worktrees/<name> <command>`
- Other commands: `(cd .worktrees/<name> && <command>)` — subshell only

Before deleting any directory, ensure the shell is NOT inside it.
Use `safe_cleanup` from context-lib.sh or `cd <project_root>` first:

```bash
source ~/.claude/hooks/context-lib.sh
safe_cleanup "/absolute/path/to/dir" "$PROJECT_ROOT"
```

Deleting the shell's CWD bricks all Bash operations for the rest of
the session. Unrecoverable without `/clear`.

---

## Trace Protocol

When `TRACE_DIR` appears in your startup context:

1. Write verbose output to `$TRACE_DIR/artifacts/` as you work:
   - implementer: `test-output.txt`, `diff.patch`, `files-changed.txt`
   - tester: `verification-output.txt`, `verification-strategy.txt`
   - guardian: `merge-analysis.md`
   - planner: `analysis.md`, `decisions.json`

2. Write incremental `$TRACE_DIR/summary.md` after each major phase:
   - Status: `"IN-PROGRESS: Phase N complete, Phase M next"`
   - Ensures any interruption has recoverable context.

3. Write final `$TRACE_DIR/summary.md` before returning — include:
   status, files changed, key outcomes, test results, next steps.

4. If running low on turns: stop, write summary.md, return immediately.
   An incomplete implementation with a good summary is recoverable.

---

## Mandatory Return Message

Your LAST action before completing MUST be producing a text message.
Never end on a bare tool call — the orchestrator only sees your final
text, not tool results.

Structure your return message as:
1. What was done (files changed, operation performed)
2. Key outcomes (test results, commit hash, worktree path, branch)
3. Any issues or blockers encountered
4. Next steps for the orchestrator
5. `Full trace: $TRACE_DIR` (if TRACE_DIR is set)

Keep it under 1500 tokens. This is not optional.

---

## Session End Checklist

Before completing, verify:
- [ ] `$TRACE_DIR/summary.md` written (if TRACE_DIR is set)
- [ ] Final text return message produced (not ending on a tool call)
- [ ] Worktree clean — no uncommitted changes (implementer)
- [ ] Lockfile removed: `rm -f .worktrees/<name>/.claude-active` (implementer)
- [ ] Tests pass (implementer) or verification complete (tester)
