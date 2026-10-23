import 'package:flutter/foundation.dart';

import '../../attendance/domain/attendance_models.dart';

/// One child linked to the signed-in guardian.
///
/// Carries `sectionId` and `academicYearId` directly (confirmed live), so
/// reaching a child's attendance needs no extra lookup.
@immutable
class GuardianChild {
  const GuardianChild({
    required this.studentId,
    required this.fullName,
    required this.sectionId,
    this.className,
    this.sectionName,
    this.admissionNumber,
    this.academicYearId,
    this.relationship,
  });

  factory GuardianChild.fromJson(Map<String, dynamic> json) {
    final first = json['firstName'] as String? ?? '';
    final last = json['lastName'] as String? ?? '';
    return GuardianChild(
      studentId: json['studentId'] as String,
      fullName: '$first $last'.trim(),
      sectionId: json['sectionId'] as String?,
      className: json['className'] as String?,
      // From guardians/me this is already `{class}-{section}`, e.g.
      // "Class 9-C". parent-progress returns the bare section ("C") for the
      // same field — this is the complete one, so it is preferred.
      sectionName: json['sectionName'] as String?,
      admissionNumber: json['admissionNumber'] as String?,
      academicYearId: json['academicYearId'] as String?,
      relationship: json['relationship'] as String?,
    );
  }

  final String studentId;
  final String fullName;
  final String? sectionId;
  final String? className;
  final String? sectionName;
  final String? admissionNumber;
  final String? academicYearId;
  final String? relationship;

  /// Best available label for the child's class.
  ///
  /// M1 consistency: guardians/me joins it as "{class}-{section}" ("Grade 6 A-6A-1")
  /// while every other screen shows "Grade 6 A · 6A-1"; the join is normalised here.
  /// Any other shape is shown as received.
  String? get classLabel {
    final section = sectionName;
    final klass = className;
    if (section != null &&
        klass != null &&
        section.startsWith('$klass-') &&
        section.length > klass.length + 1) {
      return '$klass · ${section.substring(klass.length + 1)}';
    }
    return section ?? klass;
  }
}

/// The signed-in guardian and their children.
@immutable
class GuardianProfile {
  const GuardianProfile({
    required this.guardianId,
    required this.fullName,
    required this.children,
  });

  factory GuardianProfile.fromJson(Map<String, dynamic> json) {
    final first = json['firstName'] as String? ?? '';
    final last = json['lastName'] as String? ?? '';
    return GuardianProfile(
      guardianId: json['guardianId'] as String? ?? '',
      fullName: '$first $last'.trim(),
      children: (json['students'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(GuardianChild.fromJson)
          .toList(growable: false),
    );
  }

  final String guardianId;
  final String fullName;

  /// Always a list. The API returns one child today because its write side
  /// cannot link a guardian to more (see BACKEND_CONTRACT.md), but the
  /// contract is an array and the UI handles 0, 1 and N.
  final List<GuardianChild> children;

  bool get hasMultipleChildren => children.length > 1;
}

/// A child's day, for the landing screen.
///
/// [status] is NULL when the register has not been taken yet. That is
/// "not marked", NOT absent — conflating the two would tell a parent their
/// child missed school because a teacher is running late.
@immutable
class ChildToday {
  const ChildToday({
    required this.studentId,
    required this.date,
    this.studentName,
    this.className,
    this.sectionName,
    this.status,
    this.diaryEntries = const [],
    this.remarks = const [],
    this.attendanceStats,
    this.latestResult,
  });

  factory ChildToday.fromJson(Map<String, dynamic> json) {
    final raw = json['attendanceStatus'] as String?;
    return ChildToday(
      studentId: json['studentId'] as String? ?? '',
      date: json['date'] as String? ?? '',
      studentName: json['studentName'] as String?,
      className: json['className'] as String?,
      sectionName: json['sectionName'] as String?,
      status: raw == null ? null : AttendanceStatus.fromWire(raw),
      diaryEntries: (json['diaryEntries'] as List? ?? const [])
          .map(
            (e) => e is Map
                ? (e['content'] ?? e['body'] ?? '').toString()
                : e.toString(),
          )
          .where((e) => e.isNotEmpty)
          .toList(),
      remarks: (json['remarks'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(ChildRemark.fromJson)
          .toList(),
      attendanceStats: json['attendanceStats'] == null
          ? null
          : ChildAttendanceStats.fromJson(
              (json['attendanceStats'] as Map).cast<String, dynamic>(),
            ),
      latestResult: json['latestResult'] == null
          ? null
          : ChildLatestResult.fromJson(
              (json['latestResult'] as Map).cast<String, dynamic>(),
            ),
    );
  }

  final String studentId;
  final String date;
  final String? studentName;
  final String? className;
  final String? sectionName;
  final AttendanceStatus? status;

  bool get isMarked => status != null;

  /// What T9 left on the table.
  ///
  /// `/api/parent-progress/student/{id}` has always returned far more than
  /// the attendance status T9 read: the day's diary, the parent-visible
  /// remarks, an attendance summary and the latest exam result. T9 could not
  /// use them because the screens that give them meaning (diary, remarks,
  /// exams) did not exist yet. They do now (T11/T15), so the parent finally
  /// sees the whole picture on one screen.
  ///
  /// `remarks` is **server-filtered** to `isParentVisible: true` — verified
  /// live: a remark flagged false does not appear here. Nothing is filtered
  /// on the device.
  final List<String> diaryEntries;
  final List<ChildRemark> remarks;
  final ChildAttendanceStats? attendanceStats;
  final ChildLatestResult? latestResult;
}

/// A remark the parent is allowed to see.
class ChildRemark {
  const ChildRemark({
    required this.body,
    required this.remarkType,
    required this.remarkDate,
    required this.authorName,
  });

  factory ChildRemark.fromJson(Map<String, dynamic> json) => ChildRemark(
    body: json['body'] as String? ?? '',
    remarkType: json['remarkType'] as String? ?? '',
    remarkDate: json['remarkDate'] as String? ?? '',
    authorName: json['authorName'] as String? ?? '',
  );

  final String body;
  final String remarkType;
  final String remarkDate;
  final String authorName;
}

/// The attendance summary, all server-computed.
class ChildAttendanceStats {
  const ChildAttendanceStats({
    required this.totalDays,
    required this.present,
    required this.absent,
    required this.percentage,
    required this.belowThreshold,
  });

  factory ChildAttendanceStats.fromJson(Map<String, dynamic> json) =>
      ChildAttendanceStats(
        totalDays: json['totalDays'] as int? ?? 0,
        present: json['present'] as int? ?? 0,
        absent: json['absent'] as int? ?? 0,
        // An int on this endpoint, unlike the two-decimal numbers the fee
        // and exam modules send.
        percentage: (json['percentage'] as num?)?.toInt() ?? 0,
        belowThreshold: json['belowThreshold'] as bool? ?? false,
      );

  final int totalDays;
  final int present;
  final int absent;
  final int percentage;

  /// The server's own judgement, not a threshold re-derived here.
  final bool belowThreshold;

  bool get hasData => totalDays > 0;
}

/// The most recent published exam result.
class ChildLatestResult {
  const ChildLatestResult({
    required this.examName,
    required this.grade,
    required this.percentage,
    this.position,
  });

  factory ChildLatestResult.fromJson(Map<String, dynamic> json) =>
      ChildLatestResult(
        examName: json['examName'] as String? ?? '',
        grade: json['grade'] as String? ?? '',
        // Kept as TEXT, never a double: this is the same two-decimal number
        // the exam module sends, and a result reading 89.99999 on a parent's
        // phone is the defect `Marks` exists to prevent.
        percentage: json['percentage']?.toString() ?? '',
        position: json['position'] as int?,
      );

  final String examName;
  final String grade;
  final String percentage;
  final int? position;
}

/// One attendance record in a range.
@immutable
class AttendanceDay {
  const AttendanceDay({required this.date, required this.status});

  /// NOTE the snake_case keys: this endpoint returns raw DB columns, unlike
  /// the camelCase typed DTOs. Verified live 2026-08-11.
  factory AttendanceDay.fromJson(Map<String, dynamic> json) => AttendanceDay(
    date: json['attendance_date'] as String? ?? '',
    status: AttendanceStatus.fromWire(json['status'] as String),
  );

  final String date;
  final AttendanceStatus status;
}

/// One lesson in a section's week, as `GET /api/timetable/section/{id}`
/// returns it (names included, so no further lookups are needed).
class WeekLesson {
  const WeekLesson({
    required this.dayOfWeek,
    required this.periodName,
    required this.subjectName,
    this.startTime,
    this.endTime,
    this.sortOrder = 0,
    this.teacherName,
    this.roomName,
  });

  factory WeekLesson.fromJson(Map<String, dynamic> json) => WeekLesson(
    dayOfWeek: (json['dayOfWeek'] as num?)?.toInt() ?? 0,
    periodName: json['periodName'] as String? ?? '',
    subjectName: json['subjectName'] as String? ?? 'Lesson',
    startTime: _hhmm(json['startTime']),
    endTime: _hhmm(json['endTime']),
    sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    teacherName: (json['teacherName'] as String?)?.trim(),
    roomName: json['roomName'] as String?,
  );

  /// 1 = Monday … 6 = Saturday (the builder's numbering).
  final int dayOfWeek;
  final String periodName;
  final String subjectName;
  final String? startTime;
  final String? endTime;
  final int sortOrder;
  final String? teacherName;
  final String? roomName;

  /// "08:00:00" → "08:00"; anything else is shown as sent.
  static String? _hhmm(Object? v) {
    final s = v?.toString();
    if (s == null || s.isEmpty) return null;
    return s.length >= 5 ? s.substring(0, 5) : s;
  }
}

/// D-19 (proposed contract): the student's own current class placement.
class OwnEnrollment {
  const OwnEnrollment({
    required this.sectionId,
    required this.academicYearId,
    this.className,
    this.sectionName,
    this.academicYearName,
  });

  factory OwnEnrollment.fromJson(Map<String, dynamic> json) => OwnEnrollment(
    sectionId: json['sectionId'] as String,
    academicYearId: json['academicYearId'] as String,
    className: json['className'] as String?,
    sectionName: json['sectionName'] as String?,
    academicYearName: json['academicYearName'] as String?,
  );

  final String sectionId;
  final String academicYearId;
  final String? className;
  final String? sectionName;
  final String? academicYearName;

  String get label => [
    className,
    sectionName,
  ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
}
