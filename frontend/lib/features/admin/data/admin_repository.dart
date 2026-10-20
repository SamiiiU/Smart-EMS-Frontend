import 'package:smartems/core/network/paged_get.dart';
import 'package:dio/dio.dart';

import '../../../core/network/api_config.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../domain/admin_models.dart';
import '../domain/people_models.dart';

/// Reads for the admin surfaces.
///
/// Every method throws [LoadFailure], never a raw [DioException] — the same
/// contract T9's repository had to be corrected to honour, so screens can
/// distinguish a real failure from an orphan/empty case.
class AdminRepository {
  const AdminRepository(this.dio);

  final Dio dio;

  Future<List<Map<String, dynamic>>> loadGuardianLinks(String studentId) =>
      _mapped(() async {
        final response = await dio.get<List<dynamic>>(
          '/api/guardians/links/student/$studentId',
        );
        return [
          for (final row in response.data ?? const [])
            Map<String, dynamic>.from(row as Map),
        ];
      });
  Future<void> reviewGuardianLink(
    String id, {
    required String status,
    required String reason,
    Map<String, bool>? categories,
  }) => _mapped(
    () => dio.post<dynamic>(
      '/api/guardians/links/$id/review',
      data: {'status': status, 'reason': reason, 'categories': categories},
    ),
  );

  // --- Campus roles (ADR-011 campus delegation) ---------------------------
  /// The person's explicit campus roles the caller may administer.
  Future<List<CampusRoleGrant>> loadCampusRoles(String userId) =>
      _mapped(() async {
        final res = await dio.get<List<dynamic>>(
          '/api/users/$userId/campus-grants',
        );
        return [
          for (final r in res.data ?? const [])
            CampusRoleGrant.fromJson(r as Map),
        ];
      });

  Future<void> grantCampusRole(
    String userId, {
    required String campusId,
    required String role,
  }) => _mapped(
    () => dio.post<dynamic>(
      '/api/users/$userId/campus-grants',
      data: {'campusId': campusId, 'role': role},
    ),
  );

  Future<void> revokeCampusRole(String userId, String grantId) => _mapped(
    () => dio.delete<dynamic>('/api/users/$userId/campus-grants/$grantId'),
  );

  Future<T> _mapped<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (err) {
      throw mapDioError(err);
    }
  }

  /// Loads every student, then joins enrolment in to get each one's section.
  ///
  /// B-02: there is no server-side search, so the whole set is loaded and
  /// filtered in the client (D-20). `size=500` is a deliberate ceiling, not
  /// a page size — see the note on [loadStudents]'s caller.
  Future<List<AdminStudent>> loadStudents({String? sectionId}) =>
      _mapped(() async {
        final rows = await dio.getAllPages(
          ApiConfig.studentsPath,
          queryParameters: {
            // B-03: `sectionId` and `classId` ARE honoured by this build
            // (verified live 2026-09-18 — a bogus id returns 0 while an
            // unknown param is ignored, which is what makes that sound).
            // Sent server-side because a real filter beats a client one.
            'sectionId': ?sectionId,
          },
        );
        return rows.map(AdminStudent.fromJson).toList();
      });

  Future<List<AdminClass>> loadClasses() => _mapped(() async {
    final rows = await dio.getAllPages(ApiConfig.classesPath);
    return rows.map(AdminClass.fromJson).toList();
  });

  /// The tenant's campuses.
  ///
  /// Needed before a person record can be created: every staff/student POST
  /// carries a `campusId`, and inventing one is not an option. Single-campus
  /// schools are the common case, which is why the wizard resolves this once
  /// rather than asking the admin to choose from a list of one.
  ///
  /// Typed as `dynamic`, not `Map`: this endpoint answered 200 in the live
  /// app yet failed to parse as a Spring page — the first build assumed the
  /// page envelope without verifying it, and a `get<Map>` on a bare JSON
  /// array throws a TypeError, which surfaced as a generic load failure.
  /// Both shapes are accepted so the screen does not hinge on which one
  /// this build returns.
  Future<List<String>> loadCampusIds() async => [
    for (final c in await _loadCampusRowsShared()) c.id,
  ];

  /// Campuses where THIS account holds [permission] (hard-QA BUG-QA-08).
  ///
  /// A Teacher@A + Finance@B account gets both campuses from `/mine`; a fee
  /// screen must act only on B. Rows without a permission list (the plain
  /// fallback endpoint, which only campus.manage holders can read) are kept,
  /// because those callers are institution-wide.
  Future<List<String>> loadCampusIdsWith(String permission) async => [
    for (final c in await _loadCampusRowsShared())
      if (c.permissions == null || c.permissions!.contains(permission)) c.id,
  ];

  Future<List<({String id, Set<String>? permissions})>>
  _loadCampusRowsShared() => _campusRowsInFlight ??= _loadCampusRows()
      .whenComplete(() => _campusRowsInFlight = null);

  /// Shared while on the wire — every tab asks for this at startup.
  static Future<List<({String id, Set<String>? permissions})>>?
  _campusRowsInFlight;

  // Overhaul (route crawl): `GET /api/campuses` needs campus.manage, so scoped
  // roles such as finance staff were refused and their whole Fees screen failed.
  // `/api/campuses/mine` returns exactly the campuses this account may use
  // (every campus for institution-wide roles). The plain list is a fallback only.
  Future<List<({String id, Set<String>? permissions})>> _loadCampusRows() =>
      _mapped(() async {
        Response<dynamic> res;
        try {
          res = await dio.get<dynamic>('${ApiConfig.campusesPath}/mine');
        } on DioException catch (e) {
          if (e.response?.statusCode != 404) rethrow;
          res = await dio.get<dynamic>(
            ApiConfig.campusesPath,
            queryParameters: const {'size': 50},
          );
        }
        final body = res.data;
        final rows = body is List
            ? body
            : (body is Map
                      ? (body['campuses'] ?? body['content']) as List?
                      : null) ??
                  const [];
        return [
          for (final c in rows.whereType<Map<dynamic, dynamic>>())
            if (c['id'] is String)
              (
                id: c['id'] as String,
                permissions: c['permissions'] is List
                    ? (c['permissions'] as List).whereType<String>().toSet()
                    : null,
              ),
        ];
      });

  /// Everyone with a record, and whether each has a login (2026-09-23).
  ///
  /// Three sources, because there is no one endpoint for "accounts":
  ///   - `GET /api/staff` and `GET /api/students` — both pages, both
  ///     carrying `userId` (null when no login is linked);
  ///   - `GET /api/guardians` — paged, each guardian with its linked
  ///     students. [PeopleDirectory.parentsPartial] is set if it fails.
  ///
  /// A login that was never linked to any record cannot appear here at all —
  /// nothing lists logins. Recorded in BACKEND_CONTRACT.md as a request.
  Future<PeopleDirectory> loadPeople() => _mapped(() async {
    final staffRes = await dio.getAllPages(ApiConfig.staffPath);
    final studentRes = await dio.getAllPages(ApiConfig.studentsPath);

    final staff = staffRes
        .map(
          (s) => PersonAccount(
            id: s['id'] as String,
            fullName: _name(s),
            group: PeopleGroup.staff,
            identifier: s['employeeCode'] as String?,
            detail: s['designation'] as String?,
            userId: s['userId'] as String?,
          ),
        )
        .toList();

    final studentRows = studentRes;
    final students = studentRows
        .map(
          (s) => PersonAccount(
            id: s['id'] as String,
            fullName: _name(s),
            group: PeopleGroup.students,
            identifier: s['admissionNumber'] as String?,
            detail: s['status'] as String?,
            userId: s['userId'] as String?,
          ),
        )
        .toList();

    // One paged call for the whole guardian directory (GET /api/guardians,
    // each row carrying its linked students) — replaces the old
    // per-student /api/guardians/student/{id} loop, which was N+1 and
    // burned through the per-user rate limit on a large institution.
    final parents = <PersonAccount>[];
    var partial = false;
    try {
      final rows = await dio.getAllPages(ApiConfig.guardiansPath);
      for (final g in rows) {
        final kids = (g['students'] as List? ?? const [])
            .cast<Map<String, dynamic>>();
        parents.add(
          PersonAccount(
            id: g['id'] as String,
            fullName: _name(g),
            group: PeopleGroup.parents,
            detail: kids.isEmpty
                ? null
                : kids
                      .map(
                        (k) =>
                            '${k['relationship'] ?? 'guardian'} of '
                            '${_name(k)}',
                      )
                      .join(', '),
            userId: g['userId'] as String?,
          ),
        );
      }
    } on DioException {
      partial = true;
    }

    return PeopleDirectory(
      staff: staff,
      students: students,
      parents: parents,
      parentsPartial: partial,
    );
  });

  static String _name(Map<String, dynamic> json) =>
      '${json['firstName'] ?? ''} ${json['lastName'] ?? ''}'.trim();

  Future<int> _countStaff() async {
    final res = await dio.get<Map<String, dynamic>>(
      ApiConfig.staffPath,
      queryParameters: const {'size': 1},
    );
    return (res.data?['totalElements'] as num?)?.toInt() ?? 0;
  }

  /// Student ids enrolled in a section. Carries no names — that is why the
  /// students list needs both calls joined.
  Future<List<String>> _enrolledStudentIds(String sectionId) async {
    final rows = await dio.getAllPages(
      '${ApiConfig.enrollmentsSectionPath}/$sectionId',
    );
    return rows
        .where((e) => e['status'] == 'enrolled')
        .map((e) => e['studentId'] as String)
        .toList();
  }

  Future<bool> _hasTimetable(String sectionId, String academicYearId) async {
    try {
      final res = await dio.get<List<dynamic>>(
        '${ApiConfig.timetableSectionPath}/$sectionId',
        queryParameters: {'academicYearId': academicYearId},
      );
      return (res.data ?? const []).isNotEmpty;
    } on DioException {
      // A section with no timetable is a normal state, and this call only
      // feeds a completeness rank — it must never fail the whole dashboard.
      return false;
    }
  }

  /// Builds the dashboard.
  ///
  /// ⚠️ **N+1 by necessity.** No endpoint returns per-section counts:
  /// `GET /api/sections` carries neither a student count nor any timetable
  /// information (verified live 2026-09-18). So this issues two extra calls
  /// per section — enrolments and timetable. That is fine for a pilot
  /// school and is NOT fine for a large one; there is no aggregate endpoint
  /// to replace it. Flagged rather than silently paginated.
  Future<AdminDashboard> loadDashboard() => _mapped(() async {
    final sectionsRes = await dio.getAllPages(ApiConfig.sectionsPath);
    final sectionRows = sectionsRes;

    final classes = await loadClasses();
    final classNameById = {for (final c in classes) c.id: c.name};

    final studentsRes = await dio.get<Map<String, dynamic>>(
      ApiConfig.studentsPath,
      queryParameters: const {'size': 1},
    );
    final studentCount =
        (studentsRes.data?['totalElements'] as num?)?.toInt() ?? 0;

    final staffCount = await _countStaff();

    final sections = <SectionCompleteness>[];
    for (final s in sectionRows) {
      final sectionId = s['id'] as String;
      final academicYearId = s['academicYearId'] as String?;
      final enrolled = await _enrolledStudentIds(sectionId);
      final hasTimetable = academicYearId == null
          ? false
          : await _hasTimetable(sectionId, academicYearId);

      sections.add(
        SectionCompleteness(
          sectionId: sectionId,
          sectionName: s['name'] as String? ?? '',
          className: classNameById[s['classId']] ?? '',
          studentCount: enrolled.length,
          hasTimetable: hasTimetable,
          hasClassTeacher: s['classTeacherId'] != null,
        ),
      );
    }

    return AdminDashboard(
      studentCount: studentCount,
      staffCount: staffCount,
      sections: sortByCompleteness(sections),
    );
  });

  /// The students list, with each student's section resolved.
  ///
  /// Enrolment is fetched per section rather than per student because the
  /// API only exposes it that way; the result is inverted into a
  /// studentId → section map.
  Future<List<AdminStudent>> loadStudentsWithPlacement() => _mapped(() async {
    final students = await loadStudents();

    final sectionsRes = await dio.getAllPages(ApiConfig.sectionsPath);
    final classes = await loadClasses();
    final classNameById = {for (final c in classes) c.id: c.name};

    final placementByStudent = <String, ({String id, String label})>{};
    for (final s in sectionsRes) {
      final sectionId = s['id'] as String;
      final label = '${classNameById[s['classId']] ?? ''} · ${s['name'] ?? ''}';
      for (final studentId in await _enrolledStudentIds(sectionId)) {
        placementByStudent[studentId] = (id: sectionId, label: label);
      }
    }

    return students.map((st) {
      final placement = placementByStudent[st.id];
      return st.withPlacement(
        sectionId: placement?.id,
        classLabel: placement?.label,
      );
    }).toList();
  });

  Future<AdminStudent> loadStudent(String id) => _mapped(() async {
    final res = await dio.get<Map<String, dynamic>>(
      '${ApiConfig.studentsPath}/$id',
    );
    return AdminStudent.fromJson(res.data ?? const {});
  });
}

class CampusRoleGrant {
  const CampusRoleGrant({
    required this.grantId,
    required this.campusId,
    required this.campusName,
    required this.role,
  });
  factory CampusRoleGrant.fromJson(Map json) => CampusRoleGrant(
    grantId: json['grantId'] as String,
    campusId: json['campusId'] as String,
    campusName: json['campusName'] as String? ?? '',
    role: json['role'] as String,
  );
  final String grantId;
  final String campusId;
  final String campusName;
  final String role;
}

/// Ordinary campus roles that may be delegated (the server enforces who may grant which).
const campusRoleLabels = <String, String>{
  'teacher': 'Teacher',
  'attendance_staff': 'Attendance staff',
  'finance_staff': 'Finance staff',
  'staff': 'Staff',
};
