---
name: context-sync
description: Procedure for updating DECISIONS.md, PROJECT_STATUS.md, and HANDOFF.md at the end of a task.
disable-model-invocation: true
---

# Context Sync

Run this at the end of any T-numbered task, after `task-gate` has
produced real gate results.

## Procedure

1. **DECISIONS.md** — append (never remove or rewrite prior entries)
   any decision made during this task that wasn't already specified in
   the prompt, under a `### T<n> — <date>` heading. Include the reasoning
   given, not just the outcome. If no such decision was made, do not add
   an entry.
2. **PROJECT_STATUS.md** — update this task's row: `Status` (In progress
   / Done / Blocked), `Gate result` (short pointer to the HANDOFF.md gate
   section, e.g. "see HANDOFF.md T0"), and `Date`. Do not mark a task
   Done unless `task-gate` reported every checkbox as PASS.
3. **HANDOFF.md** — **overwrite the entire file**, never append. Use the
   fixed format:
   - `# Handoff — T<n> (<date>)`
   - `## What was built`
   - `## Gate result` (every checkbox, PASS/FAIL, real output)
   - `## Decisions made`
   - `## Deviations from the prompt`
   - `## Blocked / needs a human`
   - `## Next task readiness`

   Every section must be present even when the answer is "none" — an
   omitted section reads as unreviewed, not as empty.
