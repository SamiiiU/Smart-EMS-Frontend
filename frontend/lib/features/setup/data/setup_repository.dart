import 'package:dio/dio.dart';

import '../../../core/network/api_config.dart';
import '../../../core/network/api_error_mapper.dart';
import '../domain/setup_models.dart';

/// Reads and writes for academic setup (T13 Batch A).
///
/// Everything here throws [LoadFailure], never a raw [DioException], so the
/// screens can tell a dependency failure ("no academic year yet") from a
/// genuine error. The one exception is [createSlot], which returns a typed
/// [SlotFailure] instead, because a clash is an expected outcome of filling
/// a timetable rather than an error state.
class SetupRepository {
  const SetupRepository(this.dio);

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

  static List<Map<String, dynamic>> _array(List<dynamic>? body) =>
      (body ?? const []).cast<Map<String, dynamic>>();

  // --- Academic years -------------------------------------------------------

  Future<List<AcademicYear>> loadYears() => _mapped(() async {
        final res = await dio.get<Map<String, dynamic>>(
          ApiConfig.academicYearsPath,
          queryParameters: const {'size': 100},
        );
        return _content(res.data).map(AcademicYear.fromJson).toList();
      });

  /// `current` is deliberately NOT sent: the backend ignores it either way,
  /// and sending it would suggest this call can set it.
  Future<AcademicYear> createYear({
    required String campusId,
    required String name,
    required String startDate,
    required String endDate,
  }) =>
      _mapped(() async {
        final res = await dio.post<Map<String, dynamic>>(
          ApiConfig.academicYearsPath,
          data: {
            'campusId': campusId,
            'name': name,
            'startDate': startDate,
            'endDate': endDate,
          },
        );
        return AcademicYear.fromJson(res.data!);
      });

  // --- Classes --------------------------------------------------------------

  Future<List<SchoolClass>> loadClasses() => _mapped(() async {
        final res = await dio.get<Map<String, dynamic>>(
          ApiConfig.classesPath,
          queryParameters: const {'size': 200},
        );
        return sortClasses(
          _content(res.data).map(SchoolClass.fromJson).toList(),
        );
      });

  Future<SchoolClass> createClass({
    required String campusId,
    required String name,
    int? levelOrder,
  }) =>
      _mapped(() async {
        final res = await dio.post<Map<String, dynamic>>(
          ApiConfig.classesPath,
          data: {
            'campusId': campusId,
            'name': name,
            'levelOrder': ?levelOrder,
          },
        );
        return SchoolClass.fromJson(res.data!);
      });

  // --- Sections -------------------------------------------------------------

  /// Every section, for every class.
  ///
  /// `?classId=` is IGNORED by this backend (verified with a bogus-id
  /// control), so grouping happens in the client. Sending it anyway would
  /// imply a filter that does not exist.
  Future<List<Section>> loadSections() => _mapped(() async {
        final res = await dio.get<Map<String, dynamic>>(
          ApiConfig.sectionsPath,
          queryParameters: const {'size': 500},
        );
        return _content(res.data).map(Section.fromJson).toList();
      });

  Future<Section> createSection({
    required String classId,
    required String academicYearId,
    required String name,
    int? capacity,
    String? classTeacherId,
  }) =>
      _mapped(() async {
        final res = await dio.post<Map<String, dynamic>>(
          ApiConfig.sectionsPath,
          data: {
            'classId': classId,
            'academicYearId': academicYearId,
            'name': name,
            'capacity': ?capacity,
            'classTeacherId': ?classTeacherId,
          },
        );
        return Section.fromJson(res.data!);
      });

  // --- Subjects -------------------------------------------------------------

  Future<List<Subject>> loadSubjects() => _mapped(() async {
        final res = await dio.get<Map<String, dynamic>>(
          ApiConfig.subjectsPath,
          queryParameters: const {'size': 200},
        );
        return _content(res.data).map(Subject.fromJson).toList();
      });

  Future<Subject> createSubject({required String name, String? code}) =>
      _mapped(() async {
        final res = await dio.post<Map<String, dynamic>>(
          ApiConfig.subjectsPath,
          data: {'name': name, 'code': ?code},
        );
        return Subject.fromJson(res.data!);
      });

  // --- Teaching assignments -------------------------------------------------

  Future<List<TeachingAssignment>> loadAssignments(String sectionId) =>
      _mapped(() async {
        final res = await dio.get<Map<String, dynamic>>(
          ApiConfig.teachingAssignmentsSectionPath(sectionId),
          queryParameters: const {'size': 200},
        );
        return _content(res.data).map(TeachingAssignment.fromJson).toList();
      });

  /// Create-only by necessity — there is no update or delete route.
  Future<TeachingAssignment> createAssignment({
    required String staffId,
    required String sectionId,
    required String subjectId,
    required String academicYearId,
  }) =>
      _mapped(() async {
        final res = await dio.post<Map<String, dynamic>>(
          ApiConfig.teachingAssignmentsPath,
          data: {
            'staffId': staffId,
            'sectionId': sectionId,
            'subjectId': subjectId,
            'academicYearId': academicYearId,
          },
        );
        return TeachingAssignment.fromJson(res.data!);
      });

  // --- Timetable ------------------------------------------------------------

  Future<List<SchoolPeriod>> loadPeriods(String campusId) => _mapped(() async {
        final res = await dio.get<List<dynamic>>(
          ApiConfig.timetablePeriodsPath,
          queryParameters: {'campusId': campusId},
        );
        return _array(res.data).map(SchoolPeriod.fromJson).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      });

  Future<SchoolPeriod> createPeriod({
    required String campusId,
    required String name,
    required String startTime,
    required String endTime,
    required int sortOrder,
    required bool isBreak,
  }) =>
      _mapped(() async {
        final res = await dio.post<Map<String, dynamic>>(
          ApiConfig.timetablePeriodsPath,
          data: {
            'campusId': campusId,
            'name': name,
            'startTime': startTime,
            'endTime': endTime,
            'sortOrder': sortOrder,
            'isBreak': isBreak,
          },
        );
        return SchoolPeriod.fromJson(res.data!);
      });

  Future<List<Room>> loadRooms(String campusId) => _mapped(() async {
        final res = await dio.get<List<dynamic>>(
          ApiConfig.timetableRoomsPath,
          queryParameters: {'campusId': campusId},
        );
        return _array(res.data).map(Room.fromJson).toList();
      });

  /// A section's whole week. `academicYearId` is REQUIRED by the endpoint.
  Future<List<TimetableSlot>> loadWeek({
    required String sectionId,
    required String academicYearId,
  }) =>
      _mapped(() async {
        final res = await dio.get<List<dynamic>>(
          '${ApiConfig.timetableSectionPath}/$sectionId',
          queryParameters: {'academicYearId': academicYearId},
        );
        return _array(res.data).map(TimetableSlot.fromJson).toList();
      });

  /// Fills one cell.
  ///
  /// Returns the slot on success, or a [SlotFailure] — never throws for a
  /// 409, because a clash is an ordinary outcome of building a timetable.
  /// The KIND is decided by the message, not the status: this backend
  /// answers 409 for bad input too, so trusting the status would render a
  /// clash error over a validation failure.
  Future<(TimetableSlot?, SlotFailure?)> createSlot({
    required String sectionId,
    required String academicYearId,
    required String periodId,
    required int dayOfWeek,
    required String subjectId,
    required String teacherStaffId,
    String? roomId,
  }) async {
    try {
      final res = await dio.post<Map<String, dynamic>>(
        ApiConfig.timetableSlotsPath,
        data: {
          'sectionId': sectionId,
          'academicYearId': academicYearId,
          'periodId': periodId,
          'dayOfWeek': dayOfWeek,
          'subjectId': subjectId,
          'teacherStaffId': teacherStaffId,
          'roomId': ?roomId,
        },
      );
      return (TimetableSlot.fromJson(res.data!), null);
    } on DioException catch (err) {
      final body = err.response?.data;
      final message = body is Map ? body['message'] as String? : null;
      return (null, SlotFailure.fromMessage(message ?? mapDioError(err).message));
    }
  }

  Future<void> deleteSlot(String slotId) => _mapped(() async {
        await dio.delete<void>(ApiConfig.timetableSlotPath(slotId));
      });
}
