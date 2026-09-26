/// Single source for the backend base URL — nothing under `lib/` should
/// hardcode `smart-ems-backend-production.up.railway.app` anywhere else.
///
/// **All paths below are CONFIRMED** against the live Railway deployment's
/// OpenAPI document (`GET /v3/api-docs`, publicly readable, fetched
/// 2026-08-03) and spot-checked with live requests. See
/// `BACKEND_CONTRACT.md` for the recorded evidence. This replaces T6's
/// guessed paths — notably `mePath`, which was WRONG (`/me`; the real
/// endpoint is `/auth/me`).
abstract final class ApiConfig {
  /// ⚠️ TEMPORARILY pointed at the local backend (2026-09-17): the Railway
  /// deployment is down (`x-railway-fallback: true` — no app at that
  /// hostname, not a route issue). Local backend re-verified to carry every
  /// endpoint this app depends on (`institution/me`, `guardians/me`,
  /// `forcePasswordChange`, etc.) — see BACKEND_CONTRACT.md.
  /// Swap back to the Railway URL below once it's redeployed.
  static const String baseUrl = 'http://localhost:8080';
  // static const String baseUrl =
  //     'https://smart-ems-backend-production.up.railway.app';

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);

  /// CONFIRMED. `POST` a [LoginRequest]-shaped body:
  /// `{institutionCode, username, password}` (all three required).
  /// Returns `{accessToken, refreshToken, expiresIn}`.
  static const String loginPath = '/auth/login';

  /// CONFIRMED. `POST {refreshToken}` → `{accessToken, refreshToken,
  /// expiresIn}`. Note the response carries a **new refresh token** —
  /// the backend rotates them, so the new one must be stored.
  static const String refreshPath = '/auth/refresh';

  /// CONFIRMED. `POST {refreshToken}` to invalidate the session server-side.
  static const String logoutPath = '/auth/logout';

  /// CONFIRMED (live, 2026-08-03). Returns the authenticated USER ACCOUNT:
  /// `{roles: [...], userId, tenantId}`.
  ///
  /// Returns **200 whenever the token is valid**, so it can never produce
  /// the D-17 orphan case on its own — it answers "is this token good and
  /// who is it", not "does a person record exist". See
  /// [personRecordPathFor].
  static const String mePath = '/auth/me';

  /// CONFIRMED (live, 2026-08-03). The person-record endpoints, and the
  /// only ones that produce the D-17 orphan case. Verified by calling both
  /// with a valid admin token that has no person record:
  /// `404 {"message":"Staff record linked to this login not found: <uuid>"}`.
  static const String staffMePath = '/api/staff/me';
  static const String studentMePath = '/api/students/me';

  /// Which person-record endpoint (if any) a set of role claims requires.
  ///
  /// `null` means this role legitimately has no person record and must NOT
  /// be shown `UnlinkedProfileState` — an institution admin is a real,
  /// fully-functional user without a staff or student row, so treating its
  /// 404 as the orphan case would lock out exactly the person who is
  /// supposed to fix orphaned accounts.
  ///
  /// Role vocabulary observed/reported: `super_admin`, `owner`, `admin`,
  /// `teacher`, `staff`, `parent`, `student`. `parent` maps to null because
  /// the API exposes no `/api/guardians/me` — see `BACKEND_CONTRACT.md`.
  static String? personRecordPathFor(Iterable<String> roles) {
    if (roles.contains('student')) return studentMePath;
    if (roles.contains('teacher') || roles.contains('staff')) {
      return staffMePath;
    }
    // T9: parents ARE orphan-checkable now that `/api/guardians/me` exists
    // and returns the same 404 shape. This closes the gap T7 flagged.
    if (roles.contains('parent')) return guardiansMePath;
    return null;
  }

  /// The person-record endpoints, as a set, for error classification.
  static const Set<String> personRecordPaths = {
    staffMePath,
    studentMePath,
    guardiansMePath,
  };

  /// CONFIRMED, and public (no auth) — useful as a reachability probe.
  static const String healthPath = '/health';

  // --- Attendance (T8) -------------------------------------------------------
  // ⚠️ Shapes below were confirmed by LIVE 400-validation, NOT from the
  // OpenAPI document, which publishes the STAFF attendance schema for these
  // student endpoints (springdoc collided two same-named inner DTOs). See
  // BACKEND_CONTRACT.md before changing any field name here.

  /// `POST {clientUuid, studentId, sectionId, attendanceDate, status}` —
  /// the single-mark / correction endpoint.
  static const String attendancePath = '/api/attendance';

  /// `POST {sectionId, attendanceDate, rows:[{studentId,status,clientUuid}]}`
  static const String attendanceBulkPath = '/api/attendance/bulk';

  /// `GET .../{sectionId}?date=` → a SUMMARY (counts + records), not a
  /// roster: it is empty before anything is marked.
  static const String attendanceSectionPath = '/api/attendance/section';

  /// `GET .../{sectionId}` → enrolled students. Carries `studentId` and
  /// `rollNumber` but NO names — names require [studentsPath].
  static const String enrollmentsSectionPath = '/api/enrollments/section';

  static const String studentsPath = '/api/students';

  // --- Parent / guardian (T9) ------------------------------------------------
  /// `GET` → `{guardianId, firstName, lastName, students:[…]}`.
  /// 404 when the login has no guardian record — the D-17 orphan case, same
  /// shape as staff/students. Registered in [personRecordPaths] below so the
  /// error mapper classifies it as `notLinked` rather than a plain error.
  static const String guardiansMePath = '/api/guardians/me';

  /// `GET .../{studentId}` → today's snapshot: name, class, section and
  /// `attendanceStatus` (NULL when the register has not been taken —
  /// "not marked", not absent).
  static const String parentProgressPath = '/api/parent-progress/student';

  /// `GET .../{studentId}?from=&to=` — `from` is REQUIRED. Rows come back
  /// snake_case (`attendance_date`, `status`), unlike the typed DTOs.
  static const String attendanceStudentPath = '/api/attendance/student';

  /// Paged Spring `Page` shape: `{content:[], totalElements, ...}`.
  static const String sectionsPath = '/api/sections';

  // --- Admin (T10) -----------------------------------------------------------
  // Every path and shape below was live-verified 2026-09-18 against the local
  // build. See BACKEND_CONTRACT.md "T10 Part B" for the evidence.

  /// `{id, campusId, name, levelOrder}` — paged.
  static const String classesPath = '/api/classes';

  /// `{id, employeeCode, firstName, lastName, designation, ...}` — paged.
  static const String staffPath = '/api/staff';

  /// `POST {username, password, role, email?}` → `{userId, username, role}`.
  static const String provisionPath = '/api/users/provision';

  /// `POST /api/users/{userId}/reset-password` with `{newPassword}`.
  /// EXISTS on this build (T8 had recorded it as deferred).
  static String resetPasswordPath(String userId) =>
      '/api/users/$userId/reset-password';

  /// `POST /api/enrollments` — `{studentId, academicYearId, sectionId}`.
  static const String enrollmentsPath = '/api/enrollments';

  /// `POST /api/guardians` — `{studentId, firstName, lastName, relationship}`,
  /// plus the optional `userId` that LINKS a provisioned login to the record.
  static const String guardiansPath = '/api/guardians';

  static const String academicYearsPath = '/api/academic-years';

  // --- Academic setup (T13 Batch A) — all verified live 2026-09-24 --------
  /// `GET,POST /api/subjects` — POST needs `name` only.
  static const String subjectsPath = '/api/subjects';

  /// `GET /api/teaching-assignments/section/{id}` (page, ids only) and
  /// `POST /api/teaching-assignments` (all four ids). **Create-only**:
  /// PUT/DELETE are 404, so a wrong assignment is permanent.
  static const String teachingAssignmentsPath = '/api/teaching-assignments';
  static String teachingAssignmentsSectionPath(String sectionId) =>
      '$teachingAssignmentsPath/section/$sectionId';

  /// `GET,POST /api/timetable/periods` — `campusId` REQUIRED on the GET,
  /// bare array back. School-wide, carries `isBreak`. **Create-only.**
  static const String timetablePeriodsPath = '/api/timetable/periods';

  /// `GET,POST /api/timetable/rooms` — bare array. **Create-only.**
  static const String timetableRoomsPath = '/api/timetable/rooms';

  /// `POST /api/timetable/slots`, `PUT/DELETE /slots/{id}`.
  /// 🔴 PUT is a FULL REPLACE (an omitted `roomId` became null).
  /// 🔴 A clash AND a validation failure both answer **409**.
  static const String timetableSlotsPath = '/api/timetable/slots';
  static String timetableSlotPath(String slotId) =>
      '$timetableSlotsPath/$slotId';

  /// `GET /api/guardians/student/{id}` — a bare array of
  /// `{guardian:{id, firstName, lastName, userId}, relationship, isPrimary}`.
  ///
  /// The ONLY way to reach guardians: `GET /api/guardians` is 405 (verified
  /// live 2026-09-23), so there is no "all parents" call.
  static String guardiansOfStudentPath(String studentId) =>
      '/api/guardians/student/$studentId';

  /// `POST /api/diary` — create. Verified live 2026-09-18 (T11).
  ///
  /// 🔴 Keyed by `(sectionId, subjectId, diaryDate)`: a second POST on the
  /// same key is a **409**. Hence edit-first — see `DiaryRepository`.
  static const String diaryPath = '/api/diary';

  /// `PUT /api/diary/{id}` — 🔴 a FULL REPLACE: omitted fields are set to
  /// null (verified live). Always send every field.
  static String diaryEntryPath(String id) => '/api/diary/$id';

  /// `GET /api/diary/section/{id}?date=` — `date` REQUIRED; bare array.
  static String diarySectionPath(String sectionId) =>
      '/api/diary/section/$sectionId';
  static const String campusesPath = '/api/campuses';

  /// `GET .../{sectionId}?academicYearId=` — used only to answer "does this
  /// section have a timetable at all", for the D-15 completeness sort.
  static const String timetableSectionPath = '/api/timetable/section';

  /// 🔴 **SYNCHRONOUS**, despite returning a `jobId`.
  ///
  /// `POST` multipart/form-data, field name `file`, and the response already
  /// carries the FINAL result: `{jobId, status, totalRows, successRows,
  /// errorRows}`. There is nothing to poll. Posting JSON instead of multipart
  /// returns a 500, not a 400.
  ///
  /// ⚠️ CSV headers are **snake_case** (`first_name`, `last_name`,
  /// `admission_number`). camelCase headers fail every row.
  static const String importStudentsPath = '/api/import/students';
  static const String importStaffPath = '/api/import/staff';

  /// `GET` → paged `{rowNumber, message}`. `rowNumber` is 1-indexed and
  /// INCLUDES the header row, so the first data row reports as 2.
  static String importErrorsPath(String jobId) => '/api/import/$jobId/errors';

  /// `GET .../{staffId}/today` → today's periods, camelCase, INCLUDING
  /// `sectionId` as of 2026-08-10. That unblocked Today → marking.
  static const String teacherTimetablePath = '/api/timetable/teacher';

  // --- Institution and account (2026-08-10) ---------------------------------
  /// `GET` → `{id, name, code, timezone, locale, logoUrl, status}`.
  /// `name` is the real display name the app bar shows instead of the code.
  static const String institutionMePath = '/api/institution/me';

  /// `POST {currentPassword, newPassword}` — live-verified shape.
  ///
  /// Succeeding REVOKES ALL SESSIONS, including the one that made the call,
  /// so the app must return to login afterwards rather than assume the
  /// current token still works.
  static const String changePasswordPath = '/api/users/me/change-password';
}
