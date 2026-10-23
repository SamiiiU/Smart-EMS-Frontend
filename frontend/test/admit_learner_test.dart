import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/shell/campus_context.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/app_button.dart';
import 'package:smartems/features/admin/data/admission_repository.dart';
import 'package:smartems/features/admin/presentation/admit_learner_screen.dart';
import 'package:smartems/features/setup/data/setup_repository.dart';

/// Overhaul M4: guided learner admission.
class _Server implements HttpClientAdapter {
  _Server({this.studentStatus = 201, this.enrollFailures = 0});
  final int studentStatus;
  int enrollFailures;
  final posts = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<List<int>>? s,
    Future<void>? c,
  ) async {
    if (o.method == 'POST') posts.add(o);
    if (o.method == 'GET' && o.path.contains('academic-years')) {
      return _json(200, {
        'content': [
          {
            'id': 'y-old',
            'name': '2025-26',
            'campusId': 'ca',
            'startDate': '',
            'endDate': '',
            'current': false,
          },
          {
            'id': 'y1',
            'name': '2026-27',
            'campusId': 'ca',
            'startDate': '',
            'endDate': '',
            'current': true,
          },
          {
            'id': 'y-b',
            'name': 'B year',
            'campusId': 'cb',
            'startDate': '',
            'endDate': '',
            'current': true,
          },
        ],
      });
    }
    if (o.method == 'GET' && o.path.contains('sections')) {
      return _json(200, {
        'content': [
          {'id': 's1', 'classId': 'k6', 'academicYearId': 'y1', 'name': 'A'},
          {'id': 's-b', 'classId': 'k6', 'academicYearId': 'y-b', 'name': 'B'},
        ],
      });
    }
    if (o.method == 'GET' && o.path.contains('classes')) {
      return _json(200, {
        'content': [
          {'id': 'k6', 'name': 'Grade 6', 'campusId': 'ca'},
        ],
      });
    }
    if (o.path == '/api/students') {
      return studentStatus == 201
          ? _json(201, {'id': 'stu-1'})
          : _json(studentStatus, {'message': 'duplicate'});
    }
    if (o.path == '/api/enrollments') {
      if (enrollFailures > 0) {
        enrollFailures--;
        return _json(500, {
          'message': 'Something went wrong. Please try again.',
        });
      }
      return _json(201, {'id': 'enr-1'});
    }
    if (o.path == '/api/guardians') return _json(201, {'id': 'g-1'});
    return _json(404, {});
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

const _campus = [
  CampusOption(id: 'ca', name: 'Campus A', permissions: {'student.manage'}),
];

Widget _host(_Server server, {ValueChanged<String>? onAdmitted}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
    ..httpClientAdapter = server;
  return MaterialApp(
    theme: AppTheme.light(role: AppRole.admin),
    home: AdmitLearnerScreen(
      admissions: AdmissionRepository(dio),
      setup: SetupRepository(dio),
      campuses: _campus,
      onAdmitted: onAdmitted,
    ),
  );
}

Future<void> _type(WidgetTester tester, String key, String value) async {
  await tester.enterText(
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField)),
    value,
  );
  await tester.pump();
}

Future<void> _next(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('admit-next')));
  await tester.tap(find.byKey(const Key('admit-next')));
  await tester.pumpAndSettle();
}

Future<void> _fillToReview(WidgetTester tester, {bool guardian = true}) async {
  await _type(tester, 'admit-first', 'Ayesha');
  await _type(tester, 'admit-last', 'Khan');
  await _type(tester, 'admit-number', 'ADM-77');
  await _next(tester);
  // Single campus pre-selected; the CURRENT year of that campus pre-selected.
  expect(find.text('2026-27 (current)'), findsOneWidget);
  await tester.tap(find.byKey(const Key('admit-section')));
  await tester.pumpAndSettle();
  expect(
    find.text('Grade 6 · B'),
    findsNothing,
    reason: 'other campus/year sections never offered',
  );
  await tester.tap(find.text('Grade 6 · A').last);
  await tester.pumpAndSettle();
  await _next(tester);
  if (guardian) {
    await _type(tester, 'admit-g-first', 'Imran');
    await _type(tester, 'admit-g-last', 'Khan');
  } else {
    await tester.tap(find.byKey(const Key('admit-guardian-toggle')));
    await tester.pumpAndSettle();
  }
  await _next(tester);
}

void main() {
  testWidgets('Next stays disabled until required learner fields are filled', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_Server()));
    await tester.pumpAndSettle();
    final next = find.byKey(const Key('admit-next'));
    expect(tester.widget<AppButton>(next).onPressed, isNull);
    await _type(tester, 'admit-first', 'Ayesha');
    await _type(tester, 'admit-last', 'Khan');
    expect(
      tester.widget<AppButton>(next).onPressed,
      isNull,
      reason: 'admission number still missing',
    );
    await _type(tester, 'admit-number', 'ADM-77');
    expect(tester.widget<AppButton>(next).onPressed, isNotNull);
  });

  testWidgets('admits, enrols and adds the guardian in order, after a review', (
    tester,
  ) async {
    final server = _Server();
    String? admitted;
    await tester.pumpWidget(_host(server, onAdmitted: (id) => admitted = id));
    await tester.pumpAndSettle();
    await _fillToReview(tester);
    expect(find.text('Ayesha Khan'), findsOneWidget);
    expect(find.text('Grade 6 · A'), findsOneWidget);
    expect(
      server.posts,
      isEmpty,
      reason: 'nothing is written before confirming',
    );
    await _next(tester);
    expect(server.posts.map((p) => p.path).toList(), [
      '/api/students',
      '/api/enrollments',
      '/api/guardians',
    ]);
    expect(server.posts[0].data, {
      'campusId': 'ca',
      'admissionNumber': 'ADM-77',
      'firstName': 'Ayesha',
      'lastName': 'Khan',
    });
    expect(server.posts[1].data, {
      'studentId': 'stu-1',
      'sectionId': 's1',
      'academicYearId': 'y1',
    });
    expect((server.posts[2].data as Map)['relationship'], 'father');
    expect(admitted, 'stu-1');
    expect(
      find.textContaining('is admitted and placed in Grade 6 · A'),
      findsOneWidget,
    );
  });

  testWidgets(
    'a duplicate admission number returns to the learner step with a clear message',
    (tester) async {
      final server = _Server(studentStatus: 409);
      await tester.pumpWidget(_host(server));
      await tester.pumpAndSettle();
      await _fillToReview(tester);
      await _next(tester);
      expect(find.textContaining('ADM-77 is already in use'), findsOneWidget);
      expect(find.text('Step 1 of 4 · Learner'), findsOneWidget);
      expect(
        server.posts.map((p) => p.path),
        ['/api/students'],
        reason: 'no enrolment for a learner that was not created',
      );
    },
  );

  testWidgets(
    'a failure after the learner exists resumes without creating a second learner',
    (tester) async {
      final server = _Server(enrollFailures: 1);
      await tester.pumpWidget(_host(server));
      await tester.pumpAndSettle();
      await _fillToReview(tester);
      await _next(tester);
      expect(
        find.textContaining('The learner record is saved'),
        findsOneWidget,
      );
      expect(find.widgetWithText(AppButton, 'Retry'), findsOneWidget);
      await _next(tester);
      final paths = server.posts.map((p) => p.path).toList();
      expect(paths.where((p) => p == '/api/students').length, 1);
      expect(paths.where((p) => p == '/api/enrollments').length, 2);
      expect(find.textContaining('is admitted'), findsOneWidget);
    },
  );

  testWidgets('an adult learner can be admitted without a guardian', (
    tester,
  ) async {
    final server = _Server();
    await tester.pumpWidget(_host(server));
    await tester.pumpAndSettle();
    await _fillToReview(tester, guardian: false);
    expect(find.text('None'), findsOneWidget);
    await _next(tester);
    expect(server.posts.map((p) => p.path), [
      '/api/students',
      '/api/enrollments',
    ]);
  });
}
