# Project Status

| Task | Depends on | Status | Gate result | Date |
|------|------------|--------|--------------|------|
| T0 — Project setup | — | Done | 9/11 pass; APK build and PostToolUse hook deferred to blockers (see below) | 2026-07-30 |
| T1 — Tokens and theme | T0 | Done | 8/8 pass — see HANDOFF.md T1 | 2026-07-30 |
| T2 — Primitives | T1 | Done | 8/8 pass — see HANDOFF.md T2 | 2026-07-30 |
| T3 — Composites | T2 | Done | 11/11 pass — see HANDOFF.md T3 | 2026-07-30 |
| T4 — Global states | T3 | Done | 7/7 pass — see HANDOFF.md T4 | 2026-07-30 |
| T5 — Shell and navigation | T4 | Not started | — | — |
| T6 — Network layer | T5 | Not started | — | — |
| T7 — Auth | T0–T6 | Not started | — | — |
| T8 — Teacher today + Attendance marking | T7 | Not started | — | — |
| T9 — Parent landing + Child attendance | T7 | Not started | — | — |
| T10 — Admin onboarding | T7 | Not started | — | — |
| T11 — Remaining Tier 1 screens | T7 | Not started | — | — |
| T12 — Acceptance pass | T7–T11 | Not started | — | — |

## Open blockers

Both of the following are **open** and **must be resolved before T5**, not
before T1:

1. **`flutter build apk --debug` fails** — no JDK on this machine
   (`JAVA_HOME`/`java` not found) and the Android SDK is missing its
   `cmdline-tools` component. One-time machine setup.
2. **PostToolUse hook not live** — `.claude/settings.json` is correct and
   independently verified, but the settings watcher never picked it up
   this session. Negative Test C is **blocked**, not failed.

**Until the hook is live, `bash tool/check_tokens.sh` must be run manually
from `frontend/` at the end of every task. It is part of the Definition of
Done.**
