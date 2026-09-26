import 'package:flutter/foundation.dart';

/// A student as the admin list shows them.
///
/// ⚠️ `GET /api/students` carries **no class or section** (verified live
/// 2026-09-18). [sectionId] and [classLabel] are filled in by joining
/// `/api/enrollments/section/{id}` client-side, and stay null when that
/// join finds nothing — an unenrolled student is a real state, not an error.
@immutable
class AdminStudent {
  const AdminStudent({
    required this.id,
    required this.fullName,
    required this.admissionNumber,
    this.status,
    this.sectionId,
    this.classLabel,
  });

  factory AdminStudent.fromJson(Map<String, dynamic> json) {
    final first = json['firstName'] as String? ?? '';
    final last = json['lastName'] as String? ?? '';
    return AdminStudent(
      id: json['id'] as String,
      fullName: '$first $last'.trim(),
      admissionNumber: json['admissionNumber'] as String? ?? '',
      status: json['status'] as String?,
    );
  }

  final String id;
  final String fullName;
  final String admissionNumber;
  final String? status;
  final String? sectionId;
  final String? classLabel;

  AdminStudent withPlacement({String? sectionId, String? classLabel}) =>
      AdminStudent(
        id: id,
        fullName: fullName,
        admissionNumber: admissionNumber,
        status: status,
        sectionId: sectionId,
        classLabel: classLabel,
      );

  /// B-02: the backend ignores every search parameter (`q`, `search`, `name`,
  /// `query` — all verified live to return the unfiltered set), so filtering
  /// happens here, in the client, per D-20. Replace this with a server query
  /// the moment B-02 lands; it is the whole reason this method exists.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return fullName.toLowerCase().contains(q) ||
        admissionNumber.toLowerCase().contains(q);
  }
}

@immutable
class AdminClass {
  const AdminClass({required this.id, required this.name});

  factory AdminClass.fromJson(Map<String, dynamic> json) => AdminClass(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
      );

  final String id;
  final String name;
}

/// One row of the dashboard's completeness table.
///
/// The counts are NOT returned by any endpoint — `GET /api/sections` carries
/// neither a student count nor any timetable information (verified live).
/// They are assembled per section from `/api/enrollments/section/{id}` and
/// `/api/timetable/section/{id}`, which is why building this list is N+1.
@immutable
class SectionCompleteness {
  const SectionCompleteness({
    required this.sectionId,
    required this.sectionName,
    required this.className,
    required this.studentCount,
    required this.hasTimetable,
    required this.hasClassTeacher,
  });

  final String sectionId;
  final String sectionName;
  final String className;
  final int studentCount;
  final bool hasTimetable;
  final bool hasClassTeacher;

  String get label => '$className · $sectionName';

  bool get hasStudents => studentCount > 0;

  /// D-15's ordering rule, stated explicitly because it is a judgement the
  /// design made and a future reader cannot reconstruct it from the fields.
  ///
  /// LOWER rank = LESS complete = shown FIRST. An admin onboarding a school
  /// is not looking anything up; they are looking for what is unfinished,
  /// so the unfinished work sorts to the top and alphabetical order — which
  /// scatters it — is deliberately not used.
  ///
  /// The tiers, least complete first:
  ///   0. no students at all — nothing else about the section matters yet
  ///   1. students, but no timetable — cannot take a register
  ///   2. students and timetable, but no class teacher — runs, but unowned
  ///   3. complete
  ///
  /// Dependency order is why "no students" outranks "no timetable": a
  /// timetable for an empty section teaches nobody.
  int get completenessRank {
    if (!hasStudents) return 0;
    if (!hasTimetable) return 1;
    if (!hasClassTeacher) return 2;
    return 3;
  }

  /// What the row should tell the admin to do next. Null when complete —
  /// a "nothing to do" row must not invent an action (D-19).
  String? get nextAction => switch (completenessRank) {
        0 => 'No students enrolled',
        1 => 'No timetable set',
        2 => 'No class teacher assigned',
        _ => null,
      };
}

/// Sorts least-complete first, then by label so the order is stable and
/// repeatable rather than depending on whatever the API happened to return.
List<SectionCompleteness> sortByCompleteness(List<SectionCompleteness> rows) {
  final sorted = [...rows];
  sorted.sort((a, b) {
    final byRank = a.completenessRank.compareTo(b.completenessRank);
    return byRank != 0 ? byRank : a.label.compareTo(b.label);
  });
  return sorted;
}

/// Everything the dashboard renders.
@immutable
class AdminDashboard {
  const AdminDashboard({
    required this.studentCount,
    required this.staffCount,
    required this.sections,
  });

  final int studentCount;
  final int staffCount;
  final List<SectionCompleteness> sections;

  /// D-14: the empty-school checklist triggers on **no records existing**,
  /// never on "all the counters read zero".
  ///
  /// Those look identical on screen and are completely different things. A
  /// brand-new school genuinely has nothing and needs the setup checklist.
  /// A school whose counters read zero because a filter is applied, or
  /// because a request failed, has records — and telling an admin with 400
  /// students that their school is empty is worse than showing an error.
  ///
  /// This is derived ONLY from loaded records. A failed load never reaches
  /// here: it resolves to an error state before this is consulted, which is
  /// exactly what keeps "request failed" from impersonating "empty school".
  bool get isBrandNewSchool => sections.isEmpty && studentCount == 0;
}

/// Result of a CSV import. Returned COMPLETE by the POST itself — the import
/// is synchronous despite carrying a jobId (verified live 2026-09-18).
@immutable
class ImportResult {
  const ImportResult({
    required this.jobId,
    required this.status,
    required this.totalRows,
    required this.successRows,
    required this.errorRows,
  });

  factory ImportResult.fromJson(Map<String, dynamic> json) => ImportResult(
        jobId: json['jobId'] as String? ?? '',
        status: json['status'] as String? ?? '',
        totalRows: (json['totalRows'] as num?)?.toInt() ?? 0,
        successRows: (json['successRows'] as num?)?.toInt() ?? 0,
        errorRows: (json['errorRows'] as num?)?.toInt() ?? 0,
      );

  final String jobId;
  final String status;
  final int totalRows;
  final int successRows;
  final int errorRows;

  bool get hasErrors => errorRows > 0;
}

/// One rejected CSV row.
@immutable
class ImportRowError {
  const ImportRowError({required this.rowNumber, required this.message});

  factory ImportRowError.fromJson(Map<String, dynamic> json) => ImportRowError(
        rowNumber: (json['rowNumber'] as num?)?.toInt() ?? 0,
        message: json['message'] as String? ?? '',
      );

  /// 1-indexed and INCLUDING the header row, so the first data row is 2.
  /// Surfaced verbatim rather than adjusted — the admin is looking at the
  /// same file in a spreadsheet, where the header is also row 1.
  final int rowNumber;
  final String message;
}
