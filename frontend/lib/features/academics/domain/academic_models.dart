import 'dart:convert';

import '../../../core/widgets/status_pill.dart';
import 'marks.dart';

/// The academic-loop domain (T15 Batch C).
///
/// The same rule as money runs through all of it: **every total, percentage,
/// grade, grade point, position and pass/fail below is a field the server
/// sent.** A mark POST returns the whole recomputed result, so the app never
/// has to derive one — and must not, because two sources of truth for a
/// student's GPA is worse than one that is occasionally wrong: nobody can
/// tell which is right.

// --- Exams -------------------------------------------------------------------

/// The exam `term` vocabulary, found by exhaustive probe. An unlisted value
/// answers `400 "One or more fields have an invalid value"` with no field
/// name, so only these six are ever offered.
enum ExamTerm {
  weekly('weekly', 'Weekly'),
  monthly('monthly', 'Monthly'),
  firstTerm('first_term', 'First term'),
  midTerm('mid_term', 'Mid term'),
  final_('final', 'Final'),
  annual('annual', 'Annual');

  const ExamTerm(this.wire, this.label);

  final String wire;
  final String label;

  static String labelForWire(String? wire) {
    for (final t in ExamTerm.values) {
      if (t.wire == wire) return t.label;
    }
    return wire ?? '';
  }
}

/// C9 lifecycle, exactly as the server enforces it:
/// draft → marking → submitted → moderation → approved → published → archived.
///
/// The server is the authority: it refuses an out-of-order step with 409 and
/// publishing anything but an APPROVED exam with 409. This enum only decides
/// which action to offer; it never skips a step.
enum ExamStatus {
  draft('draft', 'Draft'),
  marking('marking', 'Marking'),
  submitted('submitted', 'Submitted for moderation'),
  moderation('moderation', 'In moderation'),
  approved('approved', 'Approved'),
  published('published', 'Published'),
  archived('archived', 'Archived');

  const ExamStatus(this.wire, this.label);

  final String wire;
  final String label;

  /// Pre-V55 values: `pending` was draft and `marks_entry` was marking. An
  /// unrecognised value is treated as a locked, unreleased state so the app
  /// never offers an edit or a release the server would refuse.
  static ExamStatus parse(String? raw) => switch (raw) {
    'draft' || 'pending' => ExamStatus.draft,
    'marking' || 'marks_entry' => ExamStatus.marking,
    'submitted' => ExamStatus.submitted,
    'moderation' => ExamStatus.moderation,
    'approved' => ExamStatus.approved,
    'published' => ExamStatus.published,
    'archived' => ExamStatus.archived,
    _ => ExamStatus.submitted,
  };

  /// The single next step the server accepts, or null at the end.
  ExamStatus? get next => switch (this) {
    ExamStatus.draft => ExamStatus.marking,
    ExamStatus.marking => ExamStatus.submitted,
    ExamStatus.submitted => ExamStatus.moderation,
    ExamStatus.moderation => ExamStatus.approved,
    ExamStatus.approved => ExamStatus.published,
    ExamStatus.published => ExamStatus.archived,
    ExamStatus.archived => null,
  };

  /// What the button for moving to [next] says.
  String? get nextActionLabel => switch (this) {
    ExamStatus.draft => 'Start marking',
    ExamStatus.marking => 'Submit for moderation',
    ExamStatus.submitted => 'Start moderation',
    ExamStatus.moderation => 'Approve results',
    ExamStatus.approved => 'Publish results',
    ExamStatus.published => 'Archive exam',
    ExamStatus.archived => null,
  };

  /// Visible to students and guardians (unless a result is withheld).
  bool get isReleased =>
      this == ExamStatus.published || this == ExamStatus.archived;

  /// Marks may be entered in draft and marking, and fixed by moderators.
  bool get marksEditable =>
      this == ExamStatus.draft ||
      this == ExamStatus.marking ||
      this == ExamStatus.moderation;

  /// Papers may be added only before submission.
  bool get papersEditable =>
      this == ExamStatus.draft || this == ExamStatus.marking;

  AppStatus get pill => switch (this) {
    ExamStatus.draft || ExamStatus.marking => AppStatus.notStarted,
    ExamStatus.submitted ||
    ExamStatus.moderation ||
    ExamStatus.approved => AppStatus.partial,
    ExamStatus.published || ExamStatus.archived => AppStatus.complete,
  };
}

class Exam {
  const Exam({
    required this.id,
    required this.name,
    required this.term,
    required this.status,
    required this.academicYearId,
    this.resultDate,
    this.campusId,
  });

  factory Exam.fromJson(Map<String, dynamic> json) => Exam(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    term: json['term'] as String?,
    status: ExamStatus.parse(json['status'] as String?),
    academicYearId: json['academic_year_id'] as String? ?? '',
    resultDate: json['result_date'] as String?,
    campusId: json['campus_id'] as String?,
  );

  final String id;
  final String name;
  final String? term;
  final ExamStatus status;
  final String academicYearId;
  final String? resultDate;

  /// The exam's campus; lifecycle actions need exam.manage on it (ADR-001).
  final String? campusId;

  String get termLabel => ExamTerm.labelForWire(term);

  /// Marks are locked outside draft, marking and moderation (C9). After
  /// publication only an official correction can change a result.
  bool get marksLocked => !status.marksEditable;
}

/// One paper: a subject, for one section, within an exam.
///
/// D-13 (dev backend be3, approval pending) adds `GET /api/exams/{id}/subjects`;
/// on older backends: 🔴 **a paper cannot be read back** — that call is 405
/// and re-creating the same paper answers 409 WITHOUT returning the existing
/// id. So the only moment its id is knowable is when it is created, which is
/// why the exam screen holds the papers it made for the session and marks
/// entry is reached from there. Open items 26 and 27.
class ExamPaper {
  const ExamPaper({
    required this.id,
    required this.examId,
    required this.sectionId,
    required this.subjectId,
    required this.maxMarks,
    required this.passingMarks,
    this.subjectName = '',
    this.sectionName = '',
  });

  factory ExamPaper.fromJson(
    Map<String, dynamic> json, {
    String subjectName = '',
    String sectionName = '',
  }) => ExamPaper(
    id: json['id'] as String,
    examId: json['exam_id'] as String? ?? '',
    sectionId: json['section_id'] as String? ?? '',
    subjectId: json['subject_id'] as String? ?? '',
    maxMarks: Marks.fromJson(json['max_marks']),
    passingMarks: Marks.fromJson(json['passing_marks']),
    subjectName: subjectName,
    sectionName: sectionName,
  );

  final String id;
  final String examId;
  final String sectionId;
  final String subjectId;
  final Marks maxMarks;
  final Marks passingMarks;
  final String subjectName;
  final String sectionName;
}

// --- Marks -------------------------------------------------------------------

/// D-24: a mark already saved on the server, as read back for one paper.
class SavedMark {
  const SavedMark({required this.marks, required this.isAbsent});

  /// Exact text from the server (e.g. "42.50"), or null when not entered.
  final String? marks;
  final bool isAbsent;
}

/// One student's entry on the marks screen, before it is sent.
class MarkEntry {
  const MarkEntry({
    required this.studentId,
    required this.studentName,
    this.text = '',
    this.isAbsent = false,
  });

  final String studentId;
  final String studentName;

  /// What the teacher typed, kept as text so a half-typed "8" is not a mark.
  final String text;
  final bool isAbsent;

  MarkEntry copyWith({String? text, bool? isAbsent}) => MarkEntry(
    studentId: studentId,
    studentName: studentName,
    text: text ?? this.text,
    isAbsent: isAbsent ?? this.isAbsent,
  );

  Marks? get value => text.trim().isEmpty ? null : Marks.tryParse(text);

  /// Whether this row is ready to send: absent, or a parsable mark.
  bool get isEntered => isAbsent || value != null;

  /// Why this row cannot be sent, in the teacher's words. Null when fine.
  ///
  /// Validated as the teacher types rather than on save, because finding out
  /// at the end of forty students which one was wrong is the whole problem.
  String? problem(Marks maxMarks) {
    if (isAbsent || text.trim().isEmpty) return null;
    final parsed = value;
    if (parsed == null) return 'Not a number';
    if (parsed.hundredths < 0) return 'Cannot be negative';
    if (parsed.compareTo(maxMarks) > 0) return 'Over ${maxMarks.format()}';
    return null;
  }
}

/// What a bulk marks POST reported.
class MarksSaveResult {
  const MarksSaveResult({
    required this.successCount,
    required this.errorCount,
    required this.errors,
  });

  factory MarksSaveResult.fromJson(Map<String, dynamic> json) =>
      MarksSaveResult(
        successCount: json['successCount'] as int? ?? 0,
        errorCount: json['errorCount'] as int? ?? 0,
        errors: (json['errors'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
      );

  final int successCount;
  final int errorCount;
  final List<String> errors;

  bool get allSaved => errorCount == 0;
}

// --- Results -----------------------------------------------------------------

/// The server's result status. `pending` means at least one mark is missing:
/// it is never a pass and never a zero (C9).
enum ResultStatus {
  pass('Passed'),
  fail('Failed'),
  absent('Absent'),
  pending('Incomplete');

  const ResultStatus(this.label);

  final String label;

  static ResultStatus parse(String? raw) => switch (raw) {
    'pass' => ResultStatus.pass,
    'fail' => ResultStatus.fail,
    'absent' => ResultStatus.absent,
    _ => ResultStatus.pending,
  };

  AppStatus get pill => switch (this) {
    ResultStatus.pass => AppStatus.complete,
    ResultStatus.fail || ResultStatus.absent => AppStatus.notStarted,
    ResultStatus.pending => AppStatus.partial,
  };
}

/// One student's result. Every figure is the server's.
class StudentResult {
  const StudentResult({
    required this.studentId,
    required this.studentName,
    required this.totalMarks,
    required this.totalMax,
    required this.percentage,
    required this.grade,
    required this.gradePoint,
    required this.position,
    required this.status,
    this.subjects = const [],
    this.publishedAt,
    this.withheld = false,
    this.withheldReason,
    this.currentVersion,
  });

  factory StudentResult.fromJson(Map<String, dynamic> json) => StudentResult(
    studentId: json['student_id'] as String? ?? '',
    studentName: json['student_name'] as String? ?? '',
    totalMarks: Marks.fromJson(json['total_marks']),
    totalMax: Marks.fromJson(json['total_max']),
    percentage: Marks.fromJson(json['percentage']),
    grade: json['grade'] as String? ?? '',
    gradePoint: Marks.fromJson(json['grade_point'], fallback: Marks.zero),
    position: json['position'] as int?,
    status: ResultStatus.parse(json['result_status'] as String?),
    subjects: (json['subjects'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(SubjectResult.fromJson)
        .toList(),
    publishedAt: json['published_at'] as String?,
    withheld: json['withheld'] as bool? ?? false,
    withheldReason: json['withheld_reason'] as String?,
    currentVersion: json['current_version'] as int?,
  );

  /// Hidden from the student and guardians until released (staff only).
  final bool withheld;
  final String? withheldReason;

  /// The official version in force (1 at publication, 2+ after corrections).
  final int? currentVersion;

  final String studentId;
  final String studentName;
  final Marks totalMarks;
  final Marks totalMax;
  final Marks percentage;
  final String grade;
  final Marks gradePoint;
  final int? position;
  final ResultStatus status;
  final List<SubjectResult> subjects;
  final String? publishedAt;

  /// A pass that is close to the line. Not a backend concept — a display
  /// hint for the D-15 ordering below, and never shown as a status.
  bool get isBorderline =>
      status == ResultStatus.pass && percentage.hundredths < 5000;
}

class SubjectResult {
  const SubjectResult({
    required this.subjectName,
    required this.maxMarks,
    required this.passingMarks,
    required this.marksObtained,
    required this.isAbsent,
    required this.grade,
    this.examSubjectId,
  });

  factory SubjectResult.fromJson(Map<String, dynamic> json) => SubjectResult(
    subjectName: json['subject_name'] as String? ?? '',
    maxMarks: Marks.fromJson(json['max_marks']),
    passingMarks: Marks.fromJson(json['passing_marks']),
    // A missing mark stays missing: never shown or counted as zero (C9).
    marksObtained: json['marks_obtained'] == null
        ? null
        : Marks.fromJson(json['marks_obtained']),
    examSubjectId: json['exam_subject_id'] as String?,
    isAbsent: json['is_absent'] as bool? ?? false,
    grade: json['grade'] as String? ?? '',
  );

  final String subjectName;
  final Marks maxMarks;
  final Marks passingMarks;
  final Marks? marksObtained;
  final bool isAbsent;
  final String grade;

  /// The paper this mark belongs to; needed for an official correction.
  final String? examSubjectId;

  bool get isMissing => !isAbsent && marksObtained == null;

  bool get failed =>
      !isAbsent &&
      marksObtained != null &&
      marksObtained!.compareTo(passingMarks) < 0;
}

/// D-15's principle applied to results: a list is ordered by what needs
/// attention.
///
/// Failures first, then borderline passes, then everyone else by position.
/// A teacher opens this to find who needs help, and alphabetical order
/// scatters the failures through forty rows.
List<StudentResult> sortResults(List<StudentResult> rows) {
  final sorted = [...rows];
  sorted.sort((a, b) {
    int rank(StudentResult r) {
      if (r.status == ResultStatus.fail || r.status == ResultStatus.absent) {
        return 0;
      }
      if (r.status == ResultStatus.pending) return 1;
      if (r.isBorderline) return 2;
      return 3;
    }

    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    // Within a band, the lowest percentage first — still "who needs help".
    final byPercent = a.percentage.compareTo(b.percentage);
    if (byPercent != 0) return byPercent;
    return a.studentName.compareTo(b.studentName);
  });
  return sorted;
}

/// What the report-card endpoint actually returns.
///
/// 🔴 Re-verified live: `{generatedAt, available, status}` and **no file
/// key**. `/pdf` and `/download` are both 404. So no download affordance
/// ships (D-19) — the screen shows the card and says so.
class ReportCard {
  const ReportCard({
    required this.generatedAt,
    required this.available,
    required this.status,
  });

  factory ReportCard.fromJson(Map<String, dynamic> json) => ReportCard(
    generatedAt: json['generatedAt'] as String? ?? '',
    available: json['available'] as bool? ?? false,
    status: json['status'] as String? ?? '',
  );

  final String generatedAt;
  final bool available;
  final String status;
}

/// One official release of a learner's result (C9). Version 1 is the
/// publication; later versions are corrections, each with its reason.
class ResultVersion {
  const ResultVersion({
    required this.version,
    required this.createdAt,
    this.reason,
    this.totalMarks,
  });

  factory ResultVersion.fromJson(Map<String, dynamic> json) {
    final raw = json['snapshot'];
    final snapshot = raw is String
        ? (jsonDecode(AcademicJson.quoteNumbers(raw)) as Map)
              .cast<String, dynamic>()
        : (raw as Map? ?? const {}).cast<String, dynamic>();
    return ResultVersion(
      version: json['version'] as int? ?? 0,
      createdAt: json['createdAt']?.toString() ?? '',
      reason: json['reason'] as String?,
      totalMarks: snapshot['total_marks']?.toString(),
    );
  }

  final int version;
  final String createdAt;
  final String? reason;
  final String? totalMarks;
}

/// What publishing reported.
class PublishResult {
  const PublishResult({
    required this.reportCardsGenerated,
    this.reportCardsQueued = 0,
    required this.resultsPublished,
  });

  factory PublishResult.fromJson(Map<String, dynamic> json) => PublishResult(
    reportCardsGenerated: json['reportCardsGenerated'] as int? ?? 0,
    reportCardsQueued: json['reportCardsQueued'] as int? ?? 0,
    resultsPublished: json['resultsPublished'] as int? ?? 0,
  );

  final int reportCardsGenerated;
  final int reportCardsQueued;
  final int resultsPublished;
}

// --- Remarks -----------------------------------------------------------------

/// A teacher's note about a student.
///
/// ⚠️ `isParentVisible` is enforced server-side **for parents only** — that
/// was verified with a parent token. It is NOT enforced for students: a
/// student token read another student's remarks, including ones flagged
/// false. The screen's copy therefore says exactly what the flag does and
/// never claims a remark is private in general. Open item 23.
class Remark {
  const Remark({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.remarkType,
    required this.body,
    required this.isParentVisible,
    required this.remarkDate,
    required this.authorName,
  });

  factory Remark.fromJson(Map<String, dynamic> json) => Remark(
    id: json['id'] as String,
    studentId: json['studentId'] as String? ?? '',
    studentName: json['studentName'] as String? ?? '',
    remarkType: json['remarkType'] as String? ?? '',
    body: json['body'] as String? ?? '',
    isParentVisible: json['isParentVisible'] as bool? ?? false,
    remarkDate: json['remarkDate'] as String? ?? '',
    authorName: json['authorName'] as String? ?? '',
  );

  final String id;
  final String studentId;
  final String studentName;
  final String remarkType;
  final String body;
  final bool isParentVisible;
  final String remarkDate;
  final String authorName;
}

/// The remark types offered. Free text on the wire, so this is a convenience
/// list rather than a constraint the backend enforces.
const List<String> remarkTypes = [
  'general',
  'academic',
  'behaviour',
  'attendance',
  'achievement',
];

// --- Syllabus ----------------------------------------------------------------

class Topic {
  const Topic({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.expectedPeriodCount,
  });

  factory Topic.fromJson(Map<String, dynamic> json) => Topic(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    sortOrder: json['sort_order'] as int? ?? 0,
    expectedPeriodCount: json['expected_period_count'] as int?,
  );

  final String id;
  final String name;
  final int sortOrder;
  final int? expectedPeriodCount;
}

class Chapter {
  const Chapter({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.topics,
    this.status = 'proposed',
    this.canEdit = false,
    this.canPublish = false,
    this.adopted = false,
    this.latestPublicationId,
  });

  /// The list endpoint nests topics, so one call fetches the whole syllabus.
  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
    id: json['id'] as String,
    status: json['status'] as String? ?? 'proposed',
    canEdit: json['canEdit'] == true,
    canPublish: json['canPublish'] == true,
    adopted: json['adopted'] == true,
    latestPublicationId: json['latestPublicationId'] as String?,
    name: json['name'] as String? ?? '',
    sortOrder: json['sort_order'] as int? ?? 0,
    topics:
        (json['topics'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(Topic.fromJson)
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
  );

  final String id;
  final String name;
  final int sortOrder;
  final List<Topic> topics;
  final String status;
  final bool canEdit, canPublish, adopted;
  final String? latestPublicationId;
}

/// The only two coverage statuses the backend accepts, lowercase.
/// `pending` is rejected — "not covered" is the absence of a log, not a
/// status you can post.
enum CoverageStatus {
  covered('covered', 'Covered'),
  partial('partial', 'Partly covered');

  const CoverageStatus(this.wire, this.label);

  final String wire;
  final String label;
}

class ChapterProgress {
  const ChapterProgress({
    required this.name,
    required this.status,
    required this.topics,
    required this.covered,
  });

  factory ChapterProgress.fromJson(Map<String, dynamic> json) =>
      ChapterProgress(
        name: json['name'] as String? ?? '',
        status: json['status'] as String? ?? '',
        topics: json['topics'] as int? ?? 0,
        covered: json['covered'] as int? ?? 0,
      );

  final String name;
  final String status;
  final int topics;
  final int covered;
}

/// 🔴 Server-computed. The T15 brief assumed the backend does not provide
/// progress and that computing `covered ÷ total` client-side was correct
/// here — it does provide it (`GET /api/syllabus/progress`), so the same
/// rule as marks and money applies: render it, do not derive it.
class SyllabusProgress {
  const SyllabusProgress({
    required this.percentage,
    required this.coveredTopics,
    required this.totalTopics,
    required this.coveredChapters,
    required this.totalChapters,
    required this.chapters,
  });

  factory SyllabusProgress.fromJson(Map<String, dynamic> json) =>
      SyllabusProgress(
        percentage: Marks.fromJson(json['percentage'], fallback: Marks.zero),
        coveredTopics: json['coveredTopics'] as int? ?? 0,
        totalTopics: json['totalTopics'] as int? ?? 0,
        coveredChapters: json['coveredChapters'] as int? ?? 0,
        totalChapters: json['totalChapters'] as int? ?? 0,
        chapters: (json['chapters'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ChapterProgress.fromJson)
            .toList(),
      );

  final Marks percentage;
  final int coveredTopics;
  final int totalTopics;
  final int coveredChapters;
  final int totalChapters;
  final List<ChapterProgress> chapters;
}

// --- Grade bands -------------------------------------------------------------

/// One band of a grade scheme: a percentage range mapped to a grade.
///
/// ⚠️ **Nothing in the app can create one.** There is no grade-scheme
/// endpoint of any kind on this backend (open item 24), so this type and
/// [validateBands] are deliberately NOT wired to a screen. They exist
/// because the validation rule is the whole point of the feature and is
/// worth pinning now: a gap between bands means a student scoring in it
/// gets no grade at all, and that surfaces at result time, far from the
/// cause.
class GradeBand {
  const GradeBand({
    required this.minPercent,
    required this.maxPercent,
    required this.grade,
    required this.gradePoint,
  });

  final Marks minPercent;
  final Marks maxPercent;
  final String grade;
  final Marks gradePoint;
}

/// Why a set of bands is not usable, in the admin's words. Null when valid.
///
/// Bands must together cover 0–100 with no gap and no overlap.
String? validateBands(List<GradeBand> bands) {
  if (bands.isEmpty) return 'Add at least one band.';

  final sorted = [...bands]
    ..sort((a, b) => a.minPercent.compareTo(b.minPercent));

  for (final band in sorted) {
    if (band.minPercent.compareTo(band.maxPercent) > 0) {
      return 'Band “${band.grade}” starts above where it ends.';
    }
    if (band.grade.trim().isEmpty) return 'Every band needs a grade.';
  }

  if (sorted.first.minPercent.hundredths != 0) {
    return 'The lowest band must start at 0 — a student scoring below '
        '${sorted.first.minPercent.format()}% would get no grade.';
  }
  if (sorted.last.maxPercent.hundredths != 10000) {
    return 'The highest band must end at 100 — a student scoring above '
        '${sorted.last.maxPercent.format()}% would get no grade.';
  }

  for (var i = 1; i < sorted.length; i++) {
    final previous = sorted[i - 1];
    final current = sorted[i];
    final expected = previous.maxPercent.hundredths + 1;
    if (current.minPercent.hundredths <= previous.maxPercent.hundredths) {
      return 'Bands “${previous.grade}” and “${current.grade}” overlap — a '
          'score in the overlap could be either grade.';
    }
    if (current.minPercent.hundredths > expected) {
      return 'Nothing covers the range between ${previous.grade} and '
          '${current.grade} — a student scoring there would get no grade.';
    }
  }

  return null;
}

/// D-20 (proposed contract): a grade scheme and its bands, read-only.
/// Decimal values are kept as the server's strings (NUMERIC, rule #4).
class GradeSchemeView {
  const GradeSchemeView({required this.name, required this.bands});

  factory GradeSchemeView.fromJson(Map<String, dynamic> json) =>
      GradeSchemeView(
        name: json['name'] as String? ?? 'Grade scheme',
        bands:
            (json['bands'] as List? ?? const [])
                .whereType<Map>()
                .map((b) => GradeBandView.fromJson(b.cast<String, dynamic>()))
                .toList()
              ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
      );

  final String name;
  final List<GradeBandView> bands;
}

class GradeBandView {
  const GradeBandView({
    required this.grade,
    required this.minPercentage,
    required this.maxPercentage,
    required this.gradePoint,
    this.remark,
    this.sortOrder = 0,
  });

  factory GradeBandView.fromJson(Map<String, dynamic> json) => GradeBandView(
    grade: json['grade'] as String? ?? '',
    minPercentage: '${json['minPercentage'] ?? ''}',
    maxPercentage: '${json['maxPercentage'] ?? ''}',
    gradePoint: '${json['gradePoint'] ?? ''}',
    remark: json['remark'] as String?,
    sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
  );

  final String grade;
  final String minPercentage;
  final String maxPercentage;
  final String gradePoint;
  final String? remark;
  final int sortOrder;
}

/// The outcome of reading the grade scheme (D-20), each case distinct.
enum GradeSchemeOutcome { loaded, notConfigured, notPermitted, unsupported }

class GradeSchemeLoad {
  const GradeSchemeLoad.loaded(GradeSchemeView this.scheme)
    : outcome = GradeSchemeOutcome.loaded;
  const GradeSchemeLoad.notConfigured()
    : outcome = GradeSchemeOutcome.notConfigured,
      scheme = null;
  const GradeSchemeLoad.notPermitted()
    : outcome = GradeSchemeOutcome.notPermitted,
      scheme = null;
  const GradeSchemeLoad.unsupported()
    : outcome = GradeSchemeOutcome.unsupported,
      scheme = null;

  final GradeSchemeOutcome outcome;
  final GradeSchemeView? scheme;
}
