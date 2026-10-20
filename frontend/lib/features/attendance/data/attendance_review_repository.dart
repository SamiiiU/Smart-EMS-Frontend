import 'package:dio/dio.dart';

import '../../../core/network/api_error_mapper.dart';
import '../../../core/widgets/states/screen_state.dart';

/// One offline attendance operation the server held instead of applying
/// (ADR-010): it differed from the server record, or arrived after the
/// official closing time + 72 hours.
class AttendanceReview {
  const AttendanceReview({
    required this.id,
    required this.studentName,
    required this.attendanceDate,
    required this.submittedStatus,
    required this.currentServerStatus,
    required this.reason,
    required this.receivedAt,
  });

  factory AttendanceReview.fromJson(Map<String, dynamic> json) =>
      AttendanceReview(
        id: json['id'] as String,
        studentName: '${json['firstName'] ?? ''} ${json['lastName'] ?? ''}'
            .trim(),
        attendanceDate: json['attendanceDate']?.toString() ?? '',
        submittedStatus: json['submittedStatus'] as String? ?? '',
        currentServerStatus: json['currentServerStatus'] as String?,
        reason: json['reason'] as String? ?? '',
        receivedAt: json['receivedAt']?.toString() ?? '',
      );

  final String id;
  final String studentName;
  final String attendanceDate;
  final String submittedStatus;
  final String? currentServerStatus;

  /// `CONFLICT` or `LATE_SYNC`.
  final String reason;
  final String receivedAt;
}

/// `/api/attendance/reviews`. The server limits the list and every decision
/// to campuses where the caller holds attendance.manage.
class AttendanceReviewRepository {
  const AttendanceReviewRepository(this.dio);

  final Dio dio;

  static const _path = '/api/attendance/reviews';

  Future<({List<AttendanceReview>? reviews, LoadFailure? failure})> pending({
    int page = 0,
  }) async {
    try {
      final res = await dio.get<Map<String, dynamic>>(
        _path,
        queryParameters: {'state': 'pending', 'page': page, 'size': 50},
      );
      final content = (res.data?['content'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(AttendanceReview.fromJson)
          .toList();
      return (reviews: content, failure: null);
    } on DioException catch (err) {
      return (reviews: null, failure: mapDioError(err));
    }
  }

  /// [accept] applies the teacher's original mark; reject keeps the server
  /// record. A reason is mandatory and recorded with the reviewer.
  Future<LoadFailure?> decide(
    String id, {
    required bool accept,
    required String reason,
  }) async {
    try {
      await dio.post<dynamic>(
        '$_path/$id/${accept ? 'accept' : 'reject'}',
        data: {'reason': reason.trim()},
      );
      return null;
    } on DioException catch (err) {
      return mapDioError(err);
    }
  }
}
