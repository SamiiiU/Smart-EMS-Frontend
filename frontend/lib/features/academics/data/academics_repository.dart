import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../../../core/network/api_error_mapper.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../attendance/domain/attendance_models.dart' show RosterStudent;
import '../domain/academic_models.dart';
import '../domain/marks.dart';

/// Every academic call the app makes (T15 Batch C).
///
/// 🔴 **All reads go through [_json], which asks dio for the RAW TEXT and
/// quotes the numeric literals before decoding** — the same single door as
/// `FinanceRepository`, and for the same reason: marks and percentages
/// arrive as bare JSON numbers (`85.50`, `3.70`), and `jsonDecode` would
/// turn them into binary floats before any of our code could object. A
/// `dio.get` added beside this silently breaks the guarantee.
///
/// Failures throw [LoadFailure], except the write paths that have an
/// expected non-success answer — saving marks and publishing — which return
/// a typed message, because "that is over the maximum" is an ordinary
/// outcome of entering marks, not an error state that should blank a screen
/// holding forty rows of unsaved work.
class AcademicsRepository {
  const AcademicsRepository(this.dio);

  final Dio dio;

  static final Options _plain = Options(responseType: ResponseType.plain);

  Future<Object?> _json(Future<Response<dynamic>> Function() call) async {
    try {
      final res = await call();
      final raw = res.data;
      if (raw == null) return null;
      final text = raw is String ? raw : raw.toString();
      if (text.isEmpty) return null;
      return jsonDecode(AcademicJson.quoteNumbers(text));
    } on DioException catch (err) {
      throw mapDioError(decodeErrorBody(err));
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

  /// Re-decodes a plain-text error body into a Map before it is mapped.
  ///
  /// 🔴 Necessary because these repositories ask dio for
  /// `ResponseType.plain` — that is what keeps money and marks away from
  /// `jsonDecode`'s number parser. `mapDioError` reads `message` only when
  /// the body is already a Map, so without this every server message on a
  /// read path was silently replaced by a generic fallback, and errors like
  /// "Student is not enrolled in this section" never reached the screen.
  static DioException decodeErrorBody(DioException err) {
    final response = err.response;
    final body = response?.data;
    if (body is! String || body.isEmpty) return err;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return err;
      return err.copyWith(
        response: Response<dynamic>(
          data: decoded,
          statusCode: response!.statusCode,
          statusMessage: response.statusMessage,
          headers: response.headers,
          requestOptions: response.requestOptions,
        ),
      );
    } on FormatException {
      return err;
    }
  }

  Future<List<Map<String, dynamic>>> _array(String path,
      [Map<String, dynamic>? query]) async {
    final body = await _json(
      () => dio.get<dynamic>(path, queryParameters: query, options: _plain),
    );
    return (body as List? ?? const []).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> _object(String path,
      [Map<String, dynamic>? query]) async {
    final body = await _json(
      () => dio.get<dynamic>(path, queryParameters: query, options: _plain),
    );
    return (body as Map?)?.cast<String, dynamic>() ?? const {};
  }

  // --- Exams -----------------------------------------------------------------

  /// `academicYearId` is honoured (bogus-id control → empty), and is always
  /// passed: the backend's `current` flag points at an EXPIRED year, so a
  /// year-less list would quietly show last year's exams.
  Future<List<Exam>> loadExams({required String academicYearId}) async {
    final rows = await _array('/api/exams', {
      'academicYearId': academicYearId,
    });
    return rows.map(Exam.fromJson).toList();
  }

  /// `academicYearId` is REQUIRED by this endpoint — the server does not
  /// resolve it. That is why exam creation is not blocked by the
  /// current-year bug: nothing here depends on the flag.
  ///
  /// `gradeSchemeId` is deliberately NOT sent. The field exists on the
  /// request, but no endpoint can create or list a grade scheme, so there is
  /// no id to send and pretending otherwise would be a guess (open item 24).
  Future<Exam> createExam({
    required String campusId,
    required String academicYearId,
    required String name,
    ExamTerm? term,
  }) async {
    final body = await _json(
      () => dio.post<dynamic>(
        '/api/exams',
        data: {
          'campusId': campusId,
          'academicYearId': academicYearId,
          'name': name,
          'term': ?term?.wire,
        },
        options: _plain,
      ),
    );
    return Exam.fromJson((body as Map).cast<String, dynamic>());
  }

  /// Creates a paper.
  ///
  /// 🔴 The returned id is the ONLY time this paper is identifiable —
  /// papers cannot be listed (405) and re-creating one answers 409 without
  /// returning the existing id. Callers must hold on to it.
  Future<ExamPaper> createPaper({
    required String examId,
    required String sectionId,
    required String subjectId,
    required Marks maxMarks,
    required Marks passingMarks,
    String? examDate,
    String subjectName = '',
    String sectionName = '',
  }) async {
    final body = await _json(
      () => dio.post<dynamic>(
        '/api/exams/$examId/subjects',
        data: {
          'sectionId': sectionId,
          'subjectId': subjectId,
          // Sent as exact decimal text, never as a double.
          'maxMarks': maxMarks.toBackendString(),
          'passingMarks': passingMarks.toBackendString(),
          'examDate': ?examDate,
        },
        options: _plain,
      ),
    );
    return ExamPaper.fromJson(
      (body as Map).cast<String, dynamic>(),
      subjectName: subjectName,
      sectionName: sectionName,
    );
  }

  // --- Roster ----------------------------------------------------------------

  /// A section's students, for marks entry and remarks.
  ///
  /// Assembled from TWO calls because no single endpoint provides it —
  /// `/api/enrollments/section/{id}` carries the ids and roll numbers but no
  /// names, so names come from `/api/students`. That is the same join
  /// `AttendanceRepository.loadRoster` does.
  ///
  /// It is duplicated here rather than reused because that repository also
  /// owns the offline attendance QUEUE, which needs a local database.
  /// Constructing one just to read a list of names would drag an offline
  /// write path into a feature that has none. The shared piece — the
  /// [RosterStudent] type — IS reused.
  Future<List<RosterStudent>> loadRoster(String sectionId) async {
    final enrollments =
        await _object('/api/enrollments/section/$sectionId');
    final rows = (enrollments['content'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .where((e) => e['status'] == 'enrolled')
        .toList();
    if (rows.isEmpty) return const [];

    final students = await _object('/api/students', const {'size': 500});
    final byId = {
      for (final s in (students['content'] as List? ?? const [])
          .cast<Map<String, dynamic>>())
        s['id'] as String: s,
    };

    final roster = <RosterStudent>[];
    for (final e in rows) {
      final id = e['studentId'] as String;
      final s = byId[id];
      roster.add(RosterStudent(
        studentId: id,
        fullName: s == null
            ? 'Unknown student'
            : '${s['firstName'] ?? ''} ${s['lastName'] ?? ''}'.trim(),
        rollNumber: e['rollNumber'] as String?,
      ));
    }
    roster.sort((a, b) => a.fullName.compareTo(b.fullName));
    return roster;
  }

  // --- Marks -----------------------------------------------------------------

  /// Saves a whole section's marks in one call.
  ///
  /// The bulk endpoint takes a **bare array** — an object answers
  /// "Malformed request body". Rows with nothing entered are left out
  /// entirely rather than sent as zero, because an unentered mark and a mark
  /// of zero are different facts about a student.
  Future<({MarksSaveResult? result, String? error})> saveMarks({
    required String examSubjectId,
    required List<MarkEntry> entries,
  }) async {
    final rows = [
      for (final entry in entries)
        if (entry.isEntered)
          {
            'studentId': entry.studentId,
            'isAbsent': entry.isAbsent,
            if (!entry.isAbsent)
              'marksObtained': entry.value!.toBackendString(),
          },
    ];
    if (rows.isEmpty) {
      return (result: null, error: 'Nothing has been entered yet.');
    }

    try {
      final res = await dio.post<dynamic>(
        '/api/exams/subjects/$examSubjectId/marks/bulk',
        data: rows,
        options: _plain,
      );
      final body = jsonDecode(AcademicJson.quoteNumbers(res.data as String))
          as Map<String, dynamic>;
      return (result: MarksSaveResult.fromJson(body), error: null);
    } on DioException catch (err) {
      return (result: null, error: _message(err));
    }
  }

  /// Saves one student's mark, and gets the recomputed result back.
  Future<({StudentResult? result, String? error})> saveMark({
    required String examSubjectId,
    required String studentId,
    Marks? marksObtained,
    bool isAbsent = false,
  }) async {
    try {
      final res = await dio.post<dynamic>(
        '/api/exams/subjects/$examSubjectId/marks',
        data: {
          'studentId': studentId,
          'isAbsent': isAbsent,
          if (!isAbsent && marksObtained != null)
            'marksObtained': marksObtained.toBackendString(),
        },
        options: _plain,
      );
      final body = jsonDecode(AcademicJson.quoteNumbers(res.data as String))
          as Map<String, dynamic>;
      return (result: StudentResult.fromJson(body), error: null);
    } on DioException catch (err) {
      return (result: null, error: _message(err));
    }
  }

  // --- Results ---------------------------------------------------------------

  /// A section's results, ordered by what needs attention (D-15).
  Future<List<StudentResult>> loadSectionResults({
    required String examId,
    required String sectionId,
  }) async {
    final rows = await _array('/api/exams/$examId/results/section/$sectionId');
    return sortResults(rows.map(StudentResult.fromJson).toList());
  }

  /// One student's result, WITH the per-subject breakdown. This is also the
  /// only way to read a mark back at all — there is no marks GET.
  Future<StudentResult> loadStudentResult({
    required String examId,
    required String studentId,
  }) async =>
      StudentResult.fromJson(
        await _object('/api/exams/$examId/results/student/$studentId'),
      );

  /// 🔴 Permanent: publishing locks the marks and there is no unpublish.
  Future<({PublishResult? result, String? error})> publish(
      String examId) async {
    try {
      final res = await dio.post<dynamic>(
        '/api/exams/$examId/publish',
        data: const <String, dynamic>{},
        options: _plain,
      );
      final body = jsonDecode(res.data as String) as Map<String, dynamic>;
      return (result: PublishResult.fromJson(body), error: null);
    } on DioException catch (err) {
      return (result: null, error: _message(err));
    }
  }

  /// 404s until the exam is published — that is the normal "not ready yet"
  /// case, not an error, so it comes back null rather than throwing.
  Future<ReportCard?> loadReportCard({
    required String examId,
    required String studentId,
  }) async {
    try {
      final res = await dio.get<dynamic>(
        '/api/exams/$examId/report-card/$studentId',
        options: _plain,
      );
      final body = jsonDecode(res.data as String) as Map<String, dynamic>;
      return ReportCard.fromJson(body);
    } on DioException catch (err) {
      if (err.response?.statusCode == 404) return null;
      throw mapDioError(decodeErrorBody(err));
    }
  }

  // --- Remarks ---------------------------------------------------------------

  Future<List<Remark>> loadSectionRemarks(String sectionId) async {
    final rows = await _array('/api/remarks/section/$sectionId');
    return rows.map(Remark.fromJson).toList();
  }

  Future<List<Remark>> loadStudentRemarks(String studentId) async {
    final rows = await _array('/api/remarks/student/$studentId');
    return rows.map(Remark.fromJson).toList();
  }

  Future<Remark> createRemark({
    required String studentId,
    required String sectionId,
    required String remarkType,
    required String body,
    required bool isParentVisible,
    String? remarkDate,
  }) async {
    final res = await _json(
      () => dio.post<dynamic>(
        '/api/remarks',
        data: {
          'studentId': studentId,
          'sectionId': sectionId,
          'remarkType': remarkType,
          'body': body,
          'isParentVisible': isParentVisible,
          'remarkDate': ?remarkDate,
        },
        options: _plain,
      ),
    );
    return Remark.fromJson((res as Map).cast<String, dynamic>());
  }

  /// Remarks are the ONE thing in this batch that can be corrected — both
  /// PUT and DELETE exist, unlike exams, papers and marks after publish.
  Future<void> deleteRemark(String id) async {
    try {
      await dio.delete<void>('/api/remarks/$id');
    } on DioException catch (err) {
      throw mapDioError(decodeErrorBody(err));
    }
  }

  // --- Syllabus --------------------------------------------------------------

  /// Chapters come back with their topics nested, so this is one call for
  /// the whole syllabus. All three parameters are REQUIRED.
  Future<List<Chapter>> loadChapters({
    required String subjectId,
    required String classId,
    required String academicYearId,
  }) async {
    final rows = await _array('/api/syllabus/chapters', {
      'subjectId': subjectId,
      'classId': classId,
      'academicYearId': academicYearId,
    });
    return rows.map(Chapter.fromJson).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  Future<Chapter> createChapter({
    required String subjectId,
    required String classId,
    required String academicYearId,
    required String name,
    required int sortOrder,
  }) async {
    final body = await _json(
      () => dio.post<dynamic>(
        '/api/syllabus/chapters',
        data: {
          'subjectId': subjectId,
          'classId': classId,
          'academicYearId': academicYearId,
          'name': name,
          'sortOrder': sortOrder,
        },
        options: _plain,
      ),
    );
    return Chapter.fromJson((body as Map).cast<String, dynamic>());
  }

  Future<Topic> createTopic({
    required String chapterId,
    required String name,
    required int sortOrder,
    int? expectedPeriodCount,
  }) async {
    final body = await _json(
      () => dio.post<dynamic>(
        '/api/syllabus/topics',
        data: {
          'chapterId': chapterId,
          'name': name,
          'sortOrder': sortOrder,
          'expectedPeriodCount': ?expectedPeriodCount,
        },
        options: _plain,
      ),
    );
    return Topic.fromJson((body as Map).cast<String, dynamic>());
  }

  /// Marks a topic covered for one section.
  ///
  /// Re-marking the same topic UPDATES rather than conflicting — verified
  /// live, the unique constraint behaves as an upsert — so a teacher can
  /// correct a mis-tap without the app doing anything special.
  Future<String?> markCoverage({
    required String topicId,
    required String sectionId,
    required CoverageStatus status,
    String? coveredOn,
    String? note,
    String? clientUuid,
  }) async {
    try {
      await dio.post<dynamic>(
        '/api/syllabus/coverage',
        data: {
          'topicId': topicId,
          'sectionId': sectionId,
          'status': status.wire,
          // REQUIRED — "clientUuid is required (offline-safe idempotency)".
          // The same idempotency key attendance marks carry: generated on
          // the device before the request is attempted, so a retry is still
          // one record rather than two.
          'clientUuid': clientUuid ?? _uuidV4(),
          'coveredOn': ?coveredOn,
          'note': ?note,
        },
        options: _plain,
      );
      return null;
    } on DioException catch (err) {
      return _message(err);
    }
  }

  /// 🔴 Server-computed. The app renders this and derives nothing.
  Future<SyllabusProgress> loadProgress({
    required String subjectId,
    required String classId,
    required String sectionId,
    required String academicYearId,
  }) async =>
      SyllabusProgress.fromJson(await _object('/api/syllabus/progress', {
        'subjectId': subjectId,
        'classId': classId,
        'sectionId': sectionId,
        'academicYearId': academicYearId,
      }));

  // --- Errors ----------------------------------------------------------------

  /// The backend's message where there is one.
  ///
  /// This surface has GOOD messages worth showing verbatim — "marksObtained
  /// 150 exceeds max 100.00", "Student is not enrolled in this section",
  /// "Exam is published — marks are locked and can no longer be changed" —
  /// each of which tells the teacher exactly what to do.
  static String _message(DioException err) {
    final body = err.response?.data;
    String? message;
    if (body is Map) {
      message = body['message'] as String?;
    } else if (body is String && body.isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) message = decoded['message'] as String?;
      } on FormatException {
        message = null;
      }
    }
    if (message != null && message.isNotEmpty) return message;
    return mapDioError(err).message ?? 'This could not be saved.';
  }
}
