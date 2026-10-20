import 'package:dio/dio.dart';

import '../../../core/network/api_config.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/network/paged_get.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../setup/domain/setup_models.dart';
import 'academics_repository.dart';

/// What a teacher's Syllabus page may offer: only the sections and subjects
/// of their own active teaching assignments, in one academic year.
///
/// Built from existing, already-scoped reads (no new permission):
/// `GET /api/attendance/my-sections` (their sections), `GET /api/sections/{id}`
/// (class), `GET /api/teaching-assignments/section/{id}` (subjects, filtered to
/// this staff record), `GET /api/subjects` and `GET /api/academic-years/{id}`.
/// The server still enforces every read and write (curriculum assignment for
/// chapters, teaching assignment for coverage, Institution Admin for publish).
class TeacherSyllabusContext {
  const TeacherSyllabusContext({
    required this.year,
    required this.classes,
    required this.sections,
    required this.subjects,
  });

  final AcademicYear year;
  final List<SchoolClass> classes;
  final List<Section> sections;
  final List<Subject> subjects;

  bool get isEmpty => sections.isEmpty || subjects.isEmpty;
}

extension TeacherSyllabus on AcademicsRepository {
  /// Null when the teacher has no active assignment (shown as an empty state).
  Future<TeacherSyllabusContext?> teacherSyllabusContext(String staffId) async {
    Future<Object?> get(String path, [Map<String, dynamic>? query]) async {
      try {
        return (await dio.get<dynamic>(path, queryParameters: query)).data;
      } on DioException catch (err) {
        throw mapLoadFailure(err);
      }
    }

    final mine = (await get('/api/attendance/my-sections') as List? ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .toList();
    if (mine.isEmpty) return null;
    // One year at a time: the year of the teacher's first assignment.
    final yearId = mine.first['academicYearId'] as String;
    final sections = <Section>[];
    final subjectIds = <String>{};
    for (final row in mine.where((r) => r['academicYearId'] == yearId)) {
      final sectionId = row['sectionId'] as String;
      final page =
          await get('/api/teaching-assignments/section/$sectionId') as Map?;
      final own = [
        for (final a
            in (page?['content'] as List? ?? const [])
                .whereType<Map<String, dynamic>>())
          TeachingAssignment.fromJson(a),
      ].where((a) => a.staffId == staffId && a.status == 'active');
      if (own.isEmpty) continue;
      subjectIds.addAll(own.map((a) => a.subjectId));
      sections.add(
        Section.fromJson(
          ((await get('/api/sections/$sectionId')) as Map)
              .cast<String, dynamic>(),
        ),
      );
    }
    if (sections.isEmpty) return null;
    final classes = <SchoolClass>[
      for (final classId in sections.map((s) => s.classId).toSet())
        SchoolClass(
          id: classId,
          name:
              mine.firstWhere(
                    (r) => sections.any(
                      (s) => s.classId == classId && s.id == r['sectionId'],
                    ),
                    orElse: () => const {'className': 'Class'},
                  )['className']
                  as String? ??
              'Class',
        ),
    ];
    final List<Map<String, dynamic>> subjectRows;
    try {
      subjectRows = await dio.getAllPages(ApiConfig.subjectsPath);
    } on DioException catch (err) {
      throw mapLoadFailure(err);
    }
    final subjects = [
      for (final s in subjectRows)
        if (subjectIds.contains(s['id'])) Subject.fromJson(s),
    ];
    final year = AcademicYear.fromJson(
      ((await get('/api/academic-years/$yearId')) as Map)
          .cast<String, dynamic>(),
    );
    return TeacherSyllabusContext(
      year: year,
      classes: classes,
      sections: sections,
      subjects: subjects,
    );
  }
}

/// The repository's own error mapping, for reads made here.
LoadFailure mapLoadFailure(DioException err) =>
    mapDioError(AcademicsRepository.decodeErrorBody(err));
