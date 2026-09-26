# Handoff — current state (2026-09-27)

**T0–T16 are done. Every feature batch has shipped.** T12 is deferred; T17
is the acceptance pass over the whole surface and needs its own prompt.

Per-task history is in `PROJECT_STATUS.md`, `DECISIONS.md` and
`BACKEND_CONTRACT.md`. This file is only what the next session needs.

| | |
|---|---|
| Tests | **671** passing, 4 skipped (the four live tests, by design) · analyze clean · `check_tokens.sh` clean with a planted negative |
| Backend | **local** — `http://localhost:8080` (Railway is dead) |
| Test accounts | `admin`, `teacher1`, `parent1`, `student1` — all `Test1234!`, institution `test-school` |

---

# 0. Two things to read before anything else

## 0a. 🔴 The privacy defect that is still open (T15)

**A student can read any student's remarks, including ones a teacher marked
not-parent-visible.** The student path has neither a visibility filter nor
an ownership check; parents are correctly filtered AND scoped.

The remarks screen ships because the flag works for its named audience, its
copy says **"not shown to parents"** and never "private", nothing is
filtered client-side, and **no student-facing remarks surface exists**.
Open item 23 — still the first thing on Ali's list.

## 0b. ⚠️ `integration_test` is written but has NOT been run

`integration_test/app_smoke_test.dart` exists, analyzes clean and is scoped
as agreed — sign in, load a screen, perform a write, against the real
backend. **It has never been executed.** This machine has no Windows
desktop project, no Android device, and no `chromedriver` for the web path.

To run it:

```
# Web — the target this product ships to. Port 3000 only (CORS).
choco install chromedriver      # or match your Chrome build manually
chromedriver --port=4444
cd frontend && flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/app_smoke_test.dart \
  -d chrome --browser-name=chrome

# Android — no driver needed with a device or emulator attached
flutter test integration_test/app_smoke_test.dart
```

Until that runs, the "no terminal" claim still rests on repository-level
proof plus a manual pass, exactly as it did for T13–T15.

---

# 1. Polish pass (2026-09-27)

Consistency only — **no new data, no new endpoints, no placeholder became a
working control.** Full detail in DECISIONS.md.

- Sidebar and phone drawer **grouped** (Overview / School / Operations /
  People), mirroring the hubs. Grouping is presentational and cannot shift
  `selectedIndex`; the compact rail shows no headings.
- **Admin dashboard**: subtitle added like the hubs, KPI row stacks below
  600px, and the section heading now follows the data instead of claiming
  attention is needed when none is.
- **Empty-state copy**: eight dead ends ("Nothing could be loaded.") brought
  into the voice the other thirty already used.
- **Goldens regenerated: none.** An ungrouped list renders byte-identically,
  which is the property the grouping was designed around; a test pins it.
- 🔴 **`check_tokens.sh` had a hole** — multi-line `EdgeInsets` were
  invisible to it. Found by planting a negative. Fixed, and it immediately
  caught two real violations in T15/T16 code. `AppSpacing.none` added so the
  rule needs no "except zero" exception.

**Not done, deliberately:** no analytics, charts or owner dashboard. There
is no analytics backend and no schema, so any chart would show invented
numbers — which would undo exactly what the 27 placeholders protect.

---

# 2. T16 Batch D — what shipped

| Screen | Where | Notes |
|---|---|---|
| Raise a complaint | teacher, student | Anonymity states its cost before the choice |
| My complaints | all roles | Unresolved first (D-15) |
| Complaints worklist | admin | Overdue → unassigned → open → finished |
| Complaint detail | all roles | Assign, resolve, internal notes for staff |
| Notifications | all roles | Grouped by category, unread first |
| Staff attendance | admin | Roll-call ergonomics, its own vocabulary |
| Parent progress | parent | The fields T9 left unread |
| CSV import | admin | File picker, paste still works |
| Phone drawer | admin | D-27 amendment |

New tests: `complaints_test.dart` (25), `operations_test.dart` (23),
7 added to `parent_test.dart`, plus `e2e_complaints_live_test.dart`.

## The backend got the privacy model RIGHT here

Verified with real tokens per role, which is the only way to check it:

- a complainant **never receives** an `is_internal` comment — filtered
  server-side;
- a complainant sending `isInternal: true` has it **downgraded** by the
  server;
- an anonymous complaint stores **no** `raised_by_user_id`, including in the
  admin's own detail view;
- cross-user reads are 404, and a non-admin listing all is 403.

So internal comments ship, and the UI **labels a guarantee rather than
creating one**. Nothing is filtered on the device — that would hide a server
regression, which is precisely what T15 showed to be unreliable.

The live test asserts the leak-proofing across two accounts:

```
flutter test test/e2e_complaints_live_test.dart --dart-define=LIVE=true
```

## 🔴 A parent cannot raise a complaint

`POST /api/complaints` requires `campusId`, the server will not default it,
and **no endpoint a parent may call carries one** — `/api/campuses` is 403,
`/api/guardians/me` and `/api/institution/me` have none. Teacher and student
resolve it from `/api/staff/me` and `/api/students/me`.

`ComplaintsRepository.resolveCampusId()` returns null for a parent and the
screen explains it instead of offering a form that cannot submit. Their
existing complaints still list. Open item 39.

## Staff attendance has its own vocabulary

| Students | Staff |
|---|---|
| present, absent, late, leave, **excused** | present, absent, late, leave, **half_day** |

Four of five shared, which is exactly why one enum would have compiled and
then sent an invalid status. `AppStatus.halfDay` was added to the pill with
letter `H` on a half-filled circle — D-21 requires the (shape + letter)
PAIR to be unique, and Present/Leave already share a shape. Goldens
regenerated; the distinguishability test now asserts against the number of
statuses rather than a literal.

---

# 3. Standing rule — missing backend capability

When a screen needs something the backend does not provide, **ship the
screen with an inline placeholder naming the limitation**, in the user's
terms. Never a disabled button, never a silent omission, never a fabricated
affordance (D-19).

**The narrow exception:** a placeholder is right when a feature is
*missing*, and wrong when the backend silently returns *wrong data* —
because then the screen looks fine and the note has nothing to attach to.
Where that affects a **write**, block the action and explain it. Where it
affects only a **read**, a placeholder naming the scope is enough.

# 4. Placeholders shipped — THE LIST FOR ALI

**This is the deliverable.** It goes to Ali as ONE message now that the
feature work is closed. Each row is the copy on screen today, so he can see
exactly what a school is being told.

| # | Where | What the user is told | Backend gap |
|---|---|---|---|
| P1 | Setup → Academic years | "…cannot be changed in the app yet." | `current` is read-only; no set-current route (8) |
| P2 | Setup hub | "The current year can only be changed by your system administrator." | same as P1 |
| P3 | Setup → Who teaches what | "An assignment cannot be changed or removed yet, so check the teacher before saving." | create-only (9) |
| P4 | Setup → Who teaches what | "This cannot be changed or removed afterwards." | same as P3 |
| P5 | Setup → Timetable | "Periods apply to the whole school and cannot be edited…" | create-only, school-wide (9) |
| P6 | Setup → Timetable | clash copy admits it cannot name the other class | 409 carries no conflicting-slot id (10) |
| P7 | Admin → Accounts | "Logins that were never linked to a person cannot be listed." | no `GET /api/users` (7) |
| P8 | Student → Timetable | "Your timetable cannot be shown in the app yet." | `/students/me` has no `sectionId` (1) |
| P9 | Fees → Fee heads | "A fee head cannot be renamed or removed afterwards…" | no PUT/DELETE |
| P10 | Fees → Fee plans | "A plan cannot be edited or removed afterwards…" | no PUT/DELETE |
| P11 | Fees → Generate invoices | "There is no way to delete an invoice on this system." | no invoice delete (14) |
| P12 | Fees → Record payment | "An earlier date cannot be entered." | date fields ignored (15) |
| P13 | Fees → Record payment | "Cheque, card and online are not available." | `source` enum is 2 values (17) |
| P14 | Fees → Record payment / Approvals | "There is no way to reverse or cancel an approved payment." | no void/reverse (14) |
| P15 | Fees → Invoice detail | "This system has no way to list the individual payments." | no payment history (16) |
| P16 | Fees → Receipt | "This receipt cannot be downloaded or printed yet." | no PDF (22) |
| P17 | Fees → Collection report | "This report cannot be narrowed to a month or a year." | filters ignored (18) |
| P18 | Academics → Grade scheme | "Grades are applied automatically… the bands cannot be viewed or changed from the app yet." | no grade-scheme endpoints at all (24) |
| P19 | Academics → Subject resources | "…the system has nowhere to keep them, and no way to receive an uploaded file." | no resource or upload endpoints at all (25) |
| P20 | Academics → Exam papers | "This system cannot list papers back, so once you go, a paper cannot be reopened." | papers unlistable, 409 hides the id (26, 27) |
| P21 | Academics → Marks entry | "Marks already saved cannot be shown — this system has no way to read them back." | no marks GET (26) |
| P22 | Academics → Marks / publish | "Once the exam is published, marks are locked for good." | no unpublish (28) |
| P23 | Academics → Report card | "This report card cannot be downloaded or printed yet." | no file (§ 6.9) |
| P24 | Academics → Remarks | "Other staff can always see it, and so can the student." | 🔴 student access defect (23) |
| **P25** | **Notifications** | "These cannot be opened yet — a notification does not carry a link to the thing it is about." | **`data` is null on every row; no subject id** (34) |
| **P26** | **Complaints → My complaints (parent)** | "Complaints cannot be raised from a parent account yet — the app has no way to tell the school which campus it belongs to." | **no endpoint a parent may call carries `campusId`** (39) |
| **P27** | **Complaints → detail (anonymous)** | "There is no record of who raised it, so nobody can reply to them." | working as designed — stated so staff do not write into the void |

**Not shipped at all, and why:** per-category notification preferences —
there is no preferences endpoint (35), so there is no control to place.

## Blocked actions — NOT placeholders

| # | Where | What we do instead |
|---|---|---|
| B1 | Anything resolving "the current academic year" server-side | The year is **always passed explicitly**. The flag points at an EXPIRED year, so a server-resolved year would bill or record against the wrong one while looking plausible. Fee plans and exams both store the year they are given; every hub names it. |

---

# 5. End-to-end proof — and its honest limit

Four live tests, each walking a batch through its real repositories:

```
flutter test test/e2e_setup_live_test.dart      --dart-define=LIVE=true
flutter test test/e2e_finance_live_test.dart    --dart-define=LIVE=true
flutter test test/e2e_academics_live_test.dart  --dart-define=LIVE=true
flutter test test/e2e_complaints_live_test.dart --dart-define=LIVE=true
```

All pass. The academics one earned its keep immediately — it caught a
required `clientUuid` the manual probe had hidden by happening to send one.

🔴 **They drive the repositories, not the widgets**, because `flutter test`
uses a fake clock. `integration_test/` now exists to close that gap but has
not been run — see § 0b.

---

# 6. Waiting on Ali — the full list

Items 1–33 are in `BACKEND_CONTRACT.md` (T11–T15). T16 adds:

34. **Notifications carry no target** — `data` is null on every row and
    there is no subject id, so a notification cannot be opened onto the
    thing it is about. That is most of what a notifications centre is for.
35. **No notification preferences endpoint.**
36. **Three JSON conventions in one API** — notifications camelCase,
    complaints and staff attendance snake_case, earlier modules mixed.
37. **Staff and student attendance use different status vocabularies**
    (`half_day` vs `excused`) for what is otherwise the same act.
38. `?status=` on `/api/complaints` accepts an unknown value and answers
    200 rather than 400, unlike the write paths.
39. 🔴 **A parent cannot raise a complaint.** `campusId` is required and no
    endpoint a parent may call exposes one.

The highest-value four, in order: **23** (privacy), **39** (a whole role
cannot use a feature), **34** (notifications are half-built without it),
**26/27** (marks and papers cannot be read back, so entry cannot be
resumed).

# 7. Decisions still open

1. Multi-campus picker — deferred, pilot is single-campus.
2. Whether to keep `validateBands`, which is deliberately unwired because
   no grade-scheme endpoint exists (item 24).
3. Whether the remaining unbuilt surface — assignments (the API has 11
   endpoints), student promotion — is in scope before pilot.

# 8. For the acceptance pass (T17)

- Offline state missing on T8–T10 screens (diary, setup, finance,
  academics and the T16 screens set it).
- Web DB seam is a silent no-op that discards writes.
- PostToolUse hook not live — `check_tokens.sh` is run manually.
- `integration_test` has never run (§ 0b).
- **Purge `test-school` before pilot.** None of this can be deleted:
  - `student1`; a period **"PROBE Break"**, a room **"PROBE Room 1"**; one
    teaching assignment per setup-E2E run;
  - fee heads **PROBE Head A/B/C**, **PROBE Plan 2** and its paid 2029-01
    invoice; a PKR 1.00 approved payment against the seeded 2026-07 invoice
    (now `partial`); one `E2E …` fee head, plan, invoice, payment and
    receipt per finance-E2E run;
  - exams **PROBE noterm** (published, marks locked), **PROBE term final**
    and six **PROBE t …** exams; an exam paper on 5-A Mathematics with a
    mark for Ali Khan; chapter **PROBE Chapter 1** with **PROBE Topic 1**
    and three coverage logs; one `E2E …` exam, paper, mark, chapter, topic
    and coverage log per academics-E2E run;
  - **11 probe complaints** (`PROBE named`, `PROBE anon`,
    `PROBE student-owned`, `PROBE cat …`, `PROBE pri …`) and their
    comments; two `E2E …` complaints per complaints-E2E run; staff
    attendance records for 2026-09-26/27.
  - Probe remarks WERE deleted — remarks are the one thing that can be.

---

# 9. Running locally

Start order matters — the backend exits if Postgres is down.

```
# Docker Desktop running first
docker start backend-db-1          # docker ps → Up, 0.0.0.0:5432->5432
cd backend && sh ./gradlew bootRun # progress bar stays ~80% — normal
curl http://localhost:8080/health  # {"status":"ok",...}
cd frontend && flutter run -d chrome --web-port=3000
```

- Leave `smart-ems-app` stopped (old image, competes for 8080).
- JDK 21 required. Port 3000 only (CORS).
- Railway back later: uncomment the URL in `ApiConfig.baseUrl`.
- ⚠️ The backend has died mid-session before. If requests start failing,
  check it is still running before assuming a code fault.

**Stopping here — T17 is the acceptance pass and needs its own prompt.**

