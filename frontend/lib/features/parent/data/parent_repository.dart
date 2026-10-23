import 'package:dio/dio.dart';

import '../../../core/network/api_config.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../domain/parent_models.dart';

/// Every method throws [LoadFailure], never a raw [DioException].
///
/// That translation is the whole point: the orphan case (`guardians/me`
/// 404 → `notLinked`) is only distinguishable AFTER mapping, and a screen
/// catching `DioException` would have no way to tell "no guardian record"
/// from "server down". Leaving it unmapped silently broke the D-17 path.
class ParentRepository {
  const ParentRepository(this.dio);

  final Dio dio;

  Future<T> _mapped<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (err) {
      throw mapDioError(err);
    }
  }

  /// The guardian and their children.
  ///
  /// A 404 here is the D-17 orphan case, not an error — the login is real
  /// but no guardian record was ever linked to it. `mapDioError` already
  /// classifies it as `notLinked` because the path is registered in
  /// [ApiConfig.personRecordPaths]; the caller renders
  /// `UnlinkedProfileState` and offers no retry, since the parent cannot
  /// fix it themselves.
  Future<GuardianProfile> loadGuardian() => _mapped(() async {
    final res = await dio.get<Map<String, dynamic>>(ApiConfig.guardiansMePath);
    return GuardianProfile.fromJson(res.data ?? const {});
  });

  /// Today's snapshot for one child — name, class and today's attendance in
  /// a single call, which is exactly the landing screen's question.
  ///
  /// Null ONLY when the server says the child has no class enrollment
  /// (404 with `details.code == NO_SCHOOL_ENROLLMENT`, e.g. an Academy-only
  /// learner). The server sends that code only after confirming this parent
  /// may read the child; every other 404 (not their child, other
  /// institution) stays a [LoadFailure], never an empty success.
  Future<ChildToday?> loadToday(String studentId) async {
    try {
      final res = await dio.get<Map<String, dynamic>>(
        '${ApiConfig.parentProgressPath}/$studentId',
      );
      return ChildToday.fromJson(res.data ?? const {});
    } on DioException catch (err) {
      if (isNoSchoolEnrollment(err)) return null;
      throw mapDioError(err);
    }
  }

  static bool isNoSchoolEnrollment(DioException err) {
    if (err.response?.statusCode != 404) return false;
    final data = err.response?.data;
    final details = data is Map ? data['details'] : null;
    return details is Map && details['code'] == 'NO_SCHOOL_ENROLLMENT';
  }

  /// Attendance across a date range. `from` is REQUIRED by the backend —
  /// there is no "everything" call, so the caller always picks a window.
  Future<List<AttendanceDay>> loadAttendance({
    required String studentId,
    required DateTime from,
    required DateTime to,
  }) => _mapped(() async {
    final res = await dio.get<Map<String, dynamic>>(
      '${ApiConfig.attendanceStudentPath}/$studentId',
      queryParameters: {'from': _iso(from), 'to': _iso(to)},
    );
    final rows = (res.data?['content'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(AttendanceDay.fromJson)
        .toList();
    // Most recent first: a parent checking in cares about the last few
    // days, not the start of the window.
    rows.sort((a, b) => b.date.compareTo(a.date));
    return rows;
  });

  static String _iso(DateTime d) => d.toIso8601String().substring(0, 10);
}
