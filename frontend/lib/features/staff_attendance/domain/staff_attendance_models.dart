import '../../../core/widgets/status_pill.dart';

/// Staff attendance (T16 Batch D).
///
/// 🔴 **The vocabulary is NOT the student one.** Probed exhaustively against
/// both endpoints:
///
/// | Students | Staff |
/// |---|---|
/// | present, absent, late, leave, **excused** | present, absent, late, leave, **half_day** |
///
/// Five each, four shared. `excused` is rejected for staff and `half_day`
/// for students. So this is its own enum: sharing one would compile
/// perfectly and send an invalid status at runtime (open item 37).
///
/// The marking ERGONOMICS are reused — that is the part that is genuinely
/// the same job.
enum StaffAttendanceStatus {
  present('present', AppStatus.present),
  absent('absent', AppStatus.absent),
  late('late', AppStatus.late),
  leave('leave', AppStatus.leave),
  halfDay('half_day', AppStatus.halfDay);

  const StaffAttendanceStatus(this.wire, this.pill);

  final String wire;
  final AppStatus pill;

  String get label => StatusPill.labelFor(pill);

  static StaffAttendanceStatus? parse(String? raw) {
    for (final s in StaffAttendanceStatus.values) {
      if (s.wire == raw) return s;
    }
    // `unmarked` lands here, which is correct: it is the ABSENCE of a
    // record, not a status that can be posted.
    return null;
  }
}

/// One staff member on the day's roster.
class StaffAttendanceRow {
  const StaffAttendanceRow({
    required this.staffId,
    required this.fullName,
    required this.employeeCode,
    required this.status,
  });

  factory StaffAttendanceRow.fromJson(Map<String, dynamic> json) =>
      StaffAttendanceRow(
        staffId: json['staff_id'] as String,
        fullName: '${json['first_name'] ?? ''} ${json['last_name'] ?? ''}'
            .trim(),
        employeeCode: json['employee_code'] as String? ?? '',
        status: StaffAttendanceStatus.parse(json['status'] as String?),
      );

  final String staffId;
  final String fullName;
  final String employeeCode;

  /// Null when nothing has been recorded — the backend reports `unmarked`.
  final StaffAttendanceStatus? status;

  bool get isMarked => status != null;
}

/// The whole marking surface for one day, in ONE call.
///
/// Better than the student equivalent, which needs `/enrollments/section` and
/// `/students` joined by hand — this endpoint already carries the names, the
/// codes and the counts.
class StaffAttendanceDay {
  const StaffAttendanceDay({
    required this.date,
    required this.rows,
    required this.totalStaff,
    required this.unmarked,
    required this.present,
    required this.absent,
  });

  factory StaffAttendanceDay.fromJson(Map<String, dynamic> json) =>
      StaffAttendanceDay(
        date: json['date'] as String? ?? '',
        totalStaff: json['totalStaff'] as int? ?? 0,
        unmarked: json['unmarked'] as int? ?? 0,
        present: json['present'] as int? ?? 0,
        absent: json['absent'] as int? ?? 0,
        rows: (json['records'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(StaffAttendanceRow.fromJson)
            .toList()
          ..sort((a, b) => a.fullName.compareTo(b.fullName)),
      );

  final String date;
  final List<StaffAttendanceRow> rows;

  /// All server-computed. The screen renders them rather than counting the
  /// list itself, so the header cannot disagree with the server.
  final int totalStaff;
  final int unmarked;
  final int present;
  final int absent;
}
