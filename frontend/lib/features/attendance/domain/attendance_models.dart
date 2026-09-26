import 'package:flutter/foundation.dart';

/// The five statuses the backend accepts.
///
/// Wire values are LOWERCASE — confirmed live 2026-08-05: posting anything
/// else returns `status must be one of [present, absent, late, leave,
/// excused]`. These are exactly the five attendance variants `StatusPill`
/// has shipped since T2, so no new visual vocabulary is needed.
enum AttendanceStatus {
  present('present'),
  absent('absent'),
  late('late'),
  leave('leave'),
  excused('excused');

  const AttendanceStatus(this.wire);

  final String wire;

  static AttendanceStatus fromWire(String value) {
    return AttendanceStatus.values.firstWhere(
      (s) => s.wire == value.toLowerCase(),
      // Not a silent fallback: an unknown status means the backend grew a
      // sixth one and this app would otherwise mislabel a student's record.
      orElse: () => throw ArgumentError('Unknown attendance status: $value'),
    );
  }

  String get label => switch (this) {
        AttendanceStatus.present => 'Present',
        AttendanceStatus.absent => 'Absent',
        AttendanceStatus.late => 'Late',
        AttendanceStatus.leave => 'Leave',
        AttendanceStatus.excused => 'Excused',
      };
}

/// One student on the roster being marked.
@immutable
class RosterStudent {
  const RosterStudent({
    required this.studentId,
    required this.fullName,
    this.rollNumber,
  });

  final String studentId;
  final String fullName;
  final String? rollNumber;
}

/// A single attendance mark, queued or sent.
///
/// [clientUuid] is the backend's own idempotency key (required on every
/// mark, confirmed live). Generating it on the device — before the request
/// is ever attempted — is what makes an offline queue safe to replay: the
/// same mark retried ten times is still one record, and the server reports
/// `idempotentReplay: true` rather than duplicating.
@immutable
class AttendanceMark {
  const AttendanceMark({
    required this.clientUuid,
    required this.sectionId,
    required this.studentId,
    required this.attendanceDate,
    required this.status,
    this.isCorrection = false,
  });

  final String clientUuid;
  final String sectionId;
  final String studentId;

  /// ISO `yyyy-MM-dd`.
  final String attendanceDate;

  final AttendanceStatus status;

  /// Corrections replay through the single `/api/attendance` endpoint;
  /// initial submissions replay through `/api/attendance/bulk` (D-T8-02).
  final bool isCorrection;
}

/// A conflict that was resolved in the server's favour.
///
/// Kept as a record rather than a transient banner because the rule is
/// "server wins, but never silently" — a teacher whose marking was
/// overridden is entitled to know which student it was and what it changed
/// to, after the fact, not just in a toast they may have missed.
@immutable
class AttendanceConflict {
  const AttendanceConflict({
    required this.studentId,
    required this.attendanceDate,
    required this.localStatus,
    required this.serverStatus,
  });

  final String studentId;
  final String attendanceDate;
  final AttendanceStatus localStatus;
  final AttendanceStatus serverStatus;
}
