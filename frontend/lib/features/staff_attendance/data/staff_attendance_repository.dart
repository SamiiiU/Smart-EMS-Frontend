import 'dart:math';

import 'package:dio/dio.dart';

import '../../../core/network/api_error_mapper.dart';
import '../domain/staff_attendance_models.dart';

/// Staff attendance (T16 Batch D).
class StaffAttendanceRepository {
  const StaffAttendanceRepository(this.dio);

  final Dio dio;

  Future<T> _mapped<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (err) {
      throw mapDioError(err);
    }
  }

  /// The whole day in one call — names, codes, statuses and counts.
  Future<StaffAttendanceDay> loadDay(String date) => _mapped(() async {
        final res = await dio.get<Map<String, dynamic>>(
          '/api/staff-attendance/daily',
          queryParameters: {'date': date},
        );
        return StaffAttendanceDay.fromJson(res.data ?? const {});
      });

  /// Marks one staff member.
  ///
  /// `clientUuid` is REQUIRED, the same device-generated idempotency key
  /// student attendance uses: generated before the request is attempted, so
  /// a retry is still one record rather than two.
  Future<String?> mark({
    required String staffId,
    required String date,
    required StaffAttendanceStatus status,
    String? note,
  }) async {
    try {
      await dio.post<dynamic>(
        '/api/staff-attendance',
        data: {
          'staffId': staffId,
          'attendanceDate': date,
          'status': status.wire,
          'clientUuid': _uuidV4(),
          'note': ?note,
        },
      );
      return null;
    } on DioException catch (err) {
      return mapDioError(err).message ?? 'This could not be saved.';
    }
  }

  static String _uuidV4() {
    final random = Random();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int from, int to) => bytes
        .sublist(from, to)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}
