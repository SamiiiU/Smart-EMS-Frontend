# Backend Contract

Pending seeding by the project owner (Ali owns the backend; Sami will
supply verified contract details). Do not populate this with guessed
endpoints — an invented list is worse than an empty one.

## Verified endpoints

### CONFIRMED 2026-08-03 — via the deployment's own OpenAPI document

The Railway deployment publishes a **publicly readable OpenAPI 3.0.1
document** at `GET /v3/api-docs` (also `GET /swagger-ui/index.html`). This
is the API describing itself — the strongest available source short of a
live authenticated call, and explicitly NOT backend source reading.

```
$ curl -s https://smart-ems-backend-production.up.railway.app/v3/api-docs
openapi: 3.0.1   title: "Smart EMS API"   version: v1
servers: https://smart-ems-backend-production.up.railway.app (Production)
          http://localhost:8080 (Local)
124 paths documented
```

The document's own description states the auth model verbatim:

> **Auth:** POST /auth/login → accessToken (15 min) + refreshToken (30 d).
> Send `Authorization: Bearer <accessToken>` on every /api/** call.
> The tenant (institution) is derived from the token — never sent
> separately. All errors share one JSON shape (see the ApiError schema).

Security scheme: `bearerAuth`, `type: http`, `scheme: bearer`,
`bearerFormat: JWT`, applied globally. **Bearer-token auth is confirmed as
the intended design by the backend itself.**

#### Auth endpoints — CONFIRMED

| Method | Path | Request | Response |
|---|---|---|---|
| POST | `/auth/login` | `{institutionCode, username, password}` — **all three required** | `{accessToken, refreshToken, expiresIn}` |
| POST | `/auth/refresh` | `{refreshToken}` | `{accessToken, refreshToken, expiresIn}` |
| POST | `/auth/logout` | `{refreshToken}` | `{string: string}` |
| GET | `/auth/me` | — (bearer) | object |
| GET | `/health` | — (**public, no auth**) | `{"status":"ok","service":"smart-ems"}` |

**⚠️ `/auth/refresh` ROTATES the refresh token** — the response carries a
new `refreshToken`, not just a new `accessToken`. It must be stored. See
"Corrections to T6" below.

**Token lifetimes:** accessToken 15 minutes, refreshToken 30 days.

**Multi-tenancy:** the tenant is derived from the token and is NEVER sent
as a separate header or parameter. `institutionCode` is supplied at login
only.

#### Person-record endpoints — CONFIRMED

| Method | Path |
|---|---|
| GET | `/api/staff/me` |
| GET | `/api/students/me` |

These — not `/auth/me` — are the endpoints behind the D-17 orphan case.
See "Known gaps" for the unresolved part.

#### User creation — CONFIRMED, and there is NO self-signup

| Method | Path | Request |
|---|---|---|
| POST | `/api/users/provision` | `{username, email?, password, role}` — `username`, `password`, `role` required |

`/api/users/provision` sits under `/api/**`, so it **requires an
authenticated bearer token**. There is no unauthenticated
signup/register/create-account endpoint anywhere in the 124 documented
paths. **Users are provisioned by an already-authenticated admin; they do
not self-register.** This is consistent with `/auth/login` requiring an
`institutionCode` — accounts exist within an institution that already
exists.

#### Tenant bootstrap — CONFIRMED, and NOT in the OpenAPI document

`/internal/bootstrap/*` routes exist but are **absent from `/v3/api-docs`**,
which is why a search of the 124 documented paths did not find them. They
are token-gated by a `BOOTSTRAP_TOKEN` (a Railway env var), supplied **in
the request body**, not as a header.

| Method | Path | Body |
|---|---|---|
| POST | `/internal/bootstrap/institution` | `{token, institutionCode, institutionName, adminUsername, adminPassword}` |
| POST | `/internal/bootstrap/purge-institution` | token-gated; **this is how the `test-school` test tenant gets removed before the pilot** |
| POST | `/internal/bootstrap/backfill-grade-schemes` | token-gated migration helper |
| POST | `/internal/bootstrap/backfill-role-permissions` | token-gated migration helper |

All four confirmed live (POST `{}` → `400 Validation Failed`, i.e. the route
exists and validated; a non-existent path returns `401` instead, falling
through to the auth wall — a clean existence discriminator).

The endpoint self-describes on a bad request — posting `{}` returns a 400
listing every missing field, which is how the shape above was derived:

```
{"status":400,"error":"Validation Failed","path":"/internal/bootstrap/institution",
 "details":{"adminUsername":"must not be blank","institutionCode":"must not be blank",
            "institutionName":"must not be blank","token":"must not be blank",
            "adminPassword":"must not be blank"}}
```

Success returns `{institutionCode, tenantId, adminUserId, adminUsername}`.

**This is the only way to create the first admin of an institution**, and it
resolves the apparent chicken-and-egg problem: `/api/users/provision` needs
an admin token, and this is where the first admin comes from. Note the
bootstrapped admin is created with the `admin` role, **not** `super_admin` —
per Ali, only `super_admin` holds `user.manage`, and no production API
currently grants it (a `POST /internal/bootstrap/grant-role` was proposed).

**A test institution now exists in production** (created 2026-08-03 for T7
verification): `institutionCode: test-school`, admin `admin`, tenantId
`019fc6a8-d4fa-781c-a02d-54ddda6404c1`.

#### Self-signup and password reset — CONFIRMED ABSENT (2026-08-05)

Re-verified before T8 by **source grep + live probe**, because
`/internal/bootstrap/*` had already proved the OpenAPI doc is not
exhaustive. (This required a one-off, explicitly-authorised exception to the
"never read `backend/`" rule; existence was then confirmed against the
running API so the contract still rests on observed behaviour.)

- `AuthController` declares exactly four mappings: `/login`, `/refresh`,
  `/logout`, `/me`.
- `SecurityConfig`'s public allowlist is closed: `/health`, `/auth/login`,
  `/auth/refresh`, `/auth/logout`, `/v3/api-docs/**`, `/swagger-ui/**`,
  `/internal/bootstrap/**`; `anyRequest().authenticated()`.
- Live: `/auth/signup`, `/auth/register`, `/auth/reset-password`,
  `/auth/forgot-password` all return **401**, not 400 — no such route.

**There is no self-registration and no password-reset flow.** A user who
forgets their password has no self-service path; an admin must reset it,
and no admin-facing endpoint for that exists either. Worth raising with Ali
before the pilot — it is a product gap, not a frontend one. D-44 stands.

Also noted: `SecurityConfig` guards `/admin/**` with `hasRole("ADMIN")`, but
no `AdminController` exists — dead configuration, not a hidden surface.

### Attendance + timetable — VERIFIED LIVE 2026-08-05 (T8)

⚠️ **The OpenAPI document is WRONG for the attendance endpoints.** Springdoc
collided identically-named inner DTOs (`MarkBody`, `BulkBody`, `BulkRow`
exist in both `AttendanceController` and `StaffAttendanceController`) and
published the **staff** schema for the **student** endpoints. Anything built
from the doc alone would have posted `staffId` where `studentId` is
required. Shapes below are from live 400-validation responses, not the doc.

| Endpoint | Actually requires |
|---|---|
| `POST /api/attendance` | `clientUuid`, `studentId`, `sectionId`, `attendanceDate`, `status` |
| `POST /api/attendance/bulk` | `sectionId`, `attendanceDate`, `rows[]` of `{studentId, status, clientUuid}` |
| `POST /api/staff-attendance` | `clientUuid`, `staffId`, `attendanceDate`, `status` — a genuinely separate feature |
| `GET /api/attendance/section/{id}` | query `date` (required) |

- **`status` enum (live-confirmed, LOWERCASE):**
  `present, absent, late, leave, excused` — exactly the five attendance
  variants `StatusPill` already ships from T2.
- **`clientUuid` is a required idempotency key**, and `MarkResponse` returns
  `idempotentReplay: boolean`. This is purpose-built for an offline queue:
  a queued row can be retried safely and the server reports whether it was a
  replay.
- `GET /api/attendance/section/{id}?date=` returns
  `{sectionId, date, total, present, absent, late, leave, excused, records[]}`.
  **Before anything is marked it returns `total: 0, records: []`** — it is a
  summary, NOT a roster. The roster must come from
  `GET /api/enrollments/section/{sectionId}`, which returns
  `{studentId, sectionId, academicYearId, rollNumber, status}` — **and no
  student names**, so names require a second call to `/api/students`.

#### Casing is NOT consistent across this API

Typed DTO endpoints return **camelCase** (`sectionId`, `academicYearId`).
The timetable endpoints return **raw snake_case DB columns**
(`start_time`, `end_time`, `sort_order`, `is_break`, `section_id`,
`day_of_week`, `period_id`, `subject_id`, `teacher_staff_id`). Requests to
those same endpoints are still camelCase — `POST /api/timetable/slots`
accepts `teacherStaffId` and **silently ignores** `teacher_staff_id`
(observed: the row was created with `teacher_staff_id: null` and no error).
`dayOfWeek` is ISO 1–7 (Mon=1).

### 2026-08-10 — Ali's PRs: casing fix, sectionId, new endpoints

**BREAKING: timetable responses are now camelCase.** They previously
returned raw snake_case DB columns. Verified live:
`startTime`, `endTime`, `dayOfWeek`, `isBreak`, `isAutoGenerated`,
`periodName`, `teacherStaffId`, `sortOrder`, `sectionId`, `sectionName`,
`subjectId`, `subjectName`, `roomId`, `roomName`, `slotId`, `periodId`.

**The blocker below is RESOLVED** — `sectionId` is present. Real payload:

```json
{"slotId":"…","dayOfWeek":1,"periodId":"…","periodName":"Period 3",
 "startTime":"09:45:00","endTime":"10:30:00","sortOrder":4,
 "sectionId":"…","sectionName":"Class 9-C","subjectId":"…",
 "subjectName":"Mathematics","teacherStaffId":"…",
 "roomId":null,"roomName":null}
```

⚠️ Two things differed from the announcement, caught by verifying:
- The response carries **more** than described — `slotId`, `periodId`,
  `subjectId`, `teacherStaffId`, `roomId`, `roomName` were not mentioned.
- `sectionName` is `"Class 9-C"`, i.e. `{className}-{sectionName}`. The
  announcement's example was `"Grade 5-C"`; the actual prefix is whatever
  the class is named. **Use the field verbatim; do not compose this label
  client-side.**

#### New endpoints — VERIFIED LIVE

| Endpoint | Shape | Status |
|---|---|---|
| `GET /api/institution/me` | `{id, name, code, timezone, locale, logoUrl, status}` | **WIRED** — `name` replaces the raw code in the app bar |
| `POST /api/users/me/change-password` | `{currentPassword, newPassword}` | **WIRED** — required by `forcePasswordChange` |
| `GET /api/guardians/me` | 404 when unlinked | deferred to **T9** |
| `POST /api/users/{userId}/reset-password` | `{newPassword}` | deferred to **T10** |

**`/auth/login` now returns `forcePasswordChange`** (boolean, alongside
`accessToken`/`refreshToken`/`expiresIn`). Handled now, in T7's login flow,
because it changes login's correctness today regardless of which task owns
the reset feature.

⚠️ **Changing a password REVOKES EVERY SESSION, including the caller's.**
The app must return to `/login` afterwards, not assume the current token
survives.

**`GET /api/guardians/me` — for T9.** Returns `404` with
`"Guardian record linked to this login not found: <userId>"` when the login
has no guardian record. This is the SAME orphan shape as `/api/staff/me`
and `/api/students/me`, so it is D-17's `notLinked` case, **not** an error —
`ApiConfig.personRecordPaths` and `personRecordPathFor` should gain
`parent` → `/api/guardians/me` when T9 wires parents. It closes the gap
noted in T7 ("parents are never orphan-checked").

#### 🔴 RESOLVED 2026-08-10 — the teacher timetable returned no IDs

```
GET /api/timetable/teacher/{staffId}/today   ->
[{"period_name":"Period 3","start_time":"09:45:00","end_time":"10:30:00",
  "sort_order":4,"section_name":"C","subject_name":"Mathematics"}]
```

Display names only — **no `section_id`, no `period_id`, no slot id.** The
full variant (`GET /api/timetable/teacher/{staffId}?academicYearId=`) is the
same, plus `day_of_week` and `room_id`, still with no `section_id`.

Consequence: **a teacher cannot navigate from "Today" to attendance
marking**, because every marking call requires `sectionId`. Nor can the
Today tab show per-period attendance status, since that also needs
`sectionId`.

No workaround exists in the API: `/api/teaching-assignments` can only be
queried **by section**, not by staff, so there is no route from a teacher to
their own sections. Matching on `section_name` is not viable — section names
("C") are not unique across classes.

**Needs Ali:** add `section_id` (and ideally `period_id` / `subject_id`) to
both teacher timetable responses. Everything else for T8 is unblocked.

### Parent / guardian — VERIFIED LIVE 2026-08-11 (T9 Part A)

Seeded a real parent (`parent1` / `Test1234!`, role `parent`) in
`test-school` and verified every shape below **as that parent**, not as
admin.

**Parent JWT permissions** (confirms parents are read-only on attendance —
no `attendance.mark`):
`attendance.view, complaint.raise, diary.view, exam.results.view, fee.view`

#### `GET /api/guardians/me` — 200 shape

```json
{"guardianId":"…","firstName":"Imran","lastName":"Ahmed",
 "students":[{"studentId":"…","firstName":"Bilal","lastName":"Ahmed",
   "admissionNumber":"ADM-100","className":"Class 9",
   "sectionName":"Class 9-C","sectionId":"…","academicYearId":"…",
   "photoUrl":null,"relationship":"father"}]}
```

`students` is an **array**, and it carries `sectionId` + `academicYearId`,
so no extra lookup is needed to reach attendance. 404 when the login has no
guardian record — the same D-17 orphan shape as staff/students.

#### 🔴 Multi-child: the response supports it, the WRITE API cannot create it

`POST /api/guardians` requires `{studentId, firstName, lastName,
relationship}` and **creates a brand-new guardian row every time**. Passing
an existing `guardianId` does not link that guardian to a second student —
it is ignored and a third row is created (verified: three rows now share one
`userId`). `GET /api/guardians/me` then resolves by `userId` and returns
**one** guardian with **its** single student.

So a genuinely multi-child guardian **cannot be produced through the API**.
There is no link/patch endpoint in the documented paths.

Consequence, and how T9 handles it: the contract is an array, so the client
handles 0, 1 and N children. N is exercised against mocked responses; it
could not be verified live. **Needs Ali:** either accept `guardianId` on
`POST /api/guardians`, or add a link endpoint. Until then multi-child is
untestable end-to-end, and any parent with two children at a real school
will see only one of them.

#### `GET /api/attendance/student/{studentId}` — needs a RANGE

Query params `from` (**required**) and `to`. Returns a paged envelope whose
rows are **snake_case**, unlike the camelCase typed DTOs:

```json
{"page":0,"size":31,"totalElements":1,
 "content":[{"attendance_date":"2026-08-11","status":"present",
             "section_id":"…","subject_id":null,
             "updated_at":"2026-08-11T05:02:21.234+00:00"}]}
```

`GET /api/attendance/student/{id}/stats` requires `academicYearId` (not
used by T9).

#### `GET /api/parent-progress/student/{studentId}` — the landing screen

Purpose-built for exactly this view, and needs no params:

```json
{"studentId":"…","studentName":"Bilal Ahmed","className":"Class 9",
 "sectionName":"C","date":"2026-08-11","attendanceStatus":"present",
 "diaryEntries":[],"remarks":[],"attendanceStats":null,
 "latestResult":null,"syllabusProgress":{"subjects":[]},
 "pendingAssignments":[]}
```

⚠️ **`sectionName` disagrees between endpoints**: `guardians/me` returns
`"Class 9-C"` (`{class}-{section}`), `parent-progress` returns `"C"` (the
bare section). T9 uses the `guardians/me` form, which is the complete label.
Worth telling Ali, as the two will drift further apart otherwise.

⚠️ `attendanceStatus` is `null` when nothing is marked yet — that is
"not marked", NOT absent, and must never be rendered as absent.

#### Error shape — CONFIRMED live, matches what T6 assumed

```
$ curl -X POST .../auth/login -H 'Content-Type: application/json' \
    -d '{"institutionCode":"__nope__","username":"__nope__","password":"__nope__"}'
{"status":401,"error":"Unauthorized","message":"Invalid credentials",
 "path":"/auth/login","timestamp":"2026-08-03T07:35:05.256761697Z"}
```

`{status, error, message, path, timestamp}` — exactly the shape
`api_error_mapper.dart` was built against. `message` is human-meaningful
("Invalid credentials"), which is why `LoadFailure` carries it verbatim.

#### Corrections to T6 that this discovery forced

1. **`mePath` was WRONG.** T6 guessed `/me`; the real endpoint is
   `/auth/me`. Every identity-gate call would have 404'd — and worse, that
   404 would have been misread as `notLinked` (the D-17 orphan case),
   showing every user "your profile isn't linked, contact your
   administrator" instead of working. Fixed.
2. **Refresh-token rotation was being discarded.** T6's `DioTokenRefresher`
   read only `accessToken` and stored `refreshToken: null`, keeping the old
   refresh token. Since the backend rotates, the stored token would go stale
   and refresh would eventually fail permanently — a silent forced logout
   with no recovery. Fixed, with a regression test.

Both were latent: T6's tests passed because they asserted against T6's own
guessed constants rather than the real contract.

### Full path inventory

124 paths across: academic-years, assignments (incl. AI generate/grade),
attendance, campuses, classes, complaints, diary, enrollments, exams,
fee (heads/invoices/payments/plans/receipts/reminders/reports), guardians,
import (staff/students), notifications, parent-progress, remarks, sections,
staff, staff-attendance, students, subjects, syllabus (incl. AI
extract-from-pdf), teaching-assignments, timetable (incl. generate),
users. Retrieve the current list any time with
`curl -s <base>/v3/api-docs` — it is public and self-describing, so this
file should not duplicate it in full.

### CORS — VERIFIED 2026-07-30 against the running API

Method: live `curl` preflights against `http://localhost:8080` with the
backend booted from `SmartEMS/backend` (15 Flyway migrations applied,
`Started SmartEmsApplication in 48.994 seconds`). Not inferred from source.

| Fact | Observed |
|------|----------|
| Allowed origin | `Access-Control-Allow-Origin: http://localhost:3000` |
| Allowed methods | `GET,POST,PUT,PATCH,DELETE,OPTIONS` |
| Allowed headers | `authorization, content-type` |
| Preflight max age | `Access-Control-Max-Age: 3600` |
| Non-allowlisted origin | `403`, **no** `Access-Control-Allow-Origin` |
| `Access-Control-Allow-Credentials` | **absent** — see note below |

Evidence:

```
$ curl -i -X OPTIONS http://localhost:8080/ \
    -H "Origin: http://localhost:3000" -H "Access-Control-Request-Method: GET"
HTTP/1.1 200
Access-Control-Allow-Origin: http://localhost:3000
Access-Control-Allow-Methods: GET,POST,PUT,PATCH,DELETE,OPTIONS
Access-Control-Max-Age: 3600

$ curl -i -X OPTIONS http://localhost:8080/ \
    -H "Origin: http://evil.example.com" -H "Access-Control-Request-Method: GET"
HTTP/1.1 403          <- no CORS header: a real allowlist, not a wildcard echo
```

Consequences for the frontend:

- The web app **must** run on port 3000 (`--web-port=3000`). Any other port
  is blocked by the browser.
- `--disable-web-security` is **not needed and must not be used**.
- `Authorization` is an allowed request header, so a **bearer-token** auth
  scheme works cross-origin.
- **`Access-Control-Allow-Credentials` is absent.** Cookie / session-based
  auth will therefore NOT work cross-origin from `localhost:3000`. If T7
  turns out to need cookies, this must be raised with Ali rather than worked
  around on the client. Do not assume credentials are supported.
- All paths tried returned `401` unauthenticated (Spring Security is on by
  default), including `/actuator/health`. Preflight `OPTIONS` is permitted
  without auth.

### Railway deployment — CORS, re-verified 2026-08-03 (was blocked 2026-08-01)

Base URL: `https://smart-ems-backend-production.up.railway.app`

Method: live `curl` preflights and simple requests against the Railway
instance directly (not local Docker). Not inferred from source.

**2026-08-01: BLOCKED.** `localhost:3000` was rejected identically to a
bogus control origin (`403 Invalid CORS request` for both). Logged as a
blocker for Ali.

**2026-08-03: FIXED, re-verified live.** Ali added the allowlist entry.

| Fact | Observed |
|------|----------|
| `OPTIONS /` with `Origin: http://localhost:3000` | `200`, `Access-Control-Allow-Origin: http://localhost:3000` |
| `OPTIONS /` with `Origin: http://evil.example.com` (control) | still `403 Invalid CORS request` — real allowlist, not a wildcard echo |
| `GET /` with `Origin: http://localhost:3000` (simple request) | `401 Unauthorized` (correct — CORS passes, auth still required) |
| `Access-Control-Allow-Headers` | `authorization, content-type` |
| `Access-Control-Allow-Methods` | `GET,POST,PUT,PATCH,DELETE,OPTIONS` |
| `Access-Control-Max-Age` | `3600` |
| **`Access-Control-Allow-Credentials`** | **`true` — PRESENT** |

```
$ curl -i -X OPTIONS https://smart-ems-backend-production.up.railway.app/ \
    -H "Origin: http://localhost:3000" -H "Access-Control-Request-Method: GET"
HTTP/1.1 200 OK
access-control-allow-credentials: true
access-control-allow-headers: authorization, content-type
access-control-allow-methods: GET,POST,PUT,PATCH,DELETE,OPTIONS
access-control-allow-origin: http://localhost:3000
access-control-max-age: 3600

$ curl -i -X OPTIONS https://smart-ems-backend-production.up.railway.app/ \
    -H "Origin: http://evil.example.com" -H "Access-Control-Request-Method: GET"
HTTP/1.1 403 Forbidden
Invalid CORS request
```

**⚠️ IMPORTANT DEVIATION — contradicts the local-Docker finding above.**
The local backend (2026-07-30) measured `Access-Control-Allow-Credentials`
as **absent**, and every downstream note (including the T7 auth-design
guidance at the top of this file and in `CLAUDE.md`) was written on that
basis: *"cookie/session auth will NOT work cross-origin, bearer-token
only."* **On Railway, credentials ARE now allowed.** This does not retract
the bearer-token plan — bearer is still simpler and still works — but it
means the earlier hard constraint ("cookies cannot work, full stop") is
no longer true against this deployed backend specifically. If T7 design
leaned on that absence as a reason to rule out cookies entirely, that
reasoning should be revisited with Ali rather than assumed to still hold.
Not acting on this here — T6 stays bearer-token per existing design,
flagging only so a future task doesn't rediscover this by surprise.

T6 can now proceed with the live-verification step this contract requires.

## Known gaps

_All T6-era gaps are now CLOSED (2026-08-03): endpoint paths, auth shapes,
JWT claims, the orphan-case endpoint, and test credentials. See Verified
endpoints and D-41…D-45. What remains:_

- **JWT claim shape is verified for `admin` only.** A real token was decoded
  (D-41: `sub`, `tid`, `roles`, `permissions`, `iat`, `exp`) but from an
  admin account. `teacher` / `student` / `parent` tokens are assumed to
  carry the same claim names with different values — reasonable, but not
  observed. Worth a spot-check when the first non-admin account exists.
- **`parent` has no person-record endpoint.** There is no
  `/api/guardians/me`, so `ApiConfig.personRecordPathFor` returns null for
  parents and they are never orphan-checked. If a parent can meaningfully
  exist without a guardian record, that endpoint needs to exist before the
  D-17 gate can cover them.
- **`super_admin` cannot be created through any production API.** Per Ali:
  only `super_admin` holds `user.manage`; `/internal/bootstrap/institution`
  grants `admin`, and `PROVISIONABLE_ROLES` excludes it to prevent privilege
  escalation. Ali proposed a token-gated
  `POST /internal/bootstrap/grant-role`. Not frontend-blocking today.
- **The `permissions` claim is unused.** Recorded in D-41; capability gating
  is not built (T8+ may want it rather than inferring from role names).

## Never assume

- Never assume `Access-Control-Allow-Credentials` is supported. It was
  measured as **absent** (see Verified endpoints). Cookie-based auth will
  not work cross-origin.
- Never assume the web app can run on a port other than 3000 in
  development. The CORS allowlist is origin-exact.

### Running the backend locally — gotchas found 2026-07-30

Recorded because two of these cost real time and neither is guessable:

1. **`docker-compose.yml` in `SmartEMS/backend` defines only the `db`
   service.** There is no `app` service, so `docker compose up -d --build`
   brings up Postgres only and `--build` has nothing to build. The app is a
   separate container.
2. **The prebuilt `smart-ems-backend:local` image defaults its datasource to
   `localhost:5432`**, which inside the container is the container itself →
   `Connection refused`. It also sets Flyway's URL independently, so
   `SPRING_DATASOURCE_URL` alone is not enough. What actually worked:
   ```
   docker run -d --name smart-ems-app --network backend_default -p 8080:8080 \
     -e SPRING_DATASOURCE_URL='jdbc:postgresql://db:5432/smartems' \
     -e SPRING_DATASOURCE_USERNAME='smartems' \
     -e SPRING_DATASOURCE_PASSWORD='localdev' \
     -e SPRING_FLYWAY_URL='jdbc:postgresql://db:5432/smartems' \
     -e SPRING_FLYWAY_USER='smartems' \
     -e SPRING_FLYWAY_PASSWORD='localdev' \
     smart-ems-backend:local
   ```
3. **`docker build` of the backend currently FAILS on Windows** —
   `./gradlew: not found`, exit 127, despite the file existing.
   Cause: `gradlew` is checked out with **CRLF** line endings
   (`#!/bin/sh\r\n`), so Linux looks for the interpreter `/bin/sh\r`.
   This is a backend-repo issue for Ali (`.gitattributes` with
   `gradlew text eol=lf`, or `dos2unix gradlew`). **Not fixed here** —
   frontend work must not edit `backend/`. The image built 10 days ago was
   used instead, so the CORS result above stands, but the app image cannot
   currently be rebuilt from source on this machine.
4. The earlier stale-mount failure is **resolved**: `docker compose config`
   from `SmartEMS/backend` now resolves `init.sql` to
   `E:\Business Work\Babultech\SmartEMS\backend\docker\init.sql`, which
   exists. The old error came purely from containers created while the
   backend lived at `ERP working\smart-ems-backend`. No hardcoded absolute
   path in the compose file. Note the compose project name is now `backend`,
   so the volume is `backend_pgdata` — a fresh database, not the old
   `smart-ems-backend_pgdata`.

- Never assume an endpoint, request/response shape, auth mechanism, or
  error format exists unless it is listed above or confirmed directly by
  Ali.
- Never assume the backend is reachable at a given URL without
  independent confirmation (see `CLAUDE.md` for the current, unverified
  local dev URL).
- Never read `backend/` (the local clone at the repo root) as a source of
  truth. It exists only as a runtime dependency, to run the API locally
  for development. This contract is verified against the running API's
  observed behaviour, not by reading backend source code.

---

## 2026-09-17/18 — Local backend, post-Railway (T10 Part A)

**Build:** whatever `backend/` was at the user's `git pull` on 2026-09-17,
run via `sh ./gradlew bootRun` against Docker Postgres (`docker compose up
-d db`), Java 21 (portable Temurin, `JAVA_HOME` set). Verified live against
`http://localhost:8080` on 2026-09-18.

**This is a DIFFERENT seed than the 2026-08-11 Railway one T8/T9 were built
and tested against.** `test-school` here has July-2026 timestamps — it is
whatever the local DB volume already held, not a fresh Flyway seed and not
the Railway fixture. Endpoints/behaviour matched (see below); the DATA did
not, and should not be assumed to match any earlier session's fixture
descriptions going forward.

| Check | Result |
|---|---|
| `admin` / `test-school` login | ✅ 200 |
| `forcePasswordChange` on login response | ✅ present |
| `GET /api/institution/me` | ✅ 200 |
| `GET /api/guardians/me` (orphan shape) | ✅ real 404, `"Guardian record linked to this login not found: <uuid>"` |
| `sectionId` on `/api/timetable/teacher/{id}/today` | ✅ present |
| **Original T8/T9 fixture** (Class 9 §C, 5 students, Ayesha Khan/Mathematics) | ❌ **absent** — this DB never had it |
| **What this DB actually has** | 1 campus, 1 academic year (2025-26), class **"Grade 5"**, one section, 1 enrolled student (**Ali Khan**, ADM STU-001), 3 subjects (Math/English/Science). Admin's own staff row (EMP-001) already teaches Math to that section. |

**Provisioned this session** (admin token, live API, not by editing the DB
directly) to have real Teacher/Parent accounts to test against:
- `teacher1` / `Test1234!` — staff record **Ayesha Khan** (EMP-002), teaching-assignment for **English** (Math was taken by admin's own staff row — a real 409 conflict, not a bug, is what surfaced this), Mon–Fri timetable slots (Period 2 + Period 6) for the one existing section.
- `parent1` / `Test1234!` — guardian record linking to **Ali Khan** (the only student that exists here).

**Known consequence:** with 1 section / 1 student, D-15's completeness
*sort* and D-14's empty-vs-zero-counters distinction cannot be meaningfully
exercised against live data — there's nothing to sort and only one
possible state. T10 should assert both rules with unit/widget tests against
constructed data (which the task already requires), and treat this single
live section only as a smoke-test path, not as coverage for either rule.

**This manual provisioning is exactly the gap T10 closes.** There is
currently no UI path to create any of the above — every record above was
created by hand-crafting API calls, which is real developer effort, not a
workflow an admin should ever have to do. Recorded here so it reads as the
justification for T10's own scope, not as an accepted permanent workaround.

### T10 Part B — admin endpoints, VERIFIED LIVE 2026-09-18 (local build)

#### Shapes

All list endpoints return the Spring `Page` envelope
(`{content:[…], totalElements, totalPages, size, number, …}`).

| Endpoint | Notes |
|---|---|
| `GET /api/students` | `{id, admissionNumber, firstName, lastName, gender, dateOfBirth, admissionDate, status, photoUrl, campusId, userId, version}` |
| `GET /api/students/{id}` | identical object, unwrapped |
| `GET /api/staff` | as students plus `employeeCode`, `designation`, `employmentType`, `dateJoined` |
| `GET /api/sections` | `{id, classId, academicYearId, name, classTeacherId, defaultRoomId, capacity}` |
| `GET /api/classes` | `{id, campusId, name, levelOrder}` |

⚠️ **`GET /api/students` carries NO class/section information** — no
`sectionId`, no `className`. Enrolment lives only in
`GET /api/enrollments/section/{sectionId}`, which carries `studentId` but
no names. Same split T8 hit for the register roster: a students list that
shows a class column needs BOTH calls joined client-side.

⚠️ **`GET /api/sections` carries NO counts and NO class name** — only
`classId` and `classTeacherId`. See the D-15 note below.

#### Create-user chain — required fields (from live 400 `details`)

| Endpoint | Required |
|---|---|
| `POST /api/users/provision` | `username`, `password`, `role` (`email` optional) → returns `{userId, username, role}` |
| `POST /api/students` | `firstName`, `lastName`, `admissionNumber`, `campusId` |
| `POST /api/staff` | `firstName`, `lastName`, `employeeCode`, `campusId` |
| `POST /api/enrollments` | `studentId`, `academicYearId`, `sectionId` |
| `POST /api/guardians` | `studentId`, `firstName`, `lastName`, `relationship` |

`userId` is accepted (not required) on `/api/students`, `/api/staff` and
`/api/guardians` — that is the field that LINKS a provisioned login to its
person record, and therefore the field D-17's recovery path must re-send.

#### Password reset — EXISTS on this build

`POST /api/users/{userId}/reset-password`, body `{newPassword}`
(live 400: `{"newPassword":"must not be blank"}`). T8 recorded this as
deferred-to-T10; it is real and available.

#### 🔴 CSV import is **SYNCHRONOUS**, not an async job

The task flagged this as the thing to confirm. Confirmed by running it:

```
POST /api/import/students   (multipart, field name "file")
→ {"jobId":"…","status":"completed","totalRows":2,"successRows":2,"errorRows":0}
```

The POST **returns the final result**, with counts, in one call. There is
nothing to poll. A jobId IS returned and `GET /api/import/{jobId}` works
afterwards, but purely as a record — it returns the same already-final
object. **Do NOT build a polling UI**; the earlier note that
`/api/import/{jobId}` implied async was misleading.

- **Content type is `multipart/form-data`, field name `file`.** Posting
  JSON returns a **500**, not a 400 — a wrong content type is not handled
  cleanly. Worth telling Ali; it is a confusing failure for any client.
- **`campusId` is not needed** as a param (inferred; only one campus here —
  untested with several).

⚠️ **CSV headers are `snake_case`, not camelCase.** `first_name`,
`last_name`, `admission_number`. A camelCase header file parses as
2 rows with 2 errors and `status: "failed"` — every row reporting
`"first_name missing"`. The import screen must state the expected header
names, or every first attempt fails.

`GET /api/import/{jobId}/errors` → paged `{rowNumber, message}`, e.g.
`{"rowNumber":2,"message":"first_name missing"}`. `rowNumber` is
1-indexed **including the header row** (first data row = 2). This is the
per-row detail the import screen needs.

#### B-02 / B-03 — the two documented "gaps", re-tested

Method: unknown params are silently ignored by this API, so a param that
CHANGES the result is genuinely honoured. `?nonsenseParam=xyz` returning
the unfiltered count is the control that makes the rest meaningful.

| Param on `/api/students` | real value | bogus value | Verdict |
|---|---|---|---|
| `q` / `search` / `name` / `query` | 1 | **1** | ❌ **ignored — B-02 confirmed, no server-side search** |
| `sectionId` | 1 | **0** | ✅ **WORKS** |
| `classId` | 1 | **0** | ✅ **WORKS** |
| `status` | active→1 | inactive→0 | ✅ works |
| `academicYearId` | 1 | **1** | ❌ ignored |
| `nonsenseParam` (control) | 1 | — | ignored, as expected |

**B-02 stands: no server-side search.** Client-side filter per D-20 is
correct.

🔴 **B-03 does NOT stand on this build: `classId` and `sectionId` filters
work.** The instruction to omit the class filter rested on the parameter
being unconfirmed; it is now confirmed present and functioning. D-19's
"no affordance without a backend" therefore does not bar it — there IS a
backend.

Caveat, stated honestly: verified against a database with **one** student,
so the evidence is "bogus id returns 0, real id returns 1, unknown param
returns 1". The control makes that sound, but it is not the same as
watching it filter 400 students into 30. Re-confirm when real data exists.

#### D-15 consequence — completeness needs N+1 calls

Nothing returns per-section counts. Building the completeness-sorted
dashboard means, for each section: `/api/enrollments/section/{id}` for the
student count and `/api/timetable/section/{id}?academicYearId=` for whether
a timetable exists — plus `/api/classes` once to resolve `classId` → name.
That is 2 calls per section. Fine for a pilot school; it is not fine for a
large one, and there is no aggregate endpoint to replace it.

---

## T11 Part B — diary, student timetable/today — VERIFIED LIVE 2026-09-18

**Build:** local `sh ./gradlew bootRun` of Ali's backend as pulled
2026-09-17 (Railway still dead). Verified by live request/response only.
Accounts: `teacher1` (staff Ayesha Khan), `parent1`, `admin`, and
**`student1` — created this session** (provisioned, then linked to the
existing student Ali Khan / STU-001 via `PUT /api/students/{id}` with
`userId`). All passwords `Test1234!`, institution `test-school`.

### `/api/campuses` — confirms the T10 post-gate fix

Returns a **bare JSON array**, NOT a Spring page:
`[{"id","name","city","timezone","is_main"}]` — note `is_main` is
snake_case in an otherwise camelCase API.

### Diary

| Call | Shape / result |
|---|---|
| `POST /api/diary` | body `{sectionId*, diaryDate*, subjectId?, title?, homework?, classwork?, note?}` → **201** entry |
| `GET /api/diary/section/{sectionId}?date=YYYY-MM-DD` | `date` **required** (400 without). Bare **array** of entries |
| `PUT /api/diary/{id}` | same body → **200** entry. Unknown id → **404** `"DiaryEntry not found: <id>"` |
| `DELETE /api/diary/{id}` | **204**. Re-creating the same key afterwards → 201 (no soft-delete lock) |
| `GET /api/diary/student/{studentId}?from=&to=` | `from` **required**. Bare array. Readable by **parent AND student** |

Entry (camelCase): `{id, sectionId, sectionName, subjectId, subjectName,
diaryDate, title, homework, classwork, note, authorName, createdAt}`.

🔴 **Uniqueness key is `(sectionId, subjectId, diaryDate)`** — NOT the
teacher. A second POST on the same key → **409**
`{"status":409,"error":"Conflict","message":"Conflicts with existing data"}`.
`subjectId: null` is its own key (a second null-subject POST also 409s).

🔴 **PUT is a FULL REPLACE.** A PUT sending only `homework` set `title`,
`classwork` and `note` to **null** — silently. The client must always
send every field it holds, or an edit wipes content the teacher never
touched.

⚠️ **No author id on the entry** — only `authorName`. "The teacher's own
entry" cannot be identified by id; and because the key is per SUBJECT, two
teachers of the same subject in one section share one entry.

⚠️ `sectionName` is `"5-A"` here, `"Grade 5-5-A"` on the teacher timetable
and `guardians/me` — a third form of the same label.

### Section timetable (the only timetable a student can read)

`GET /api/timetable/section/{sectionId}?academicYearId=` — `academicYearId`
**required**. **Whole week** in one array. Readable by `student`.

Row: `{slotId, dayOfWeek, periodId, periodName, startTime, endTime,
sortOrder, subjectId, subjectName, teacherStaffId, teacherName, roomId,
roomName}`.

**NOT the same shape as the teacher's today:** no `sectionId` /
`sectionName`; adds `teacherName`. Teacher today has the reverse.

There is **no** student timetable or student "today" endpoint:
`/api/timetable/student/{id}`, `/api/timetable/me`,
`/api/students/me/timetable` all 404. "Today" = the section week filtered
client-side by `dayOfWeek` (1 = Monday; Friday rows carried 5).

### Breaks

Slots **never** contain breaks. Breaks exist only in
`GET /api/timetable/periods?campusId=` (`campusId` required) as
`{id, name, startTime, endTime, sortOrder, isBreak}` — and that endpoint is
**403 for student and parent**. So a student's timetable cannot show break
rows from data.

### 🔴 BLOCKER — a student cannot find their own section

| Tried as `student1` | Result |
|---|---|
| `GET /api/students/me` | 200, but **no section/enrollment field** |
| `GET /api/enrollments/student/{id}` | **403** |
| `GET /api/enrollments/me` | 404 |
| `GET /api/parent-progress/student/{id}` | 200, `sectionName:"5-A"` — name only, no id |
| `GET /api/sections` | 200 — every section, nothing marks "yours" |

Matching `sectionName` against `/api/sections` would be a guess (section
names are not unique — T8). **Needs Ali:** `sectionId` +
`academicYearId` on `/api/students/me` (the way `guardians/me` already
carries them), or enrollment read permission for the student themself.

Readable as student, for the record: `/api/academic-years` (page;
`current: true` flag), `/api/sections`, `/api/classes`,
`/api/diary/student/{own id}`, `/api/parent-progress/student/{own id}`.

### T11 — open items for Ali (one list)

| # | Request | Why | Blocks |
|---|---|---|---|
| 1 | **`sectionId` + `academicYearId` on `GET /api/students/me`** | Exactly what `guardians/me` already carries per child — same shape, same reason. A student currently cannot learn their own section from any endpoint they may call (`enrollments/student/{id}` is 403; `parent-progress` has the name only). | Student Today + Timetable (app shows "not available yet") |
| 2 | **Read access to `GET /api/timetable/periods?campusId=` for `student` and `parent`** | Breaks exist ONLY there (`isBreak`); slots never contain them. Today it's 403 for both roles. | Break rows in the student timetable (app states they aren't shown) |
| 3 | **Diary: consider an author id, and confirm per-subject sharing is intended** | Entries carry `authorName` only, and the key is `(section, subject, date)` — two teachers of one subject share one entry. The app shows "Last saved by X" when the name differs. | Nothing (handled) — design confirmation |
| 4 | **Diary PUT is a full replace** | Omitted fields become null. The app always sends every field (tested). A PATCH, or ignoring absent keys, would make other clients safer. | Nothing (guarded client-side) |
| 5 | `sectionName` has three forms (`"5-A"` diary / parent-progress, `"Grade 5-5-A"` timetable / guardians) | Label drift. | Nothing |

**Never assume (added T11):**
- Never assume a student can reach their own section — verify on `students/me` first.
- Never PUT a partial diary body.
- Never treat a diary 409 as "already saved" — it means the save was rejected.
- Never expect breaks in timetable slot responses.

### 2026-09-23 — accounts list (verified live)

| Call | Result |
|---|---|
| `GET /api/staff?size=` | Spring page. Rows carry `userId` (null = no login), `employeeCode`, `designation`, `status` |
| `GET /api/students?size=` | Spring page, same `userId` rule |
| `GET /api/guardians/student/{id}` | Bare array of `{guardian:{id, firstName, lastName, userId}, relationship, isPrimary, canPickup, isEmergencyContact}` |
| `GET /api/guardians` | **405 Method Not Allowed** — there is no guardians list |

🔴 **There is no endpoint that lists LOGINS.** `GET /api/users` does not
exist; `/api/users/*` is provision / reset-password / roles only. So the
admin's accounts screen is assembled from person records, and a login that
was never linked to a record cannot be shown at all.

**Added to the T11 open items for Ali:**
6. `GET /api/users` (or `GET /api/guardians`) — so the admin can see every
   login, including ones not linked to a person record.

---

## T13 Batch A — academic setup — VERIFIED LIVE 2026-09-24

Local `bootRun` build of Ali's backend (pulled 2026-09-17). Every line below
is an observed request/response as `admin` in `test-school`. OpenAPI was used
only to find candidate paths.

### Academic years — `/api/academic-years`

| Call | Shape |
|---|---|
| `GET ?size=` | Spring page. Row: `{id, campusId, name, startDate, endDate, current}` |
| `POST` | requires `campusId`, `name`, `startDate`, `endDate` (all 400 if absent) → **201** |
| `PUT /{id}` | same body → 200 |
| `DELETE /{id}` | 204 |

🔴 **`current` is READ-ONLY. There is no way to set the current year.**
Sending `current: true` on POST → row is created with `current: false`.
Sending it on PUT → ignored, row stays `false`. `POST /{id}/current`,
`/set-current`, `/activate` all 404. Only one year (`2025-26`) is current and
nothing in the API can change that.

⚠️ Names are **not unique** — two years called "PROBE 2027-28" were created
back to back, both 201.

### Classes — `/api/classes`

`GET ?size=` page; row `{id, campusId, name, levelOrder}`.
`POST` requires `campusId`, `name`; `levelOrder` optional → 201.
`PUT /{id}`, `DELETE /{id}` exist.

### Sections — `/api/sections`

Row: `{id, classId, academicYearId, name, classTeacherId, defaultRoomId, capacity}`.
`POST` requires `classId`, `academicYearId`, `name`; `capacity` and
`classTeacherId` optional and both are honoured → 201.

🔴 **`?classId=` is IGNORED** — filtering by a real class returned sections of
other classes, and a bogus UUID returned all 3 rows (control). Sections must
be grouped client-side, like B-02's search.

### Subjects — `/api/subjects`

Row `{id, name, code}`. `POST` requires `name` only (`code` optional, no
`campusId`) → 201.

### Teaching assignments — `/api/teaching-assignments`

`GET /section/{sectionId}` → page. Row carries **ids only**
(`{id, staffId, sectionId, subjectId, academicYearId}`) — no names, so the
screen must join staff and subject lists client-side.
`POST` requires all four ids → 201. Duplicate on the same four → **409**
`"Conflicts with existing data"`.

🔴 **Create-only.** `PUT /{id}` and `DELETE /{id}` are **404** — an
assignment cannot be edited or removed. A wrong teacher is permanent.

### Timetable periods — `/api/timetable/periods`

`GET ?campusId=` (**required**) → **bare array**, `{id, name, startTime,
endTime, sortOrder, isBreak}`. `POST` requires `campusId`, `name`,
`startTime`, `endTime`, `sortOrder`; `isBreak` accepted → 201.

✅ **`isBreak` is on the PERIOD** (school-wide), not on the slot.

🔴 **Create-only**: `PUT`/`DELETE` on `/periods/{id}` are 404. A period with a
typo is permanent, and it applies school-wide.

### Rooms — `/api/timetable/rooms`

`GET ?campusId=` → bare array. `POST {campusId, name, capacity}` → 201,
`roomType` defaults to `"classroom"`. **Create-only** (DELETE 404).

### Timetable slots — `/api/timetable/slots`

`POST {sectionId, academicYearId, periodId, dayOfWeek, subjectId,
teacherStaffId, roomId?}` → 201
`{id, sectionId, dayOfWeek, periodId, subjectId, teacherStaffId, roomId,
isAutoGenerated}`.
`PUT /{id}` → 200 and is a **FULL REPLACE** (omitting `roomId` set it to
null — same trap as the diary). `DELETE /{id}` → 204.

**Clash responses — 409, with a message that names the cause:**

| Case | Message |
|---|---|
| Teacher busy that day/period | `"Teacher is already scheduled at that day/period"` |
| Room booked that day/period | `"Room is already booked at that day/period"` |
| Cell already filled (same section/day/period) | same "Teacher…" message |
| Missing required field (e.g. no `academicYearId`) | `"Conflicts with existing data"` — a **409, not a 400** |

⚠️ The body carries **no id of the conflicting slot**, so the app can say
*that* a teacher clashes but not *with which class*.

⚠️ `POST /periods {}` and `POST /slots {}` also answer **409**, not 400 —
validation failures and genuine conflicts are indistinguishable by status
alone on these two endpoints.

### Permissions

`teacher1` → **403** on `POST /api/classes`. Setup is admin-only, as expected.

### 🔴 Deletes cascade nothing — verified, and destructive

- `DELETE /api/classes/{id}` succeeded (204) while the class still had a
  section. The section survived, pointing at a class that no longer exists.
- `DELETE /api/subjects/{id}` succeeded while a teaching assignment
  referenced it; the assignment survived, referencing a dead subject.

### Test-data note

Two probe rows could not be removed, because those endpoints have no delete:
a period named **"PROBE Break"** (sortOrder 9) and a room **"PROBE Room 1"**
in `test-school`.

### T13 open items for Ali

7. **Set the current academic year** — no endpoint exists; `current` is
   read-only. Nothing else in onboarding works without it.
8. **`PUT`/`DELETE` for teaching assignments** — currently create-only, so a
   wrong assignment cannot be corrected.
9. **`PUT`/`DELETE` for timetable periods and rooms** — same.
10. **Clash responses should identify the conflicting slot** (id, or section +
    subject), so the admin can be told what they clash with.
11. **Validation should be 400, not 409**, on `/timetable/periods` and
    `/timetable/slots`.
12. **Deletes should refuse or cascade** rather than orphaning sections and
    assignments.
13. **`?classId=` on `/api/sections`** is ignored — either honour it or drop it.

#### `current` is NOT derived from the date range — probed 2026-09-24

Tested on 2026-09-24 with two new years:

| Year | Range | `current` |
|---|---|---|
| PROBE SPANS TODAY | 2026-09-01 → 2027-06-30 (includes today) | **false** |
| PROBE PAST | 2020-08-01 → 2021-05-31 | false |
| 2025-26 (seeded) | 2025-08-01 → 2026-05-31 (**expired**) | **true** |

So the flag is stored, not computed: a year covering today is not current,
and an expired year stays current. It is only ever set at seed/bootstrap
time. **Open item 8 stands — there is no way to change the current year.**

---

# T14 Batch B — Finance (verified live 2026-09-24)

All of it measured against `http://localhost:8080` as `admin` /
`test-school`. Every earlier note about the fee surface was re-checked, not
trusted.

## ⚠️ This module speaks snake_case

Unlike every other part of this API, fee RESPONSES use `snake_case`
(`total_amount`, `paid_amount`, `due_date`, `is_recurring`, `fee_head_id`).
REQUESTS still take `camelCase` (`invoiceId`, `feeHeadId`, `academicYearId`).
Two exceptions inside the same payloads, presumably computed fields:
`taxAmount`/`total` on a plan, and `receiptId`/`receiptNumber`/
`idempotentReplay` on a payment.

## The endpoints that exist

| Method + path | Answer |
|---|---|
| `GET /api/fee/heads` | bare array |
| `POST /api/fee/heads` | 201, the head |
| `GET /api/fee/plans` | bare array (no `items`) |
| `GET /api/fee/plans/{id}` | plan **with** `items`, `subtotal`, `taxAmount`, `total` |
| `POST /api/fee/plans` | 201, plan with items |
| `POST /api/fee/plans/{id}/generate` | 200 `{total, generated, skipped}` |
| `GET /api/fee/invoices` | custom envelope `{size, content, page, totalElements}` |
| `GET /api/fee/invoices/{id}` | full invoice **with `lines`** |
| `POST /api/fee/payments` | 201, payment `pending_approval` |
| `GET /api/fee/payments/pending` | bare array |
| `POST /api/fee/payments/{id}/approve` | 200 + **`receiptId`, `receiptNumber`** |
| `POST /api/fee/payments/{id}/reject` | 200 |
| `GET /api/fee/receipts/{receiptId}` | 200, the receipt |
| `GET /api/fee/reports/collection` | `{totalInvoiced, totalCollected, outstanding, byClass[]}` |
| `GET /api/fee/reports/defaulters` | bare array, one row per unpaid/partial invoice |

**Absent** (404/405, all probed): `/api/fee/structures`, `/api/payments*`,
`/api/fee/receipts` (list), `/api/fee/heads/{id}`, `/api/fee/plans/{id}/items`,
`/api/fee/invoices/{id}/payments`, `/api/fee/payments/{id}` (by id),
invoice `PUT`/`DELETE`/`cancel`, payment `void`/`reverse`/`DELETE`,
any receipt PDF.

## 🔴 Money is a JSON number with 2 decimal places

`5500.00`, `0.01`, `1500.00`, `tax_rate: 5.50`. Dart's `jsonDecode` turns
these into `double` **before any of our code sees them**, so the app decodes
money by pre-quoting those keys in the raw response text and parsing to
integer paisa. See `MoneyJson` / `Money`.

The server **rounds to 2dp, half-up**: posting `amount: 1.005` stored
`1.01`. So the form restricts input to 2 decimals rather than letting the
server silently change the number.

**Server-computed totals** — `subtotal`, `tax_amount`, `total_amount`,
`paid_amount` on an invoice, `subtotal`/`total` on a plan, and every figure
in both reports. The app renders them; it never adds them up itself.

## Payments: record, then approve — and then it is permanent

1. `POST /api/fee/payments` → status `pending_approval`. The money is NOT
   counted yet: the invoice's `paid_amount` does not move.
2. `POST /api/fee/payments/{id}/approve` → status `approved`, a receipt is
   created, and the invoice's `paid_amount` and `status` update server-side.
3. `POST .../reject` works **only before approval** — after it,
   `400 "Payment is already approved"`.

🔴 **An approved payment cannot be undone.** No void, no reverse, no delete,
no invoice cancel or edit. It also cannot be READ by id afterwards (404) —
once approved it is reachable only through its receipt. So there is no
correction path in this API at all, and the UI offers none (D-19, ADR-0008).

### `POST /api/fee/payments` request

| Field | Verified behaviour |
|---|---|
| `idempotencyKey` | **required, and must be a UUID.** A non-UUID answers `400 "Malformed request body"` — a misleading message that cost real time to diagnose |
| `invoiceId` | required |
| `amount` | required, `> 0`, and `<=` outstanding — `400 "Amount 999999.99 exceeds outstanding balance 5499.00"` |
| `source` | `MANUAL_CASH` or `MANUAL_BANK` **only**. Anything else → 400. Omitting it defaults to `MANUAL_CASH` |
| `reference` | free text, stored and returned |
| a payment DATE | **impossible.** `receivedAt`, `paidAt`, `paymentDate` and `date` are all silently ignored; `received_at` is always server-now |

`method`, `paymentMethod`, `sourceType`, `referenceNumber`, `txnReference`
and `note` are all silently ignored — an unknown field never errors, so a
wrong field name looks like it worked.

## Invoices

Statuses observed end-to-end: `unpaid` → `partial` → `paid`. There is **no
overdue status** — an invoice due 2026-07-10 still reads `unpaid` today, so
"overdue" is derived from `due_date` on the client.

Filters, each with a bogus-id control:

| Parameter | Honoured? |
|---|---|
| `classId` | **yes** (bogus id → empty) |
| `status` | **yes** (`status=zzz` → empty) |
| `period` | **yes** |
| `page`, `size` | yes |
| `sectionId` | 🔴 **ignored** — bogus id returned the row anyway |

`?classId=` on `/api/fee/plans` is **ignored** too.

## Generation is idempotent per period

`POST /api/fee/plans/{id}/generate {"period":"2029-01"}` returned
`{total:1, generated:1, skipped:0}`, and re-running the same period on the
seeded plan returned `{total:1, generated:0, skipped:1}`. So a second run
does not duplicate invoices. It still cannot be undone — there is no invoice
delete — and the confirm step says both things.

`period` is required (`400 {"period":"must not be blank"}`). The call takes
no `academicYearId`: the **plan** carries one, set explicitly at creation.

## 🔴 The collection report ignores its filters

`?period=1999-01` and `?academicYearId=…` returned **identical** figures to
the unfiltered call. It is an all-time, whole-school total. The screen
therefore states that scope rather than offering a filter that does nothing.

`/reports/defaulters` **does** honour `classId` and `period` (both
controlled), and excludes paid invoices.

## 409 means "something was wrong", not "conflict" — again

`POST /api/fee/heads {}` and `POST /api/fee/plans` missing `classId`/
`academicYearId`/`campusId` both answer
`409 "Conflicts with existing data"`. Same trap as the timetable (T13).
Meanwhile `POST /api/fee/plans` with an empty `items` array answers a
helpful `400 "A fee plan needs at least one item"`. Status alone cannot be
trusted on this surface.

## The academic year, and why fees escape the bug

`/api/academic-years` still reports the **expired** 2025-26
(ends 2026-05-31) as `current: true`. Anything resolving "the current year"
server-side is resolving to last year.

Fees are safe from it: a fee plan stores an explicit `academic_year_id`
given at creation, generation keys off the plan, and neither report resolves
a year at all (they ignore the parameter). The app **always passes the year
explicitly** and never relies on `current`.

## Test-data note

`test-school` now permanently holds probe rows that no endpoint can delete:
fee heads **PROBE Head A/B/C**, **PROBE Plan 2**, its generated 2029-01
invoice (paid, receipt `RCP-2026-002`), and one PKR 1.00 approved payment
against the seeded 2026-07 invoice (`RCP-2026-001`) which moved it to
`partial`. Pending probe payments were all rejected. Add to the purge list.

### T14 open items for Ali

14. **A correction path for money.** Approved payments and issued invoices
    are permanent — no reversal, no credit note, no cancel. A mistyped
    amount is currently unfixable.
15. **The payment date cannot be recorded.** Fees are collected in cash and
    entered later; `received_at` being server-now makes the ledger wrong.
16. **No payment history per invoice.** With no `/invoices/{id}/payments`
    and no payment-by-id, an invoice shows only a `paid_amount` total — the
    accountant cannot see what made it up.
17. **`source` allows only `MANUAL_CASH`/`MANUAL_BANK`** — no cheque,
    card or online, which Pakistani schools do take.
18. **The collection report ignores `period` and `academicYearId`.**
19. **`?sectionId=` on `/api/fee/invoices`** is ignored — honour or drop it.
20. **A non-UUID `idempotencyKey` answers "Malformed request body"**, which
    points at the wrong problem entirely.
21. **Validation answers 409** on `/fee/heads` and `/fee/plans`.
22. **No receipt PDF** anywhere — parents expect a printable receipt.


---

# T15 Batch C — Academic loop (verified live 2026-09-25)

Measured against `http://localhost:8080` as `admin` / `test-school`, with
`parent1`, `teacher1` and `student1` used for the permission checks. Paths
were located in the running API's own `/v3/api-docs` and then **every one
verified with live requests** — the published schemas are wrong in at least
one place (see marks).

## 🔴 Two of this batch's screens have NO backend at all

Confirmed by listing all 130 published paths:

- **Grade schemes and bands — nothing.** No `/api/grade-schemes`, no
  `/api/grading/*`, no band endpoint of any kind. `POST /api/exams` accepts
  a `gradeSchemeId` field that **there is no way to populate**.
  Grades are nevertheless assigned (85 → `A` / 3.70, 70 → `B` / 3.00) from a
  scheme seeded somewhere out of reach, which can be neither listed nor
  edited.
- **Subject resources — nothing.** No resource, material or file endpoint,
  and **no upload endpoint anywhere in the API**. Not even link-only is
  possible, because there is nothing to store a link in.

The 130 paths do include `assignments` (11), `complaints` (8),
`notifications` (4) and `staff-attendance` (5), which are not part of this
batch.

## Exams

| Method + path | Answer |
|---|---|
| `GET /api/exams` | bare array; `?academicYearId=` and `?status=` both honoured (bogus-value controls → `[]`) |
| `POST /api/exams` | 201 |
| `POST /api/exams/{examId}/subjects` | 201 — a "paper" |
| `POST /api/exams/subjects/{examSubjectId}/marks` | 200 — **returns the computed result** |
| `POST /api/exams/subjects/{examSubjectId}/marks/bulk` | 200 `{errors, successCount, errorCount}` |
| `POST /api/exams/{examId}/publish` | 200 `{reportCardsGenerated, resultsPublished, examId, status}` |
| `GET /api/exams/{examId}/results/section/{sectionId}` | bare array of per-student results |
| `GET /api/exams/{examId}/results/student/{studentId}` | one result **with `subjects[]`** |
| `GET /api/exams/{examId}/report-card/{studentId}` | `{generatedAt, available, status}` |

**Absent** (404/405, all probed): `GET /api/exams/{id}`,
`GET /api/exams/{id}/subjects`, `GET …/marks`, `PUT`/`DELETE` on an exam,
`DELETE` on a paper, `POST …/unpublish`, and every report-card file path
(`/pdf`, `/download`).

### ✅ The academic year is REQUIRED, not resolved

`POST /api/exams {}` → `400 {"campusId":"must not be null",
"name":"must not be blank","academicYearId":"must not be null"}`.

**So the current-year bug does NOT apply to exam creation, and exam creation
is not blocked.** The app passes the year explicitly, as it does everywhere
else. Note also that validation here is a proper **400 with per-field
details** — far better than the 409s on fees and the timetable.

`term` is an enum. Verified by exhaustive probe:

- **Accepted:** `weekly`, `monthly`, `mid_term`, `first_term`, `final`,
  `annual`
- Rejected: `mid`, `midterm`, `term1`, `term_1`, `quarterly`, `half_yearly`,
  `unit`, `test`, `pre_board`, `board`, `sessional`

An invalid `term` answers the unhelpful `400 "One or more fields have an
invalid value"` with no field name — it cost a round of probing to find that
`term` was the culprit rather than a missing id.

Responses are **snake_case** (`result_date`, `academic_year_id`,
`max_marks`), like the fee module and unlike remarks.

### 🔴 The marks schema in `/v3/api-docs` is the WRONG DTO

`POST …/marks` publishes the **staff-attendance** schema
(`staffId`, `attendanceDate`, `status`, `checkInTime`…). This is the same
springdoc collision already recorded for T8's student attendance. The real
shape, found by live 400-validation:

| Field | Behaviour |
|---|---|
| `studentId` | required — `400 {"studentId":"must not be null"}` |
| `marksObtained` | required **unless absent** — `400 "marksObtained is required unless absent"` |
| `isAbsent` | boolean |

Validated server-side, with a message worth showing verbatim:
`400 "marksObtained 150 exceeds max 100.00"`. A student not enrolled in the
paper's section is refused: `400 "Student is not enrolled in this section"`.

**Bulk takes a BARE ARRAY**, not an object — `{}`, `{marks:[]}` and
`{rows:[]}` all answer `400 "Malformed request body"`.

### ✅ Results are computed on marks entry — no publish needed

A single mark POST returns the whole recomputed result immediately:

```
{"exam_id":…,"student_id":…,"total_marks":85.00,"total_max":100.00,
 "percentage":85.00,"grade":"A","grade_point":3.70,"position":1,
 "result_status":"pass","published_at":null}
```

So **the app computes nothing**: totals, percentage, grade, grade point,
position and pass/fail are all the server's, exactly as with money.

### 🔴 Publishing locks the marks, permanently

Re-posting a mark for the same student **updates** it — verified, 85 → 85.5,
no conflict. So marks ARE correctable, unlike fee payments.

But after `POST /api/exams/{id}/publish`:

```
400 "Exam is published — marks are locked and can no longer be changed"
```

and there is **no unpublish route** (404). Publishing is idempotent
(running it twice returns the same counts), but it cannot be reversed. The
marks screen states this before saving and publish is a deliberate,
confirmed action.

### Report cards exist but are not files

Before publish: `404 "ReportCard not found: …"`.
After publish: `{"generatedAt":"…","available":true,"status":"generated"}`.

**Re-verified: there is still no file key**, and `/pdf` and `/download` are
both 404. So no download affordance ships.

## 🔴 Remarks — a real access-control defect

Shape is **camelCase** here (unlike exams and fees), and carries
`authorName`. `PUT` and `DELETE /api/remarks/{id}` both exist, so remarks
are the one thing in this batch that can be corrected.

`isParentVisible` was tested with one private and one public remark:

| Reader | Sees private remark? | Other student's remarks? |
|---|---|---|
| admin | yes (correct) | n/a |
| teacher1 | yes (correct) | n/a |
| **parent1** | **no — correctly filtered** | **no — 404, correctly scoped** |
| **student1** | 🔴 **YES** | 🔴 **YES** |

So the flag IS enforced server-side **for parents**, which is what it is
named for — the screen is therefore not blocked.

But the **student path has neither check**: a student token read another
student's remarks, including one flagged `isParentVisible: false`. That is a
broken object-level authorisation defect (IDOR), not a missing feature.
Consequences for this batch:

1. The teacher-facing copy must say exactly who can see a remark. It must
   **not** claim the note is private in general — only that parents cannot
   see it.
2. **No student-facing remarks surface is built** until this is fixed.
3. Raised as the top item for Ali.

`GET /api/remarks/section/{id}` is 403 for parent and student, correctly.

## Syllabus

| Method + path | Answer |
|---|---|
| `GET /api/syllabus/chapters` | chapters **with nested `topics[]`** — one call |
| `POST /api/syllabus/chapters` | 201 |
| `POST /api/syllabus/topics` | 201 |
| `POST /api/syllabus/coverage` | 201 `{status, idempotent, logId}` |
| `GET /api/syllabus/progress` | **server-computed progress** |

`GET /chapters` and `/progress` both REQUIRE `subjectId`, `classId` and
`academicYearId`; `/progress` also requires `sectionId`. A missing one is a
clear `400 "Missing required parameter 'subjectId'"`.

### ✅ Progress is computed server-side — the app must not re-derive it

```
{"coveredTopics":1,"coveredChapters":1,"percentage":100.00,
 "totalTopics":1,"totalChapters":1,
 "chapters":[{"name":"PROBE Chapter 1","status":"complete","topics":1,"covered":1}]}
```

⚠️ This corrects the T15 brief, which assumed the server does not provide it
and that client-side computation was correct here. It does provide it, so
the same rule as money and results applies: render it, do not compute it.

### Coverage re-marking UPDATES, it does not conflict

Posting the same `(topicId, sectionId)` again returned 201 with a new
`logId` and no 409 — the unique constraint behaves as an upsert. Progress
reflects the LATEST status: a topic marked `partial` counted 0 covered, and
re-marking it `covered` moved progress to 100%.

⚠️ `clientUuid` is **REQUIRED** on a coverage POST — omitting it answers
`400 "clientUuid is required (offline-safe idempotency)"`. This was missed
by the manual probe (which happened to send one) and caught by the live
end-to-end test. Same idempotency key attendance marks carry.

Coverage `status` is **lowercase only**: `covered` and `partial` are
accepted; `COVERED` and `pending` are both
`400 "Invalid coverage status: …"`.

## Numbers

Marks, percentages and grade points all arrive as **JSON numbers with two
decimals** (`85.50`, `3.70`, `100.00`), exactly like money. They get the
same exact-decimal treatment: a mark rendering as `17.999999` is the same
class of defect as a rupee of drift, so nothing here goes through a
`double` either.

## Test-data note

`test-school` now permanently holds, none of it deletable — there is no
delete for an exam, a paper, a mark or a coverage log:

- exams **PROBE noterm** (published, marks locked) and **PROBE term final**,
  plus **PROBE t …** exams for each accepted `term` value (6 of them);
- one exam paper on 5-A / Mathematics with a mark of 70 for Ali Khan, and
  the report card generated by publishing;
- chapter **PROBE Chapter 1** with **PROBE Topic 1**, and three coverage
  logs against it;
- remarks **PROBE private note** / **PROBE public note** on Ali Khan and
  **PROBE other-student private** on Test ImportOne (these three CAN be
  deleted — remarks have a DELETE).

### T15 open items for Ali

23. 🔴 **A student can read any student's remarks, including ones flagged
    `isParentVisible: false`.** No ownership check and no visibility filter
    on the student path, while the parent path has both. Privacy defect —
    top priority.
24. **No grade-scheme or band endpoints at all**, yet `POST /api/exams`
    takes a `gradeSchemeId` and grades are assigned from a scheme nothing
    can list or edit.
25. **No subject-resource endpoints, and no file-upload endpoint anywhere.**
26. **Marks cannot be read back.** `GET …/marks` is 405 and papers cannot be
    listed (`GET /api/exams/{id}/subjects` → 405), so a half-finished marks
    entry cannot be resumed.
27. **Exam papers cannot be listed**, so the `examSubjectId` that marks
    entry needs is only available at the moment of creation.
28. **No unpublish**, and publishing locks marks permanently.
29. **No delete or edit for an exam or a paper** — a typo is forever.
30. **`GET /api/exams/{id}` does not exist** (404), only the list.
31. **The published `/v3/api-docs` schema for marks is the staff-attendance
    DTO** — the same springdoc collision as T8's attendance.
32. **An invalid `term` answers "One or more fields have an invalid value"**
    with no field name.
33. Exam responses are snake_case while remarks are camelCase.


---

# T16 Batch D — Operations (verified live 2026-09-26/27)

Measured against `http://localhost:8080` with `admin`, `parent1`,
`teacher1` and `student1`, because three of the questions in this batch are
about who can see what and cannot be answered from one account.

## ✅ Complaints get the privacy model RIGHT

Worth stating plainly, because T15's remarks did not (open item 23). Every
check below was run with real tokens:

| Check | Result |
|---|---|
| Parent reads another user's complaint | **404** — correctly scoped |
| Teacher reads a parent's complaint | **404** |
| Parent lists all complaints | **403** |
| Parent reads a complaint's comments they do not own | **404** |
| **Parent sees an `is_internal` comment** | 🟢 **NO — filtered server-side** |
| **Parent posts `isInternal: true`** | 🟢 **Downgraded to `false` by the server** |
| Anonymous complaint, creator's own response | `raised_by_user_id: **null**` |
| **Anonymous complaint, ADMIN's detail view** | 🟢 `raised_by_user_id: **null**` |

So the internal-comment feature **ships** (it is enforced, not advisory),
and anonymity is **real** — the raiser's id is not stored, not merely
hidden. Neither had to be blocked.

## Complaints

| Method + path | Answer |
|---|---|
| `GET /api/complaints` | admin only; `{content, size, page, totalElements}` |
| `POST /api/complaints` | 201 |
| `GET /api/complaints/my` | the caller's own, paged |
| `GET /api/complaints/overdue` | bare array |
| `GET /api/complaints/{id}` | full detail |
| `GET,POST /api/complaints/{id}/comments` | bare array / 201 |
| `PUT /api/complaints/{id}/assign` | `{staffId}` |
| `PUT /api/complaints/{id}/status` | `{status, resolutionNote}` |
| `PUT /api/complaints/{id}/rate` | satisfaction |

Responses are **snake_case** (`raised_by_user_id`, `is_anonymous`,
`assigned_to_staff_id`, `due_by`, `is_internal`); requests are camelCase.

Vocabularies, each found by exhaustive probe — an invalid value answers a
**400 that names the allowed set**, which is far better than the fee and
timetable modules:

- **category**: `academic`, `fee`, `transport`, `staff_behaviour`,
  `facility`, `other`. (`staff` and `discipline` are rejected.)
- **priority**: `low`, `medium`, `high`. (`urgent`/`critical` rejected.)
- **status**: starts at `open`; settable values are `in_progress`,
  `resolved`, `closed` only. `open` cannot be set back.

`POST` requires `campusId`, `category`, `subject`, `description`.
`aboutStudentId`, `priority` and `isAnonymous` are optional.

## Notifications

| Method + path | Answer |
|---|---|
| `GET /api/notifications` | paged `{content}`; `?unreadOnly`, `?page`, `?size` |
| `GET /api/notifications/unread-count` | `{unreadCount: N}` |
| `PUT /api/notifications/{id}/read` | marks one |
| `PUT /api/notifications/read-all` | `{marked: N, status: "ok"}` |

⚠️ **camelCase here** (`recipientUserId`, `createdAt`, `readAt`) while
complaints and staff attendance are snake_case. Three conventions now
coexist in one API.

Read state **persists** — `readAt` is null until marked, and `read-all`
reported `{marked: 4}`. Notifications are genuinely produced by the system:
commenting on a complaint created one for the admin and one for the
complainant, unprompted.

🔴 **`data` is null on every notification** (checked across all of them),
and there is no target id of any kind on the row. **So a notification
cannot be opened onto its subject** — the "tap to go there" the bell
implies does not exist. No such affordance ships; the screen says so.

🔴 **No preferences endpoint** — `/api/notifications/preferences` is 404, and
nothing else matches. Per-category toggles cannot ship.

Only one `category` value has been observed in practice (`admin`), so the
grouping the screen does is correct but currently degenerate.

## Staff attendance

| Method + path | Answer |
|---|---|
| `GET /api/staff-attendance/daily?date=` | **a ready-made roster** |
| `POST /api/staff-attendance` | 201 |
| `POST /api/staff-attendance/bulk` | bulk |
| `GET /api/staff-attendance/staff/{id}` | one member's history |
| `GET /api/staff-attendance/staff/{id}/monthly` | monthly summary |

`/daily` is **better than the student equivalent**: it returns the whole
marking surface in ONE call, already counted —
`{date, totalStaff, unmarked, present, absent, records[]}`, each record
carrying `staff_id`, `first_name`, `last_name`, `employee_code` and a
`status` of `unmarked` where nothing is recorded. No two-call join, unlike
`/api/enrollments/section/{id}` + `/api/students`.

`POST` requires `staffId`, `attendanceDate`, `status` **and `clientUuid`** —
the same device-generated idempotency key student attendance uses.

🔴 **The status vocabulary is NOT the same as student attendance.** Probed
exhaustively:

| Student attendance | Staff attendance |
|---|---|
| present, absent, late, leave, **excused** | present, absent, late, leave, **half_day** |

Five values each, four shared. `excused` is rejected for staff and
`half_day` is rejected for students. The marking ERGONOMICS are reusable;
the vocabulary is not, and treating them as one enum would silently send an
invalid status.

## Parent progress — what T9 left on the table

`GET /api/parent-progress/student/{id}` returns far more than the
`attendanceStatus` T9 used:

- `diaryEntries[]`
- `remarks[]` — **server-filtered to `isParentVisible: true`** (verified:
  the private probe remark does not appear)
- `attendanceStats` — `{totalDays, present, absent, late, leave, excused,
  percentage, belowThreshold}`
- `latestResult` — `{examName, percentage, grade, position, …}`
- `className`, `sectionName`, `studentName`, `date`

camelCase throughout.

## Test-data note

`test-school` now holds **11 probe complaints** (`PROBE named`,
`PROBE anon`, `PROBE student-owned`, `PROBE cat …`, `PROBE pri …`), their
comments, and staff-attendance records for 2026-09-26 on `EMP-001`. There is
no delete for a complaint, a comment or an attendance record. Add to the
purge list.

### T16 open items for Ali

34. **Notifications carry no target.** `data` is null on every row and
    there is no subject id, so a notification cannot be opened onto the
    thing it is about — which is most of what a notifications centre is for.
35. **No notification preferences endpoint**, so a user cannot turn a
    category off.
36. **Three JSON conventions in one API** — notifications camelCase,
    complaints and staff attendance snake_case, earlier modules mixed.
37. **Staff and student attendance use different status vocabularies**
    (`half_day` vs `excused`) for what is otherwise the same act.
38. `?status=` on `/api/complaints` accepts an unknown value and answers
    200 rather than 400, unlike the write paths which validate properly.

