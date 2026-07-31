---
name: task-gate
description: Definition of Done procedure — runs each acceptance check for the current task and reports per-checkbox with real command output.
disable-model-invocation: true
---

# Task Gate

Run this at the end of any T-numbered task, before reporting it as done.

## Procedure

1. Read the current task's Definition of Done checklist (from the task
   prompt or `PROJECT_STATUS.md`).
2. For every checkbox, actually run the command it names. Do not infer,
   assume, or recall a result from earlier in the conversation — run it
   again, fresh, right now.
3. Report one line per checkbox: the checkbox text, PASS or FAIL, and the
   real command output (or a representative excerpt for long output).
   Never collapse this into a prose summary like "all checks passed" —
   the reader must be able to see what actually ran.
4. For any negative test (a check that is supposed to fail), show both
   the failing output and the passing output after the fix/removal. A
   negative test that was never triggered counts as FAIL for that
   checkbox, not as skipped.
5. If a checkbox cannot be run (missing tool, missing credential, out of
   scope), mark it FAIL / BLOCKED and say why — never mark it as passed.
6. Do not proceed to mark the task complete in `PROJECT_STATUS.md` until
   every checkbox has a real, shown result.

**Never claim a pass you did not run.** A gate that reports success
without executing the check is worse than no gate — it manufactures
false confidence.

## Standing checklist for every component task

Applies from T4 onward, in addition to the task's own Definition of Done.

### Accessibility paths need EXPLICIT tests

**Nobody exercises these by accident.** They are never the default path, so a
break in them is invisible in normal testing and ships.

This is not hypothetical. T4's shimmer crashed **only** for reduced-motion
users: the `AnimationController` was a lazy `late final`, so under reduced
motion the first access was `dispose()`, which constructed it during unmount
and threw on an ancestor lookup. An accessibility feature that broke for
exactly the people who requested accessibility, and it would have shipped.

Every component task must test:

- [ ] **Reduced motion** — `MediaQuery.disableAnimations`. Animations stop,
      and the component still renders (static, not absent).
- [ ] **Large text scale** — `MediaQuery.textScaler`. No overflow, nothing
      clipped, tap targets still ≥ 44px.
- [ ] **RTL** — `Directionality(textDirection: TextDirection.rtl)`. Layout
      mirrors; leading/trailing do not swap meaning.
- [ ] **Screen reader** — `Semantics` labels exist and say something useful;
      decorative shapes are excluded.

### A test that silently tests nothing is worse than no test

It produces false confidence. T4 also produced one: a reduced-motion test that
wrapped `MediaQuery` **outside** `MaterialApp` — which does nothing, because
`MaterialApp` inserts its own from the view. It passed while testing nothing.

So: when a test asserts an ABSENCE (no shimmer, no danger colour, no button),
first prove the test can FAIL. Assert the positive case alongside it — e.g.
"OfflineState uses no danger token" is meaningless unless "ErrorState DOES use
danger" also passes.

### Contrast

- [ ] Any NEW colour pairing is added to `test/contrast_test.dart`.
      Contrast is invisible to widget tests and to goldens — three real
      failures shipped through a green suite before that file existed.

### Layout

- [ ] No overflow at **360 / 768 / 1366px**.
