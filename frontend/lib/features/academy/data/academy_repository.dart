import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_error_mapper.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../domain/academy_models.dart';

/// Every Academy (Phase B) call the app makes.
///
/// Contracts are the backend's own (`AcademyController`, `AcademyFeeController`,
/// `InstitutionProfileController`, verified 2026-10-14). Nothing here is
/// simulated: an endpoint that does not exist is not called.
///
/// All reads go through [_json], which asks dio for raw text and quotes the
/// money/marks literals before decoding — the same guarantee as
/// `FinanceRepository`: no amount or mark ever passes through a `double`.
///
/// Failures throw [LoadFailure]. The server's message is kept; Academy
/// messages start with a machine code (`ALREADY_ENROLLED: ...`), which
/// [AcademyRepository.explain] turns into staff-readable text.
class AcademyRepository {
  AcademyRepository(this.dio, {String Function()? newKey})
    : _newKey = newKey ?? const Uuid().v4;

  final Dio dio;
  final String Function() _newKey;

  /// A fresh UUID for an idempotent operation (enrollment, attendance row).
  String newKey() => _newKey();

  static final Options _plain = Options(responseType: ResponseType.plain);
  static final RegExp _exact = RegExp(
    r'"(amount|marks|max_marks|maxMarks|fee_amount|total_amount|paid_amount|outstanding|invoiced|collected)"\s*:\s*(-?\d+(?:\.\d+)?)',
  );

  static Object? decode(String text) => text.isEmpty
      ? null
      : jsonDecode(text.replaceAllMapped(_exact, (m) => '"${m[1]}":"${m[2]}"'));

  Future<Object?> _json(Future<Response<dynamic>> Function() call) async {
    try {
      final res = await call();
      final raw = res.data;
      if (raw == null) return null;
      return decode(raw is String ? raw : jsonEncode(raw));
    } on DioException catch (err) {
      final data = err.response?.data;
      if (data is String && data.isNotEmpty) {
        try {
          err.response!.data = jsonDecode(data);
        } on FormatException {
          // Not JSON (e.g. a proxy page): the mapper falls back to its own text.
        }
      }
      throw mapDioError(err);
    }
  }

  Future<Object?> _get(String path, [Map<String, dynamic>? q]) =>
      _json(() => dio.get<dynamic>(path, queryParameters: q, options: _plain));
  Future<Object?> _send(String method, String path, [Object? body]) => _json(
    () => dio.request<dynamic>(
      path,
      data: body,
      options: _plain.copyWith(method: method),
    ),
  );

  Map _map(Object? o) => o is Map ? o : const {};
  List _list(Object? o) => o is List
      ? o
      : (o is Map ? (o['content'] as List? ?? const []) : const []);

  /// Walks a Spring `Page` (size capped at 100 server-side).
  Future<List<Map>> _all(
    String path, [
    Map<String, dynamic> q = const {},
  ]) async {
    final rows = <Map>[];
    for (var page = 0; page < 50; page++) {
      final body = _map(await _get(path, {...q, 'page': page, 'size': 100}));
      final content = (body['content'] as List? ?? const []).cast<Map>();
      rows.addAll(content);
      final total = (body['totalElements'] as num?)?.toInt();
      if (content.length < 100 ||
          body['last'] == true ||
          (total != null && rows.length >= total)) {
        break;
      }
    }
    return rows;
  }

  /// `CODE: message` → readable text; unknown codes keep the server message.
  static String explain(
    Object error, [
    String fallback = 'The request could not be completed.',
  ]) {
    final message = error is LoadFailure ? error.message : null;
    if (message == null || message.isEmpty) return fallback;
    final match = RegExp(
      r'^([A-Z_]{3,}):\s*(.*)$',
      dotAll: true,
    ).firstMatch(message);
    if (match == null) return message;
    return _codes[match[1]] ?? (match[2]!.isEmpty ? message : match[2]!);
  }

  static const _codes = {
    'ACADEMY_NOT_ENABLED':
        'Academy courses and batches are not enabled for this institution.',
    'PROFILE_INCOMPATIBLE':
        'Academy courses or batches exist, so the institution cannot leave the Academy profile.',
    'ALREADY_ENROLLED':
        'This learner already has an active place in this batch.',
    'BATCH_FULL': 'The batch is full.',
    'BATCH_NOT_OPEN': 'The batch is not open for this change.',
    'WRONG_CAMPUS':
        'This learner belongs to a different campus. In this version a learner can only join batches on their own campus.',
    'STUDENT_INACTIVE': 'This learner is not active.',
    'IDEMPOTENCY_KEY_REUSED':
        'This request id was already used for a different enrollment. Start again.',
    'STAFF_NOT_ON_CAMPUS':
        'This staff member is not assigned to the batch\'s campus. Assign the campus first.',
    'ALREADY_ASSIGNED': 'This staff member already instructs this batch.',
    'BATCH_HAS_ACTIVE_ENROLLMENTS':
        'Learners are still enrolled. Confirm ending their memberships to continue.',
    'BATCH_CANCELLED': 'The batch is cancelled.',
    'OFFERING_NOT_OPEN': 'The offering is not open for new batches.',
    'OFFERING_HAS_BATCHES': 'Cancel or close this offering\'s batches first.',
    'COURSE_ARCHIVED': 'Archived courses cannot be offered.',
    'ENROLLMENT_NOT_ACTIVE': 'This membership has already ended.',
    'SCHEDULE_OVERLAP':
        'The batch already has a weekly slot overlapping this time.',
    'SESSION_HAS_ATTENDANCE':
        'Attendance exists for this session, so its date/time cannot change and it cannot be cancelled. The room can still change.',
    'SESSION_CANCELLED': 'The session is already cancelled.',
    'ASSESSMENT_PUBLISHED':
        'This assessment is published; its marks are frozen.',
    'BATCH_FEE_EXISTS':
        'This batch already has a price. Schedule a future price change instead.',
    'VERSION_EXISTS': 'A price change already takes effect in that month.',
    'RETROACTIVE_PRICE':
        'Prices cannot be changed for a past or already-invoiced month. Choose a later month.',
    'ADJUSTMENT_EXISTS':
        'An adjustment already applies to these learners from that month.',
    'ADJUSTMENT_BEFORE_VERSION':
        'The adjustment cannot start before the price takes effect.',
    'BATCH_FEE_MISSING': 'Set the batch fee before generating invoices.',
    'ACADEMY_ATTENDANCE_ONLINE_ONLY':
        'Academy attendance can only be saved while online.',
  };

  /// `SESSION_CONFLICT: BATCH_OVERLAP; INSTRUCTOR_BUSY:<id>; ROOM_BUSY:Lab 2`.
  static List<String> conflicts(Object error) {
    final message = error is LoadFailure ? error.message ?? '' : '';
    if (!message.startsWith('SESSION_CONFLICT')) return const [];
    return [
      for (final part in message.substring(message.indexOf(':') + 1).split(';'))
        if (part.trim().startsWith('BATCH_OVERLAP'))
          'The batch already has a session at this time.'
        else if (part.trim().startsWith('INSTRUCTOR_BUSY'))
          'An instructor of this batch is teaching another batch at this time.'
        else if (part.trim().startsWith('ROOM_BUSY'))
          'Room ${part.trim().substring('ROOM_BUSY'.length).replaceFirst(':', '').trim()} is booked at this time.',
    ];
  }

  // ── institution profile ──
  Future<InstitutionProfile> profile() async =>
      InstitutionProfile.fromJson(_map(await _get('/api/institution/profile')));
  Future<InstitutionProfile> changeProfile(
    String profile,
    String reason,
  ) async => InstitutionProfile.fromJson(
    _map(
      await _send('PUT', '/api/institution/profile', {
        'profile': profile,
        'reason': reason,
      }),
    ),
  );
  Future<List<ProfileChange>> profileHistory() async => [
    for (final r in _list(await _get('/api/institution/profile/history')))
      ProfileChange.fromJson(r as Map),
  ];

  // ── catalogue ──
  Future<List<Course>> courses({String? status}) async => [
    for (final r in await _all('/api/academy/courses', {'status': ?status}))
      Course.fromJson(r),
  ];
  Future<Course> createCourse({
    required String code,
    required String name,
    String? description,
    String? level,
  }) async => Course.fromJson(
    _map(
      await _send('POST', '/api/academy/courses', {
        'code': code,
        'name': name,
        'description': ?description,
        'level': ?level,
      }),
    ),
  );
  Future<Course> updateCourse(
    String id, {
    String? name,
    String? description,
    String? level,
    String? status,
  }) async => Course.fromJson(
    _map(
      await _send('PATCH', '/api/academy/courses/$id', {
        'name': ?name,
        'description': ?description,
        'level': ?level,
        'status': ?status,
      }),
    ),
  );

  // ── offerings ──
  Future<List<Offering>> offerings({
    String? campusId,
    String? courseId,
  }) async => [
    for (final r in await _all('/api/academy/offerings', {
      'campusId': ?campusId,
      'courseId': ?courseId,
    }))
      Offering.fromJson(r),
  ];
  Future<Offering> createOffering({
    required String courseId,
    required String campusId,
    required String academicYearId,
    required String name,
    required String startDate,
    required String endDate,
    required String status,
  }) async => Offering.fromJson(
    _map(
      await _send('POST', '/api/academy/offerings', {
        'courseId': courseId,
        'campusId': campusId,
        'academicYearId': academicYearId,
        'name': name,
        'startDate': startDate,
        'endDate': endDate,
        'status': status,
      }),
    ),
  );
  Future<Offering> setOfferingStatus(String id, String status) async =>
      Offering.fromJson(
        _map(
          await _send('PATCH', '/api/academy/offerings/$id/status', {
            'status': status,
          }),
        ),
      );

  // ── batches ──
  Future<List<Batch>> batches({
    String? campusId,
    String? offeringId,
    bool mine = false,
  }) async => [
    for (final r in await _all('/api/academy/batches', {
      'campusId': ?campusId,
      'offeringId': ?offeringId,
      if (mine) 'mine': true,
    }))
      Batch.fromJson(r),
  ];
  Future<BatchDetail> batch(String id) async =>
      BatchDetail.fromJson(_map(await _get('/api/academy/batches/$id')));
  Future<Batch> createBatch({
    required String offeringId,
    required String name,
    int? capacity,
    String? defaultRoom,
  }) async => Batch.fromJson(
    _map(
      await _send('POST', '/api/academy/batches', {
        'offeringId': offeringId,
        'name': name,
        'capacity': ?capacity,
        'defaultRoom': ?defaultRoom,
      }),
    ),
  );
  Future<Batch> setBatchStatus(
    String id,
    String status, {
    bool endActiveEnrollments = false,
    String? reason,
  }) async => Batch.fromJson(
    _map(
      await _send('PATCH', '/api/academy/batches/$id/status', {
        'status': status,
        'endActiveEnrollments': endActiveEnrollments,
        'reason': ?reason,
      }),
    ),
  );
  Future<void> assignInstructor(String batchId, String staffId, String role) =>
      _send('POST', '/api/academy/batches/$batchId/instructors', {
        'staffId': staffId,
        'role': role,
      });
  Future<void> revokeInstructor(String batchId, String assignmentId) => _send(
    'DELETE',
    '/api/academy/batches/$batchId/instructors/$assignmentId',
  );

  // ── enrollment ──
  /// Pass the SAME [idempotencyKey] when retrying a failed attempt: the server
  /// then returns the original membership instead of creating a second one.
  Future<({Enrollment enrollment, bool replay})> enroll(
    String batchId,
    String studentId,
    String idempotencyKey,
  ) async {
    final m = _map(
      await _send('POST', '/api/academy/batches/$batchId/enrollments', {
        'studentId': studentId,
        'idempotencyKey': idempotencyKey,
      }),
    );
    return (
      enrollment: Enrollment.fromJson(m),
      replay: m['idempotentReplay'] == true,
    );
  }

  Future<Enrollment> endEnrollment(
    String id,
    String status,
    String reason,
  ) async => Enrollment.fromJson(
    _map(
      await _send('POST', '/api/academy/enrollments/$id/end', {
        'status': status,
        'reason': reason,
      }),
    ),
  );
  Future<List<RosterEntry>> roster(String batchId) async => [
    for (final r in _list(await _get('/api/academy/batches/$batchId/roster')))
      RosterEntry.fromJson(r as Map),
  ];
  Future<List<Enrollment>> enrollmentHistory(String batchId) async => [
    for (final r in await _all('/api/academy/batches/$batchId/enrollments'))
      Enrollment.fromJson(r),
  ];
  Future<List<Enrollment>> learnerEnrollments(
    String studentId, {
    bool includeEnded = false,
  }) async => [
    for (final r in _list(
      await _get('/api/academy/students/$studentId/enrollments', {
        'includeEnded': includeEnded,
      }),
    ))
      Enrollment.fromJson(r as Map),
  ];

  // ── schedule and sessions ──
  Future<void> addSlot(
    String batchId,
    int dayOfWeek,
    String start,
    String end,
    String? room,
  ) => _send('POST', '/api/academy/batches/$batchId/schedule', {
    'dayOfWeek': dayOfWeek,
    'startTime': start,
    'endTime': end,
    'room': ?room,
  });
  Future<void> removeSlot(String batchId, String slotId) =>
      _send('DELETE', '/api/academy/batches/$batchId/schedule/$slotId');
  Future<Session> createSession(
    String batchId,
    String date,
    String start,
    String end,
    String? room,
  ) async => Session.fromJson(
    _map(
      await _send('POST', '/api/academy/batches/$batchId/sessions', {
        'sessionDate': date,
        'startTime': start,
        'endTime': end,
        'room': ?room,
      }),
    ),
  );
  Future<({int created, int existing, int skipped})> generateSessions(
    String batchId,
    String from,
    String to,
  ) async {
    final m = _map(
      await _send('POST', '/api/academy/batches/$batchId/sessions/generate', {
        'from': from,
        'to': to,
      }),
    );
    return (
      created: (m['created'] as num?)?.toInt() ?? 0,
      existing: (m['alreadyExisting'] as num?)?.toInt() ?? 0,
      skipped: (m['skipped'] as List?)?.length ?? 0,
    );
  }

  /// Teacher Today: the caller's own DATED sessions for one business day
  /// (server default: the institution's today), optionally narrowed to the
  /// active campus. Weekly templates are never expanded into sessions here.
  Future<List<MySession>> mySessions({String? date, String? campusId}) async => [
    for (final r in _list(
      _map(await _get('/api/academy/sessions/mine', {
        'date': ?date,
        'campusId': ?campusId,
      }))['sessions'],
    ))
      MySession.fromJson(r as Map),
  ];

  Future<List<Session>> sessions(
    String batchId,
    String from,
    String to,
  ) async => [
    for (final r in _list(
      await _get('/api/academy/batches/$batchId/sessions', {
        'from': from,
        'to': to,
      }),
    ))
      Session.fromJson(r as Map),
  ];
  Future<Session> updateSession(
    String id, {
    String? date,
    String? start,
    String? end,
    String? room,
    bool cancel = false,
  }) async => Session.fromJson(
    _map(
      await _send('PATCH', '/api/academy/sessions/$id', {
        'sessionDate': ?date,
        'startTime': ?start,
        'endTime': ?end,
        'room': ?room,
        if (cancel) 'cancel': true,
      }),
    ),
  );

  // ── attendance (online-only) ──
  Future<AttendanceSheet> sheet(String sessionId) async =>
      AttendanceSheet.fromJson(
        _map(await _get('/api/academy/sessions/$sessionId/attendance')),
      );

  /// Rows: studentId → (status, clientUuid). Each row commits independently
  /// on the server; a retry with the same clientUuid is reported `replayed`.
  Future<List<RowResult>> mark(
    String sessionId,
    Map<String, ({String status, String clientUuid})> rows, {
    String source = 'app',
  }) async {
    final m = _map(
      await _send('POST', '/api/academy/sessions/$sessionId/attendance', {
        'source': source,
        'rows': [
          for (final e in rows.entries)
            {
              'studentId': e.key,
              'status': e.value.status,
              'clientUuid': e.value.clientUuid,
            },
        ],
      }),
    );
    return [
      for (final r in (m['results'] as List? ?? const []))
        RowResult.fromJson(r as Map),
    ];
  }

  Future<List<LearnerAttendance>> learnerAttendance(
    String studentId,
    String from,
    String to,
  ) async => [
    for (final r in _list(
      await _get('/api/academy/students/$studentId/attendance', {
        'from': from,
        'to': to,
      }),
    ))
      LearnerAttendance.fromJson(r as Map),
  ];

  // ── assessments ──
  Future<List<Assessment>> assessments(String batchId) async => [
    for (final r in _list(
      await _get('/api/academy/batches/$batchId/assessments'),
    ))
      Assessment.fromJson(r as Map),
  ];
  Future<Assessment> createAssessment(
    String batchId,
    String title,
    String maxMarks,
    String assessedOn,
  ) async => Assessment.fromJson(
    _map(
      await _send('POST', '/api/academy/batches/$batchId/assessments', {
        'title': title,
        'maxMarks': maxMarks,
        'assessedOn': assessedOn,
      }),
    ),
  );
  Future<({Assessment assessment, List<MarkEntry> marks})> marks(
    String assessmentId,
  ) async {
    final m = _map(await _get('/api/academy/assessments/$assessmentId/marks'));
    return (
      assessment: Assessment.fromJson(m),
      marks: [
        for (final r in (m['marks'] as List? ?? const []))
          MarkEntry.fromJson(r as Map),
      ],
    );
  }

  Future<void> saveMarks(
    String assessmentId,
    List<({String studentId, String? marks, bool absent, String? remarks})>
    rows,
  ) => _send('POST', '/api/academy/assessments/$assessmentId/marks', [
    for (final r in rows)
      {
        'studentId': r.studentId,
        'marks': r.marks,
        'absent': r.absent,
        'remarks': r.remarks,
      },
  ]);
  Future<void> publish(String assessmentId) =>
      _send('POST', '/api/academy/assessments/$assessmentId/publish');
  Future<List<LearnerResult>> learnerResults(String studentId) async => [
    for (final r in _list(
      await _get('/api/academy/students/$studentId/results'),
    ))
      LearnerResult.fromJson(r as Map),
  ];

  // ── fees ──
  /// Null when no fee is set yet (the server answers 404 for that).
  Future<BatchFee?> batchFee(String batchId) async {
    try {
      return BatchFee.fromJson(
        _map(await _get('/api/academy/batches/$batchId/fee')),
      );
    } on LoadFailure catch (f) {
      if (f.message != null && f.message!.contains('BatchFee')) return null;
      rethrow;
    }
  }

  Future<BatchFee> setBatchFee(
    String batchId, {
    required String feeHeadId,
    required String amount,
    required String frequency,
    required int dueDay,
  }) async => BatchFee.fromJson(
    _map(
      await _send('PUT', '/api/academy/batches/$batchId/fee', {
        'feeHeadId': feeHeadId,
        'amount': amount,
        'frequency': frequency,
        'dueDay': dueDay,
      }),
    ),
  );

  /// Schedules a future price (V50). The server refuses backdated months
  /// (`RETROACTIVE_PRICE`) and duplicates (`VERSION_EXISTS`); step-up required.
  Future<BatchFee> scheduleFeeVersion(
    String batchId, {
    required String amount,
    required String effectiveFrom,
    required String reason,
  }) async => BatchFee.fromJson(
    _map(
      await _send('POST', '/api/academy/batches/$batchId/fee/versions', {
        'amount': amount,
        'effectiveFrom': effectiveFrom,
        'reason': reason,
      }),
    ),
  );

  /// Explicit, audited move of existing learners (all active when [enrollmentIds]
  /// is null) to [versionId] from [appliesFrom]; step-up required.
  Future<int> adjustExistingLearners(
    String batchId, {
    required String versionId,
    required String appliesFrom,
    required String reason,
    List<String>? enrollmentIds,
  }) async {
    final m = _map(
      await _send('POST', '/api/academy/batches/$batchId/fee/adjustments', {
        'versionId': versionId,
        'appliesFrom': appliesFrom,
        'reason': reason,
        'enrollmentIds': ?enrollmentIds,
      }),
    );
    return (m['adjusted'] as num?)?.toInt() ?? 0;
  }

  Future<GenerateResult> generateInvoices(
    String batchId,
    String period,
  ) async => GenerateResult.fromJson(
    _map(
      await _send('POST', '/api/academy/batches/$batchId/fee/invoices', {
        'period': period,
      }),
    ),
  );

  // ── finance read views (fee.manage on the campus; read-only) ──
  Future<List<FinanceBatch>> financeBatches({String? campusId}) async => [
    for (final r in await _all('/api/academy/finance/batches', {
      'campusId': ?campusId,
    }))
      FinanceBatch.fromJson(r),
  ];
  Future<({List<BatchInvoice> invoices, MoneyTotals totals})> batchInvoices(
    String batchId, {
    String? period,
  }) async {
    final m = _map(
      await _get('/api/academy/finance/batches/$batchId/invoices', {
        'period': ?period,
      }),
    );
    return (
      invoices: [
        for (final r in (m['invoices'] as List? ?? const []))
          BatchInvoice.fromJson(r as Map),
      ],
      totals: MoneyTotals.fromJson(_map(m['totals'])),
    );
  }

  Future<({List<CollectionRow> rows, MoneyTotals totals})> collection({
    String? campusId,
    String? period,
  }) async {
    final m = _map(
      await _get('/api/academy/finance/reports/collection', {
        'campusId': ?campusId,
        'period': ?period,
      }),
    );
    return (
      rows: [
        for (final r in (m['rows'] as List? ?? const []))
          CollectionRow.fromJson(r as Map),
      ],
      totals: MoneyTotals.fromJson(_map(m['totals'])),
    );
  }

  // ── pickers (existing school endpoints, always with an explicit campus) ──
  Future<List<Pick>> students(String campusId) async => [
    for (final r in await _all('/api/students', {
      'campusId': campusId,
      'status': 'active',
    }))
      Pick(
        '${r['id']}',
        '${r['firstName'] ?? ''} ${r['lastName'] ?? ''}'.trim(),
        r['admissionNumber']?.toString(),
      ),
  ];
  Future<List<Pick>> staff(String campusId) async => [
    for (final r in await _all('/api/staff', {'campusId': campusId}))
      Pick(
        '${r['id']}',
        '${r['firstName'] ?? ''} ${r['lastName'] ?? ''}'.trim(),
        r['employeeCode']?.toString(),
      ),
  ];
  Future<List<Pick>> academicYears(String campusId) async => [
    for (final r in await _all('/api/academic-years', {'campusId': campusId}))
      Pick('${r['id']}', '${r['name'] ?? ''}'),
  ];
  Future<List<Pick>> feeHeads() async => [
    for (final r in _list(await _get('/api/fee/heads')))
      Pick('${(r as Map)['id']}', '${r['name']}'),
  ];

  /// The signed-in learner's own student id, or a guardian's linked children.
  Future<List<Pick>> myLearners({required bool student}) async {
    if (student) {
      final m = _map(await _get('/api/students/me'));
      return [
        Pick(
          '${m['id']}',
          '${m['firstName'] ?? ''} ${m['lastName'] ?? ''}'.trim(),
        ),
      ];
    }
    final m = _map(await _get('/api/guardians/me'));
    return [
      for (final c in (m['students'] as List? ?? const []))
        Pick(
          '${(c as Map)['studentId']}',
          '${c['firstName'] ?? ''} ${c['lastName'] ?? ''}'.trim(),
        ),
    ];
  }
}
