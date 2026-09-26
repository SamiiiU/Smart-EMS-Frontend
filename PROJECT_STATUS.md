# Project Status

| Task | Depends on | Status | Gate result | Date |
|------|------------|--------|--------------|------|
| T0 — Project setup | — | Done | 9/11 pass; APK build and PostToolUse hook deferred to blockers (see below) | 2026-07-30 |
| T1 — Tokens and theme | T0 | Done | 8/8 pass — see HANDOFF.md T1 | 2026-07-30 |
| T2 — Primitives | T1 | Done | 8/8 pass — see HANDOFF.md T2 | 2026-07-30 |
| T3 — Composites | T2 | Done | 11/11 pass — see HANDOFF.md T3 | 2026-07-30 |
| T4 — Global states | T3 | Done | 7/7 pass — see HANDOFF.md T4 | 2026-07-30 |
| T5 — Shell and navigation | T4 | Done | 216/216 tests pass (171 baseline + 45 new); analyze clean; check_tokens.sh clean + negative test; APK re-verified — see HANDOFF.md | 2026-08-01 |
| T6 — Network layer | T5 | Done | 232/232 tests pass (216 baseline + 16 new); analyze clean; check_tokens.sh clean + negative test; CORS blocker found + fixed live mid-task — see HANDOFF.md | 2026-08-03 |
| T7 — Auth | T0–T6 | Done | 251/251 tests pass; analyze clean; endpoints CONFIRMED via public OpenAPI; real account created + logged in end-to-end; JWT claims verified (D-41). Found/fixed 2 latent T6 auth bugs + 1 T2 primitive bug — see HANDOFF.md | 2026-08-03 |
| T8 — Teacher today + Attendance marking | T7 | **Done** | 312/312 tests pass, analyze clean. Today fully navigable after Ali's 2026-08-10 `sectionId` fix; timetable camelCase migration done; institution name + `forcePasswordChange` flow wired. Section picker removed. Fixed a latent paint-time crash in the Today card | 2026-08-10 |
| T9 — Parent landing + Child attendance | T7 | **Done** | 363/363 tests pass, analyze clean. Endpoints live-verified as a real parent; orphan case wired (closes T7 gap). Found+fixed unmapped DioException that silently broke the D-17 path. Multi-child mock-verified only — write API cannot create it (Ali) | 2026-08-11 |
| T10 — Admin onboarding | T7 | **Done** | Admin shell wired (was falling through to teacher). 381 tests. Post-gate fix: campus list parse (Add user). Dashboard (D-15/D-14), students list+profile, create-user wizard (D-17 resume), CSV import (sync, per-row errors). 18 new tests. Endpoints live-verified on local backend. Open: file_picker, multi-campus, no classes/sections UI | 2026-09-18 |
| T11 — Remaining Tier 1 screens | T7 | **Done** (student held) | Diary edit-first (PUT/POST asserted both ways, full-replace guard, 409 race error, shared-entry strip). Student Today/Timetable held at "not available yet" — backend gives a student no sectionId (Ali). Fixed: student login fell through to teacher shell. Added offline state via LoadFailure.unreachable (T8–T10 still lack it) | 2026-09-18 |
| T12 — Acceptance pass | T7–T11 | Not started | — | — |
| UI fixes from manual testing | — | **Done** | 421 tests. Debug banner off; Appearance (System/Light/Dark) in More; new admin **Accounts** tab (staff/students/parents + has-login); sign-out on orphan/error screens; phone "More" is a real list; desktop sync chip; CSV header checked client-side. Backend has NO endpoint listing logins (Ali) | 2026-09-23 |
| T13 Batch A — Academic setup | T11 | **Done** | Six screens under a Setup hub: years, classes, sections, subjects, teaching assignments, timetable (grid ≥768px, day list below). D-14 checklist step 1 now live. Add-only assignments, no delete buttons (backend orphans data). Live E2E through the repository passes. 21 new tests | 2026-09-24 |
| T14 Batch B - Finance | T13 Batch A | **Done** | Fee heads, plans, bulk generation, invoice list + detail, record payment, approvals queue, receipt, defaulters, collection report - under a Fees hub. Money is integer paisa end to end (never a double); response text is rewritten before decoding because the API sends bare JSON numbers. No correction affordances anywhere: this backend cannot reverse a payment or cancel an invoice. Live E2E through the repository passes. 68 new tests | 2026-09-25 |
| T15 Batch C - Academic loop | T13 Batch A | **Done** | Exams, papers, marks entry (attendance ergonomics, 40-student budget), results, report card, remarks, syllabus coverage - under an Academics hub. Marks are integer hundredths end to end. Grade schemes and subject resources have NO backend and ship as screens that say so. Publishing locks marks permanently. Student remark access is a privacy defect raised to Ali. Live E2E through the repository passes. 71 new tests | 2026-09-25 |
| T16 Batch D - Operations | T15 Batch C | **Done** | Complaints (raise/mine/admin worklist/detail with assign+resolve), notifications centre + the app-bar bell wired at last, staff attendance, parent-progress completion, CSV file picker, admin phone drawer. Internal comments and anonymity are server-enforced and proven live across two accounts. A parent cannot raise a complaint (no campusId reachable) - blocked with an explanation. integration_test set up but NOT yet run - no driver on this machine. 55 new tests | 2026-09-27 |

## Open blockers

1. **`flutter build apk --debug`** — ✅ resolved (portable JDK 17 +
   `kotlin.incremental=false`); re-verified green again for T5.
2. **PostToolUse hook not live** — still open, waived for T5 by explicit
   instruction (see HANDOFF.md). `.claude/settings.json` is correct and
   independently verified, but the settings watcher never picked it up this
   session.

**Until the hook is live, `bash tool/check_tokens.sh` must be run manually
after every file change (not just at the end of a task). It is part of the
Definition of Done.**
