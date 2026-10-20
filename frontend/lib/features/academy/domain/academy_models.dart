/// Academy (Phase B) models. Field names are the backend's own: the Academy
/// API returns JDBC row maps, so keys are snake_case (`campus_id`), while
/// `Page` envelopes, request bodies and the profile view are camelCase.
///
/// Money and marks arrive as exact decimal STRINGS (the repository quotes
/// them before decoding) and stay strings here — never a `double`.
library;

String _s(Map m, String k) => m[k]?.toString() ?? '';
String? _o(Map m, String k) => m[k]?.toString();

/// `2026-10-14`, or an epoch-millisecond number if the server ever sends one.
String _date(Object? v) {
  if (v == null) return '';
  if (v is num) {
    return DateTime.fromMillisecondsSinceEpoch(
      v.toInt(),
      isUtc: true,
    ).toIso8601String().substring(0, 10);
  }
  final s = v.toString();
  return s.length >= 10 ? s.substring(0, 10) : s;
}

/// `16:00:00` → `16:00`.
String _time(Object? v) {
  final s = v?.toString() ?? '';
  return s.length >= 5 ? s.substring(0, 5) : s;
}

class InstitutionProfile {
  const InstitutionProfile({
    required this.profile,
    required this.academyEnabled,
    required this.capabilities,
  });
  factory InstitutionProfile.fromJson(Map json) => InstitutionProfile(
    profile: json['profile']?.toString() ?? 'SCHOOL',
    academyEnabled: json['academyEnabled'] == true,
    capabilities: ((json['supportedCapabilities'] as List?) ?? const [])
        .map((e) => '$e')
        .toList(),
  );
  final String profile;
  final bool academyEnabled;
  final List<String> capabilities;

  static const labels = {
    'SCHOOL': 'School',
    'PRE_UNIVERSITY_COLLEGE': 'Pre-university college',
    'ACADEMY': 'Academy / coaching centre',
  };
}

class ProfileChange {
  const ProfileChange({
    required this.oldProfile,
    required this.newProfile,
    required this.reason,
    required this.changedAt,
  });
  factory ProfileChange.fromJson(Map j) => ProfileChange(
    oldProfile: _s(j, 'oldProfile'),
    newProfile: _s(j, 'newProfile'),
    reason: _s(j, 'reason'),
    changedAt: _s(j, 'changedAt'),
  );
  final String oldProfile, newProfile, reason, changedAt;
}

class Course {
  const Course({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    this.level,
    required this.status,
  });
  factory Course.fromJson(Map j) => Course(
    id: _s(j, 'id'),
    code: _s(j, 'code'),
    name: _s(j, 'name'),
    description: _o(j, 'description'),
    level: _o(j, 'level'),
    status: _s(j, 'status'),
  );
  final String id, code, name, status;
  final String? description, level;
  bool get archived => status == 'archived';
}

class Offering {
  const Offering({
    required this.id,
    required this.courseId,
    required this.courseName,
    required this.campusId,
    required this.academicYearId,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.status,
  });
  factory Offering.fromJson(Map j) => Offering(
    id: _s(j, 'id'),
    courseId: _s(j, 'course_id'),
    courseName: _s(j, 'course_name'),
    campusId: _s(j, 'campus_id'),
    academicYearId: _s(j, 'academic_year_id'),
    name: _s(j, 'name'),
    startDate: _date(j['start_date']),
    endDate: _date(j['end_date']),
    status: _s(j, 'status'),
  );
  final String id,
      courseId,
      courseName,
      campusId,
      academicYearId,
      name,
      startDate,
      endDate,
      status;
  bool get acceptsBatches => status == 'planned' || status == 'open';
}

class Batch {
  const Batch({
    required this.id,
    required this.name,
    required this.status,
    this.capacity,
    this.defaultRoom,
    required this.campusId,
    required this.offeringId,
    required this.offeringName,
    required this.courseName,
    required this.courseCode,
    required this.startDate,
    required this.endDate,
    required this.activeLearners,
  });
  factory Batch.fromJson(Map j) => Batch(
    id: _s(j, 'id'),
    name: _s(j, 'name'),
    status: _s(j, 'status'),
    capacity: (j['capacity'] as num?)?.toInt(),
    defaultRoom: _o(j, 'default_room'),
    campusId: _s(j, 'campus_id'),
    offeringId: _s(j, 'offering_id'),
    offeringName: _s(j, 'offering_name'),
    courseName: _s(j, 'course_name'),
    courseCode: _s(j, 'course_code'),
    startDate: _date(j['start_date']),
    endDate: _date(j['end_date']),
    activeLearners: (j['active_learners'] as num?)?.toInt() ?? 0,
  );
  final String id,
      name,
      status,
      campusId,
      offeringId,
      offeringName,
      courseName,
      courseCode,
      startDate,
      endDate;
  final int? capacity;
  final String? defaultRoom;
  final int activeLearners;
  bool get isOpen => status == 'open';
  bool get isFull => capacity != null && activeLearners >= capacity!;
}

class Instructor {
  const Instructor({
    required this.id,
    required this.staffId,
    required this.role,
    required this.name,
  });
  factory Instructor.fromJson(Map j) => Instructor(
    id: _s(j, 'id'),
    staffId: _s(j, 'staff_id'),
    role: _s(j, 'role'),
    name: '${_s(j, 'first_name')} ${_s(j, 'last_name')}'.trim(),
  );
  final String id, staffId, role, name;
}

class ScheduleSlot {
  const ScheduleSlot({
    required this.id,
    required this.dayOfWeek,
    required this.start,
    required this.end,
    this.room,
  });
  factory ScheduleSlot.fromJson(Map j) => ScheduleSlot(
    id: _s(j, 'id'),
    dayOfWeek: (j['day_of_week'] as num?)?.toInt() ?? 1,
    start: _time(j['start_time']),
    end: _time(j['end_time']),
    room: _o(j, 'room'),
  );
  final String id, start, end;
  final int dayOfWeek;
  final String? room;
  static const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  String get dayLabel => days[(dayOfWeek - 1).clamp(0, 6)];
}

class BatchDetail {
  const BatchDetail({
    required this.batch,
    required this.instructors,
    required this.schedule,
  });
  factory BatchDetail.fromJson(Map j) => BatchDetail(
    batch: Batch.fromJson(j),
    instructors: [
      for (final i in (j['instructors'] as List? ?? const []))
        Instructor.fromJson(i as Map),
    ],
    schedule: [
      for (final s in (j['schedule'] as List? ?? const []))
        ScheduleSlot.fromJson(s as Map),
    ],
  );
  final Batch batch;
  final List<Instructor> instructors;
  final List<ScheduleSlot> schedule;
}

class Enrollment {
  const Enrollment({
    required this.id,
    required this.batchId,
    required this.batchName,
    required this.courseName,
    required this.studentId,
    required this.status,
    required this.enrolledOn,
    this.endedOn,
    this.endReason,
  });
  factory Enrollment.fromJson(Map j) => Enrollment(
    id: _s(j, 'id'),
    batchId: _s(j, 'batch_id'),
    batchName: _s(j, 'batch_name'),
    courseName: _s(j, 'course_name'),
    studentId: _s(j, 'student_id'),
    status: _s(j, 'status'),
    enrolledOn: _date(j['enrolled_on']),
    endedOn: j['ended_on'] == null ? null : _date(j['ended_on']),
    endReason: _o(j, 'end_reason'),
  );
  final String id,
      batchId,
      batchName,
      courseName,
      studentId,
      status,
      enrolledOn;
  final String? endedOn, endReason;
  bool get active => status == 'active';
}

class RosterEntry {
  const RosterEntry({
    required this.enrollmentId,
    required this.studentId,
    required this.name,
    required this.admissionNumber,
    required this.enrolledOn,
  });
  factory RosterEntry.fromJson(Map j) => RosterEntry(
    enrollmentId: _s(j, 'enrollment_id'),
    studentId: _s(j, 'student_id'),
    name: '${_s(j, 'first_name')} ${_s(j, 'last_name')}'.trim(),
    admissionNumber: _s(j, 'admission_number'),
    enrolledOn: _date(j['enrolled_on']),
  );
  final String enrollmentId, studentId, name, admissionNumber, enrolledOn;
}

/// One of the caller's own sessions on Teacher Today.
class MySession {
  const MySession({
    required this.session,
    required this.batchName,
    required this.courseName,
    required this.activeLearners,
    required this.marked,
    required this.canMark,
  });
  factory MySession.fromJson(Map j) => MySession(
    session: Session.fromJson(j),
    batchName: _s(j, 'batch_name'),
    courseName: _s(j, 'course_name'),
    activeLearners: (j['active_learners'] as num?)?.toInt() ?? 0,
    marked: (j['marked'] as num?)?.toInt() ?? 0,
    canMark: j['can_mark'] == true,
  );
  final Session session;
  final String batchName, courseName;
  final int activeLearners, marked;

  /// Server-computed (not cancelled, not in the future, attendance.mark on
  /// the campus). The server re-checks on every submission.
  final bool canMark;
}

class Session {
  const Session({
    required this.id,
    required this.batchId,
    required this.date,
    required this.start,
    required this.end,
    this.room,
    required this.status,
  });
  factory Session.fromJson(Map j) => Session(
    id: _s(j, 'id'),
    batchId: _s(j, 'batch_id'),
    date: _date(j['session_date']),
    start: _time(j['start_time']),
    end: _time(j['end_time']),
    room: _o(j, 'room'),
    status: _s(j, 'status'),
  );
  final String id, batchId, date, start, end, status;
  final String? room;
  bool get cancelled => status == 'cancelled';
}

/// Attendance statuses the backend accepts, plus the read-only "unmarked".
const attendanceStatuses = ['present', 'absent', 'late', 'leave', 'excused'];

class SheetLearner {
  const SheetLearner({
    required this.studentId,
    required this.name,
    required this.admissionNumber,
    required this.status,
  });
  factory SheetLearner.fromJson(Map j) => SheetLearner(
    studentId: _s(j, 'student_id'),
    name: '${_s(j, 'first_name')} ${_s(j, 'last_name')}'.trim(),
    admissionNumber: _s(j, 'admission_number'),
    status: _s(j, 'status'),
  );
  final String studentId, name, admissionNumber, status;
  bool get unmarked => status == 'unmarked';
}

class AttendanceSheet {
  const AttendanceSheet({required this.session, required this.learners});
  factory AttendanceSheet.fromJson(Map j) => AttendanceSheet(
    session: Session.fromJson(j),
    learners: [
      for (final l in (j['learners'] as List? ?? const []))
        SheetLearner.fromJson(l as Map),
    ],
  );
  final Session session;
  final List<SheetLearner> learners;
}

class RowResult {
  const RowResult({
    required this.clientUuid,
    required this.studentId,
    required this.outcome,
    this.errorCode,
  });
  factory RowResult.fromJson(Map j) => RowResult(
    clientUuid: _s(j, 'clientUuid'),
    studentId: _s(j, 'studentId'),
    outcome: _s(j, 'outcome'),
    errorCode: _o(j, 'errorCode'),
  );
  final String clientUuid, studentId, outcome;
  final String? errorCode;
  bool get saved => outcome == 'recorded' || outcome == 'replayed';

  static const messages = {
    'NOT_ENROLLED': 'Not an active member of this batch on the session date.',
    'FUTURE_SESSION': 'This session has not happened yet.',
    'SESSION_CANCELLED': 'The session is cancelled.',
    'CORRECTION_LOCKED':
        'Locked after the correction window — ask an administrator.',
    'OPERATION_MISMATCH': 'A different mark already used this submission id.',
    'INVALID_STATUS': 'Unknown status.',
  };
  String get message =>
      messages[errorCode] ?? 'Not saved (${errorCode ?? 'rejected'}).';
}

class Assessment {
  const Assessment({
    required this.id,
    required this.batchId,
    required this.title,
    required this.maxMarks,
    required this.assessedOn,
    required this.status,
  });
  factory Assessment.fromJson(Map j) => Assessment(
    id: _s(j, 'id'),
    batchId: _s(j, 'batch_id'),
    title: _s(j, 'title'),
    maxMarks: _s(j, 'max_marks'),
    assessedOn: _date(j['assessed_on']),
    status: _s(j, 'status'),
  );
  final String id, batchId, title, maxMarks, assessedOn, status;
  bool get published => status == 'published';
}

class MarkEntry {
  const MarkEntry({
    required this.studentId,
    required this.name,
    this.marks,
    required this.absent,
    this.remarks,
  });
  factory MarkEntry.fromJson(Map j) => MarkEntry(
    studentId: _s(j, 'student_id'),
    name: '${_s(j, 'first_name')} ${_s(j, 'last_name')}'.trim(),
    marks: _o(j, 'marks'),
    absent: j['absent'] == true,
    remarks: _o(j, 'remarks'),
  );
  final String studentId, name;
  final String? marks, remarks;
  final bool absent;
}

class LearnerResult {
  const LearnerResult({
    required this.courseName,
    required this.batchName,
    required this.title,
    required this.maxMarks,
    this.marks,
    required this.absent,
    required this.status,
    required this.assessedOn,
  });
  factory LearnerResult.fromJson(Map j) => LearnerResult(
    courseName: _s(j, 'course_name'),
    batchName: _s(j, 'batch_name'),
    title: _s(j, 'title'),
    maxMarks: _s(j, 'max_marks'),
    marks: _o(j, 'marks'),
    absent: j['absent'] == true,
    status: _s(j, 'status'),
    assessedOn: _date(j['assessed_on']),
  );
  final String courseName, batchName, title, maxMarks, status, assessedOn;
  final String? marks;
  final bool absent;
}

class LearnerAttendance {
  const LearnerAttendance({
    required this.courseName,
    required this.batchName,
    required this.date,
    required this.start,
    required this.status,
  });
  factory LearnerAttendance.fromJson(Map j) => LearnerAttendance(
    courseName: _s(j, 'course_name'),
    batchName: _s(j, 'batch_name'),
    date: _date(j['session_date']),
    start: _time(j['start_time']),
    status: _s(j, 'status'),
  );
  final String courseName, batchName, date, start, status;
}

/// One append-only price version (V50), effective from a billing month (YYYY-MM).
class FeeVersion {
  const FeeVersion({
    required this.id,
    required this.amount,
    required this.effectiveFrom,
    required this.reason,
    required this.dueDay,
  });
  factory FeeVersion.fromJson(Map j) => FeeVersion(
    id: _s(j, 'id'),
    amount: _s(j, 'amount'),
    effectiveFrom: _s(j, 'effective_from').trim(),
    reason: _s(j, 'reason'),
    dueDay: (j['due_day'] as num?)?.toInt() ?? 10,
  );
  final String id, amount, effectiveFrom, reason;
  final int dueDay;
}

/// The batch's price as the server reports it: the version effective in the current
/// institution month (top-level fields) plus the full history and scheduled versions.
class BatchFee {
  const BatchFee({
    required this.feeHeadName,
    required this.amount,
    required this.frequency,
    required this.dueDay,
    this.currentMonth = '',
    this.currentVersionId = '',
    this.versions = const [],
    this.adjustments = 0,
  });
  factory BatchFee.fromJson(Map j) => BatchFee(
    feeHeadName: _s(j, 'fee_head_name'),
    amount: _s(j, 'amount'),
    frequency: _s(j, 'frequency'),
    dueDay: (j['due_day'] as num?)?.toInt() ?? 10,
    currentMonth: _s(j, 'current_month'),
    currentVersionId: _s(j, 'id'),
    versions: [
      for (final v in (j['versions'] as List? ?? const []))
        FeeVersion.fromJson(v as Map),
    ],
    adjustments: (j['adjustments'] as num?)?.toInt() ?? 0,
  );
  final String feeHeadName, amount, frequency, currentMonth, currentVersionId;
  final int dueDay, adjustments;
  final List<FeeVersion> versions;
  bool get monthly => frequency == 'monthly';

  /// Versions taking effect after the current month (not yet billed to anyone).
  List<FeeVersion> get scheduled => [
    for (final v in versions)
      if (currentMonth.isNotEmpty &&
          v.effectiveFrom.compareTo(currentMonth) > 0)
        v,
  ];
}

class GenerateResult {
  const GenerateResult({
    required this.billingKey,
    required this.generated,
    required this.alreadyBilled,
  });
  factory GenerateResult.fromJson(Map j) => GenerateResult(
    billingKey: _s(j, 'billingKey'),
    generated: (j['generated'] as num?)?.toInt() ?? 0,
    alreadyBilled: (j['alreadyBilled'] as num?)?.toInt() ?? 0,
  );
  final String billingKey;
  final int generated, alreadyBilled;
}

/// Picker rows from existing school endpoints (camelCase entities).
class Pick {
  const Pick(this.id, this.label, [this.detail]);
  final String id, label;
  final String? detail;
}

/// Finance-discovery row (`/api/academy/finance/batches`, fee.manage only).
class FinanceBatch {
  const FinanceBatch({required this.batch, this.feeAmount, this.feeFrequency});
  factory FinanceBatch.fromJson(Map j) => FinanceBatch(
    batch: Batch.fromJson(j),
    feeAmount: j['fee_amount']?.toString(),
    feeFrequency: j['fee_frequency']?.toString(),
  );
  final Batch batch;
  final String? feeAmount, feeFrequency;
}

/// Server-computed money totals (exact decimal strings).
class MoneyTotals {
  const MoneyTotals({
    required this.invoices,
    required this.invoiced,
    required this.collected,
    required this.outstanding,
  });
  factory MoneyTotals.fromJson(Map j) => MoneyTotals(
    invoices: (j['invoices'] as num?)?.toInt() ?? 0,
    invoiced: '${j['invoiced'] ?? '0'}',
    collected: '${j['collected'] ?? '0'}',
    outstanding: '${j['outstanding'] ?? '0'}',
  );
  final int invoices;
  final String invoiced, collected, outstanding;
}

class BatchInvoice {
  const BatchInvoice({
    required this.invoiceId,
    required this.studentName,
    required this.admissionNumber,
    required this.period,
    required this.dueDate,
    required this.status,
    required this.total,
    required this.paid,
    required this.outstanding,
  });
  factory BatchInvoice.fromJson(Map j) => BatchInvoice(
    invoiceId: '${j['invoice_id']}',
    studentName: '${j['student_name'] ?? ''}',
    admissionNumber: '${j['admission_number'] ?? ''}',
    period: '${j['period'] ?? ''}',
    dueDate: _date(j['due_date']),
    status: '${j['status'] ?? ''}',
    total: '${j['total_amount'] ?? '0'}',
    paid: '${j['paid_amount'] ?? '0'}',
    outstanding: '${j['outstanding'] ?? '0'}',
  );
  final String invoiceId,
      studentName,
      admissionNumber,
      period,
      dueDate,
      status,
      total,
      paid,
      outstanding;
}

class CollectionRow {
  const CollectionRow({
    required this.campusName,
    required this.courseName,
    required this.batchName,
    required this.period,
    required this.totals,
  });
  factory CollectionRow.fromJson(Map j) => CollectionRow(
    campusName: '${j['campus_name'] ?? ''}',
    courseName: '${j['course_name'] ?? ''}',
    batchName: '${j['batch_name'] ?? ''}',
    period: '${j['period'] ?? ''}',
    totals: MoneyTotals.fromJson(j),
  );
  final String campusName, courseName, batchName, period;
  final MoneyTotals totals;
}
