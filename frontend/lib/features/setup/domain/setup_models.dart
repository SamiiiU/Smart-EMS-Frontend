import 'package:flutter/foundation.dart';

/// An academic year.
///
/// [current] is **read-only on this backend** — probed 2026-09-24: it is
/// neither settable (POST/PUT ignore it, no `set-current` route) nor derived
/// from the dates (a year covering today came back false while an expired
/// year stayed true). The screen therefore explains the situation instead of
/// offering a control that cannot work (D-19).
@immutable
class AcademicYear {
  const AcademicYear({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.current,
  });

  factory AcademicYear.fromJson(Map<String, dynamic> json) => AcademicYear(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        startDate: json['startDate'] as String? ?? '',
        endDate: json['endDate'] as String? ?? '',
        current: json['current'] as bool? ?? false,
      );

  final String id;
  final String name;

  /// `YYYY-MM-DD`, as the API returns them.
  final String startDate;
  final String endDate;
  final bool current;

  String get rangeLabel => '$startDate → $endDate';
}

/// A class (Grade 5, Class 9…).
@immutable
class SchoolClass {
  const SchoolClass({
    required this.id,
    required this.name,
    this.levelOrder,
  });

  factory SchoolClass.fromJson(Map<String, dynamic> json) => SchoolClass(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        levelOrder: (json['levelOrder'] as num?)?.toInt(),
      );

  final String id;
  final String name;

  /// Display order. Exposed in the UI because alphabetical sorting puts
  /// "Class 10" before "Class 2", which every school notices immediately.
  final int? levelOrder;
}

/// Classes in teaching order: [SchoolClass.levelOrder] first, then name for
/// the ones that have none — never alphabetical alone.
List<SchoolClass> sortClasses(List<SchoolClass> classes) {
  final sorted = [...classes];
  sorted.sort((a, b) {
    final ao = a.levelOrder;
    final bo = b.levelOrder;
    if (ao != null && bo != null && ao != bo) return ao.compareTo(bo);
    if (ao != null && bo == null) return -1;
    if (ao == null && bo != null) return 1;
    return a.name.compareTo(b.name);
  });
  return sorted;
}

@immutable
class Section {
  const Section({
    required this.id,
    required this.classId,
    required this.academicYearId,
    required this.name,
    this.classTeacherId,
    this.capacity,
  });

  factory Section.fromJson(Map<String, dynamic> json) => Section(
        id: json['id'] as String,
        classId: json['classId'] as String? ?? '',
        academicYearId: json['academicYearId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        classTeacherId: json['classTeacherId'] as String?,
        capacity: (json['capacity'] as num?)?.toInt(),
      );

  final String id;
  final String classId;
  final String academicYearId;
  final String name;
  final String? classTeacherId;
  final int? capacity;
}

@immutable
class Subject {
  const Subject({required this.id, required this.name, this.code});

  factory Subject.fromJson(Map<String, dynamic> json) => Subject(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        code: json['code'] as String?,
      );

  final String id;
  final String name;
  final String? code;
}

/// staff → section → subject → year.
///
/// The API returns **ids only**, so the screens join names from the staff and
/// subject lists they already hold.
@immutable
class TeachingAssignment {
  const TeachingAssignment({
    required this.id,
    required this.staffId,
    required this.sectionId,
    required this.subjectId,
    required this.academicYearId,
  });

  factory TeachingAssignment.fromJson(Map<String, dynamic> json) =>
      TeachingAssignment(
        id: json['id'] as String,
        staffId: json['staffId'] as String? ?? '',
        sectionId: json['sectionId'] as String? ?? '',
        subjectId: json['subjectId'] as String? ?? '',
        academicYearId: json['academicYearId'] as String? ?? '',
      );

  final String id;
  final String staffId;
  final String sectionId;
  final String subjectId;
  final String academicYearId;
}

/// A school-wide period. [isBreak] lives HERE, not on a slot (verified).
@immutable
class SchoolPeriod {
  const SchoolPeriod({
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.sortOrder,
    required this.isBreak,
  });

  factory SchoolPeriod.fromJson(Map<String, dynamic> json) => SchoolPeriod(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        startTime: json['startTime'] as String? ?? '',
        endTime: json['endTime'] as String? ?? '',
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        isBreak: json['isBreak'] as bool? ?? false,
      );

  final String id;
  final String name;
  final String startTime;
  final String endTime;
  final int sortOrder;
  final bool isBreak;

  String get timeLabel => '${_hhmm(startTime)}–${_hhmm(endTime)}';

  static String _hhmm(String t) => t.length >= 5 ? t.substring(0, 5) : t;
}

@immutable
class Room {
  const Room({required this.id, required this.name, this.capacity});

  factory Room.fromJson(Map<String, dynamic> json) => Room(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        capacity: (json['capacity'] as num?)?.toInt(),
      );

  final String id;
  final String name;
  final int? capacity;
}

/// One filled cell of a section's week.
@immutable
class TimetableSlot {
  const TimetableSlot({
    required this.id,
    required this.dayOfWeek,
    required this.periodId,
    required this.subjectId,
    required this.teacherStaffId,
    this.roomId,
  });

  factory TimetableSlot.fromJson(Map<String, dynamic> json) => TimetableSlot(
        // The section week endpoint calls it `slotId`; the write endpoints
        // call the same thing `id`. Both are accepted rather than picking
        // one and having the other silently produce empty cells.
        id: (json['slotId'] ?? json['id']) as String? ?? '',
        dayOfWeek: (json['dayOfWeek'] as num?)?.toInt() ?? 0,
        periodId: json['periodId'] as String? ?? '',
        subjectId: json['subjectId'] as String? ?? '',
        teacherStaffId: json['teacherStaffId'] as String? ?? '',
        roomId: json['roomId'] as String?,
      );

  final String id;

  /// 1 = Monday … 6 = Saturday (verified: Friday rows carried 5).
  final int dayOfWeek;
  final String periodId;
  final String subjectId;
  final String teacherStaffId;
  final String? roomId;
}

/// Why a slot write failed.
///
/// **Status alone cannot tell these apart** — this backend answers 409 for a
/// genuine clash AND for a missing required field. So the message is matched
/// against the two known clash wordings, and anything else is surfaced
/// verbatim: rendering "there is a clash" over a validation failure would
/// send the admin hunting for a conflict that does not exist.
enum SlotFailureKind { teacherClash, roomClash, other }

@immutable
class SlotFailure {
  const SlotFailure({required this.kind, required this.message});

  factory SlotFailure.fromMessage(String? message) {
    final m = message ?? '';
    if (m.contains('Teacher is already scheduled')) {
      return SlotFailure(kind: SlotFailureKind.teacherClash, message: m);
    }
    if (m.contains('Room is already booked')) {
      return SlotFailure(kind: SlotFailureKind.roomClash, message: m);
    }
    return SlotFailure(
      kind: SlotFailureKind.other,
      message: m.isEmpty ? 'This could not be saved.' : m,
    );
  }

  final SlotFailureKind kind;
  final String message;
}
