import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/api_config.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/features/academy/data/academy_repository.dart';
import 'package:smartems/features/parent/data/parent_repository.dart';
import 'package:smartems/features/parent/presentation/parent_home_screen.dart';

/// Report 11 A-1: an Academy parent's home showed "Student not found" because
/// the School snapshot 404s for a learner with no class enrollment. The server
/// now explains that 404 (details.code NO_SCHOOL_ENROLLMENT) only to readers
/// authorised for the child; the home then shows the child's Academy day.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.responder);
  final ResponseBody Function(RequestOptions o) responder;
  final List<RequestOptions> requests = [];
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<List<int>>? s,
    Future<void>? c,
  ) async {
    requests.add(o);
    return responder(o);
  }

  @override
  void close({bool force = false}) {}
}

/// Holds School-snapshot answers until [gate] completes (a slow network).
class _GatedAdapter implements HttpClientAdapter {
  _GatedAdapter(this.inner, this.gate);
  final _Adapter inner;
  final Completer<void> gate;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<List<int>>? s,
    Future<void>? c,
  ) async {
    if (o.path.startsWith(ApiConfig.parentProgressPath)) await gate.future;
    return inner.fetch(o, s, c);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromBytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, dynamic> _child(String id, String first) => {
  'studentId': id,
  'firstName': first,
  'lastName': 'Live',
  'admissionNumber': 'A-$id',
  'className': null,
  'sectionName': null,
  'sectionId': null,
  'academicYearId': null,
  'photoUrl': null,
  'relationship': 'mother',
};

Map<String, dynamic> _progress(String id) => {
  'studentId': id,
  'studentName': 'School Child',
  'className': 'Class 9',
  'sectionName': 'C',
  'date': '2026-10-15',
  'attendanceStatus': 'present',
  'diaryEntries': <Object>[],
  'remarks': <Object>[],
  'attendanceStats': null,
  'latestResult': null,
  'syllabusProgress': {'subjects': <Object>[]},
  'pendingAssignments': <Object>[],
};

final _noSchool = {
  'status': 404,
  'error': 'Not Found',
  'message': 'This learner has no class enrollment',
  'details': {'code': 'NO_SCHOOL_ENROLLMENT'},
};
final _plain404 = {
  'status': 404,
  'error': 'Not Found',
  'message': 'Student not found: x',
};

/// [academyOnly] children answer NO_SCHOOL_ENROLLMENT; [forbidden] answer a
/// plain 404 everywhere (not this parent's child); [academyDown] makes the
/// Academy endpoints fail with a plain 404.
_Adapter _adapter({
  required List<Map<String, dynamic>> children,
  Set<String> academyOnly = const {},
  Set<String> forbidden = const {},
  Set<String> academyDown = const {},
  Map<String, List<Map<String, dynamic>>> batches = const {},
}) {
  return _Adapter((o) {
    final p = o.path;
    if (p == ApiConfig.guardiansMePath) {
      return _json(200, {
        'guardianId': 'g',
        'firstName': 'Par',
        'lastName': 'Ent',
        'students': children,
      });
    }
    String? idIn(String prefix) => p.startsWith(prefix)
        ? p.substring(prefix.length).split('/').first
        : null;
    final progressId = idIn('${ApiConfig.parentProgressPath}/');
    if (progressId != null) {
      if (forbidden.contains(progressId)) return _json(404, _plain404);
      if (academyOnly.contains(progressId)) return _json(404, _noSchool);
      return _json(200, _progress(progressId));
    }
    final id = idIn('/api/academy/students/');
    if (id != null) {
      if (forbidden.contains(id) || academyDown.contains(id)) {
        return _json(404, _plain404);
      }
      if (p.endsWith('/enrollments')) {
        return _json(200, batches[id] ?? const []);
      }
      if (p.endsWith('/attendance')) {
        return _json(200, [
          if ((batches[id] ?? const []).isNotEmpty)
            {
              'course_name': 'Mathematics',
              'batch_name': 'Mathematics A',
              'session_date': '2026-10-15',
              'start_time': '16:00:00',
              'status': 'late',
            },
        ]);
      }
      if (p.endsWith('/results')) {
        return _json(200, [
          {
            'course_name': 'Mathematics',
            'batch_name': 'Mathematics A',
            'title': 'Unit 1',
            'max_marks': '25.00',
            'marks': '21.50',
            'absent': false,
            'status': 'published',
            'assessed_on': '2026-10-10',
          },
          // Defence in depth: even if a draft ever arrived, it is not shown.
          {
            'course_name': 'Mathematics',
            'batch_name': 'Mathematics A',
            'title': 'Unit 2 draft',
            'max_marks': '20.00',
            'marks': '15.50',
            'absent': false,
            'status': 'draft',
            'assessed_on': '2026-10-15',
          },
        ]);
      }
    }
    return _json(500, {'status': 500});
  });
}

Map<String, dynamic> _enrollment(String student, String course) => {
  'id': 'e-$student-$course',
  'batch_id': 'b-$course',
  'batch_name': '$course A',
  'course_name': course,
  'student_id': student,
  'status': 'active',
  'enrolled_on': '2026-10-01',
};

Future<_Adapter> _pump(
  WidgetTester tester,
  _Adapter a, {
  bool academy = true,
}) async {
  final dio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))
    ..httpClientAdapter = a;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(role: AppRole.parent),
      home: ParentHomeScreen(
        repository: ParentRepository(dio),
        academy: academy ? AcademyRepository(dio) : null,
        now: () => DateTime(2026, 10, 15, 12),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return a;
}

bool _calledAcademy(_Adapter a) =>
    a.requests.any((r) => r.path.startsWith('/api/academy/'));

void main() {
  testWidgets(
    'Academy-only child: batches, today and published results instead of "Student not found"',
    (tester) async {
      await _pump(
        tester,
        _adapter(
          children: [_child('a1', 'Ayesha')],
          academyOnly: {'a1'},
          batches: {
            'a1': [
              _enrollment('a1', 'Mathematics'),
              _enrollment('a1', 'Physics'),
            ],
          },
        ),
      );
      expect(find.textContaining('not found'), findsNothing);
      expect(find.text('Could not load this'), findsNothing);
      expect(
        find.text('Mathematics · Mathematics A'),
        findsOneWidget,
        reason: 'multi-batch',
      );
      expect(find.text('Physics · Physics A'), findsOneWidget);
      expect(
        find.text('Mathematics · 16:00'),
        findsOneWidget,
        reason: "today's session attendance",
      );
      expect(
        find.text('Mathematics · Unit 1: 21.50 of 25.00'),
        findsOneWidget,
        reason: 'exact decimal',
      );
      expect(
        find.textContaining('Unit 2 draft'),
        findsNothing,
        reason: 'never an unpublished assessment',
      );
      // No School attendance history link for a child with no class.
      expect(find.text('Attendance history'), findsNothing);
    },
  );

  testWidgets(
    'several children: School child keeps the School card; Academy-only child gets the Academy day',
    (tester) async {
      final a = await _pump(
        tester,
        _adapter(
          children: [_child('s1', 'Sana'), _child('a1', 'Ayesha')],
          academyOnly: {'a1'},
          batches: {
            'a1': [_enrollment('a1', 'Mathematics')],
          },
        ),
      );
      // Overview: both cards. The School child's status pill is present; its
      // Academy section is hidden because it has no batches.
      expect(find.text('Present'), findsOneWidget);
      expect(find.text('Mathematics · Mathematics A'), findsOneWidget);
      expect(
        find.text('Courses'),
        findsOneWidget,
        reason: 'only the Academy child has a Courses section',
      );
      // Each child's Academy data is requested for that child only.
      final academyIds = a.requests
          .where((r) => r.path.startsWith('/api/academy/students/'))
          .map((r) => r.path.split('/')[4])
          .toSet();
      expect(academyIds, {'s1', 'a1'});
    },
  );

  testWidgets(
    'authorisation failure stays an error: a plain 404 is never shown as "no class"',
    (tester) async {
      await _pump(
        tester,
        _adapter(children: [_child('x1', 'Xena')], forbidden: {'x1'}),
      );
      expect(find.text('Not enrolled in a class yet.'), findsNothing);
      expect(
        find.textContaining('Not enrolled in a class or course batch'),
        findsNothing,
      );
      expect(
        find.byKey(const Key('academy-summary-x1')),
        findsNothing,
        reason: 'nothing rendered as data',
      );
      expect(find.textContaining('Retry'), findsWidgets);
    },
  );

  testWidgets(
    'Academy endpoints failing show a retryable error, not "not enrolled"',
    (tester) async {
      final down = {'a1'};
      await _pump(
        tester,
        _adapter(
          children: [_child('a1', 'Ayesha')],
          academyOnly: {'a1'},
          academyDown: down,
          batches: {
            'a1': [_enrollment('a1', 'Mathematics')],
          },
        ),
      );
      expect(find.text('Could not load course details.'), findsOneWidget);
      expect(find.textContaining('Not enrolled'), findsNothing);
      // Retry recovers once the server answers.
      down.clear();
      await tester.tap(find.bySemanticsLabel('Retry course details'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load course details.'), findsNothing);
      expect(find.text('Mathematics · Mathematics A'), findsOneWidget);
    },
  );

  testWidgets(
    'School institution (no Academy): School home unchanged and no Academy calls',
    (tester) async {
      final a = await _pump(
        tester,
        _adapter(children: [_child('s1', 'Sana')]),
        academy: false,
      );
      expect(find.text('Present'), findsOneWidget);
      expect(find.text('Attendance history'), findsOneWidget);
      expect(_calledAcademy(a), isFalse);
    },
  );

  testWidgets(
    'School institution, child without a class: a plain fact, not an error, no Academy calls',
    (tester) async {
      final a = await _pump(
        tester,
        _adapter(children: [_child('a1', 'Ayesha')], academyOnly: {'a1'}),
        academy: false,
      );
      expect(find.text('Not enrolled in a class yet.'), findsOneWidget);
      expect(find.textContaining('Retry'), findsNothing);
      expect(_calledAcademy(a), isFalse);
    },
  );

  testWidgets(
    'Academy institution: the School history link never shows before a School record is confirmed',
    (tester) async {
      // Loading: the School snapshot has not answered yet.
      final gate = Completer<void>();
      final inner = _adapter(
        children: [_child('a1', 'Ayesha')],
        academyOnly: {'a1'},
        batches: {
          'a1': [_enrollment('a1', 'Mathematics')],
        },
      );
      final dio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))
        ..httpClientAdapter = _GatedAdapter(inner, gate);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(role: AppRole.parent),
          home: ParentHomeScreen(
            repository: ParentRepository(dio),
            academy: AcademyRepository(dio),
            now: () => DateTime(2026, 10, 15, 12),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Attendance history'), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      // Answered "no class enrollment": still no School history link.
      expect(find.text('Attendance history'), findsNothing);
      expect(find.text('Mathematics · Mathematics A'), findsOneWidget);
    },
  );

  testWidgets(
    'Academy institution, School snapshot failed: no history link; School institution keeps it',
    (tester) async {
      await _pump(
        tester,
        _adapter(children: [_child('a1', 'Ayesha')], forbidden: {'a1'}),
      );
      expect(find.text('Attendance history'), findsNothing);
      expect(find.textContaining('Retry'), findsWidgets);

      await _pump(
        tester,
        _adapter(children: [_child('a2', 'Bilal')], forbidden: {'a2'}),
        academy: false,
      );
      expect(find.text('Attendance history'), findsOneWidget);
    },
  );

  testWidgets(
    'overview: one assistive-tech action per child ("View <name> only"); the card tap is touch-only',
    (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        _adapter(
          children: [_child('a1', 'Ayesha'), _child('b1', 'Bilal')],
          academyOnly: {'a1'},
          batches: {
            'a1': [_enrollment('a1', 'Mathematics')],
          },
        ),
      );
      for (final id in ['a1', 'b1']) {
        final card = tester.widget<GestureDetector>(
          find.byKey(Key('overview-$id')),
        );
        expect(card.excludeFromSemantics, isTrue);
      }
      expect(find.bySemanticsLabel('View Ayesha Live only'), findsOneWidget);
      expect(find.bySemanticsLabel('View Bilal Live only'), findsOneWidget);
      // Touch still opens the child.
      await tester.tap(find.byKey(const Key('overview-b1')));
      await tester.pumpAndSettle();
      expect(find.text('Attendance history'), findsOneWidget);
      handle.dispose();
    },
  );

  test('only the coded 404 means "no class enrollment"', () {
    DioException err(int status, Object data) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      response: Response(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: status,
        data: data,
      ),
    );
    expect(ParentRepository.isNoSchoolEnrollment(err(404, _noSchool)), isTrue);
    expect(ParentRepository.isNoSchoolEnrollment(err(404, _plain404)), isFalse);
    expect(ParentRepository.isNoSchoolEnrollment(err(403, _noSchool)), isFalse);
    expect(
      ParentRepository.isNoSchoolEnrollment(err(404, 'plain text')),
      isFalse,
    );
  });
}
