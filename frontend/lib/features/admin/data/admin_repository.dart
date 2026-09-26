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

  Future<T> _mapped<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (err) {
      throw mapDioError(err);
    }
  }

  static List<Map<String, dynamic>> _content(Map<String, dynamic>? body) =>
      (body?['content'] as List? ?? const []).cast<Map<String, dynamic>>();

  /// Loads every student, then joins enrolment in to get each one's section.
  ///
  /// B-02: there is no server-side search, so the whole set is loaded and
  /// filtered in the client (D-20). `size=500` is a deliberate ceiling, not
  /// a page size — see the note on [loadStudents]'s caller.
  Future<List<AdminStudent>> loadStudents({String? sectionId}) =>
      _mapped(() async {
        final res = await dio.get<Map<String, dynamic>>(
          ApiConfig.studentsPath,
          queryParameters: {
            'size': 500,
            // B-03: `sectionId` and `classId` ARE honoured by this build
            // (verified live 2026-09-18 — a bogus id returns 0 while an
            // unknown param is ignored, which is what makes that sound).
            // Sent server-side because a real filter beats a client one.
            'sectionId': ?sectionId,
          },
        );
        return _content(res.data).map(AdminStudent.fromJson).toList();
      });

  Future<List<AdminClass>> loadClasses() => _mapped(() async {
        final res = await dio.get<Map<String, dynamic>>(
          ApiConfig.classesPath,
          queryParameters: const {'size': 200},
        );
        return _content(res.data).map(AdminClass.fromJson).toList();
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
  Future<List<String>> loadCampusIds() => _mapped(() async {
        final res = await dio.get<dynamic>(
          ApiConfig.campusesPath,
          queryParameters: const {'size': 50},
        );
        final body = res.data;
        final rows = body is List
            ? body
            : (body is Map ? body['content'] as List? : null) ?? const [];
        return rows
            .whereType<Map<dynamic, dynamic>>()
            .map((c) => c['id'] as String?)
            .whereType<String>()
            .toList();
      });

  /// Everyone with a record, and whether each has a login (2026-09-23).
  ///
  /// Three sources, because there is no one endpoint for "accounts":
  ///   - `GET /api/staff` and `GET /api/students` — both pages, both
  ///     carrying `userId` (null when no login is linked);
  ///   - guardians have **no list endpoint** (`GET /api/guardians` answers
  ///     405, verified live), so parents are collected per student via
  ///     `/api/guardians/student/{id}`. That is N+1 by necessity, not by
  ///     choice, and it is why [PeopleDirectory.parentsPartial] exists.
  ///
  /// A login that was never linked to any record cannot appear here at all —
  /// nothing lists logins. Recorded in BACKEND_CONTRACT.md as a request.
  Future<PeopleDirectory> loadPeople() => _mapped(() async {
        final staffRes = await dio.get<Map<String, dynamic>>(
          ApiConfig.staffPath,
          queryParameters: const {'size': 200},
        );
        final studentRes = await dio.get<Map<String, dynamic>>(
          ApiConfig.studentsPath,
          queryParameters: const {'size': 200},
        );

        final staff = _content(staffRes.data)
            .map((s) => PersonAccount(
                  id: s['id'] as String,
                  fullName: _name(s),
                  group: PeopleGroup.staff,
                  identifier: s['employeeCode'] as String?,
                  detail: s['designation'] as String?,
                  userId: s['userId'] as String?,
                ))
            .toList();

        final studentRows = _content(studentRes.data);
        final students = studentRows
            .map((s) => PersonAccount(
                  id: s['id'] as String,
                  fullName: _name(s),
                  group: PeopleGroup.students,
                  identifier: s['admissionNumber'] as String?,
                  detail: s['status'] as String?,
                  userId: s['userId'] as String?,
                ))
            .toList();

        final parents = <String, PersonAccount>{};
        var partial = false;
        for (final student in studentRows) {
          try {
            final res = await dio.get<List<dynamic>>(
              ApiConfig.guardiansOfStudentPath(student['id'] as String),
            );
            for (final link in (res.data ?? const []).cast<Map<String, dynamic>>()) {
              final g = link['guardian'] as Map<String, dynamic>?;
              if (g == null) continue;
              // Keyed by id: one guardian can be linked to several students
              // and must appear once, not once per child.
              parents[g['id'] as String] = PersonAccount(
                id: g['id'] as String,
                fullName: _name(g),
                group: PeopleGroup.parents,
                detail: '${link['relationship'] ?? 'guardian'} of '
                    '${_name(student)}',
                userId: g['userId'] as String?,
              );
            }
          } on DioException {
            partial = true;
          }
        }

        return PeopleDirectory(
          staff: staff,
          students: students,
          parents: parents.values.toList(),
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
    final res = await dio.get<Map<String, dynamic>>(
      '${ApiConfig.enrollmentsSectionPath}/$sectionId',
      queryParameters: const {'size': 500},
    );
    return _content(res.data)
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
        final sectionsRes = await dio.get<Map<String, dynamic>>(
          ApiConfig.sectionsPath,
          queryParameters: const {'size': 200},
        );
        final sectionRows = _content(sectionsRes.data);

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

          sections.add(SectionCompleteness(
            sectionId: sectionId,
            sectionName: s['name'] as String? ?? '',
            className: classNameById[s['classId']] ?? '',
            studentCount: enrolled.length,
            hasTimetable: hasTimetable,
            hasClassTeacher: s['classTeacherId'] != null,
          ));
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

        final sectionsRes = await dio.get<Map<String, dynamic>>(
          ApiConfig.sectionsPath,
          queryParameters: const {'size': 200},
        );
        final classes = await loadClasses();
        final classNameById = {for (final c in classes) c.id: c.name};

        final placementByStudent = <String, ({String id, String label})>{};
        for (final s in _content(sectionsRes.data)) {
          final sectionId = s['id'] as String;
          final label =
              '${classNameById[s['classId']] ?? ''} · ${s['name'] ?? ''}';
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
        final res =
            await dio.get<Map<String, dynamic>>('${ApiConfig.studentsPath}/$id');
        return AdminStudent.fromJson(res.data ?? const {});
      });
}
