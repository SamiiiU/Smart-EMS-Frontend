import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/api_config.dart';
import 'package:smartems/core/network/api_error_mapper.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/states/error_state.dart';
import 'package:smartems/core/widgets/states/screen_state.dart';
import 'package:smartems/core/widgets/status_pill.dart';
import 'package:smartems/features/attendance/domain/attendance_models.dart';
import 'package:smartems/features/parent/data/parent_repository.dart';
import 'package:smartems/features/parent/domain/parent_models.dart';
import 'package:smartems/features/parent/presentation/child_attendance_screen.dart';
import 'package:smartems/features/parent/presentation/child_progress_details.dart';
import 'package:smartems/features/parent/presentation/parent_home_screen.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.responder);

  final ResponseBody Function(RequestOptions o) responder;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    requests.add(o);
    return responder(o);
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

DioException _notFound(RequestOptions o, String message) => DioException(
      requestOptions: o,
      response: Response(
        requestOptions: o,
        statusCode: 404,
        data: {'status': 404, 'message': message, 'path': o.path},
      ),
    );

/// A verbatim `/api/guardians/me` payload, captured live 2026-08-11.
Map<String, dynamic> _guardianJson({int childCount = 1}) => {
      'guardianId': '019fef33-3729-78f1-aea1-cbb058b8ef11',
      'firstName': 'Imran',
      'lastName': 'Ahmed',
      'students': [
        {
          'studentId': 'st-1',
          'firstName': 'Bilal',
          'lastName': 'Ahmed',
          'admissionNumber': 'ADM-100',
          'className': 'Class 9',
          'sectionName': 'Class 9-C',
          'sectionId': 'sec-1',
          'academicYearId': 'ay-1',
          'photoUrl': null,
          'relationship': 'father',
        },
        if (childCount > 1)
          {
            'studentId': 'st-2',
            'firstName': 'Fatima',
            'lastName': 'Noor',
            'admissionNumber': 'ADM-101',
            'className': 'Class 7',
            'sectionName': 'Class 7-A',
            'sectionId': 'sec-2',
            'academicYearId': 'ay-1',
            'photoUrl': null,
            'relationship': 'father',
          },
      ],
    };

/// A verbatim `/api/parent-progress/student/{id}` payload.
Map<String, dynamic> _progressJson({String? status, String name = 'Bilal Ahmed'}) => {
      'studentId': 'st-1',
      'studentName': name,
      'className': 'Class 9',
      'sectionName': 'C',
      'date': '2026-08-11',
      'attendanceStatus': status,
      'diaryEntries': <Object>[],
      'remarks': <Object>[],
      'attendanceStats': null,
      'latestResult': null,
      'syllabusProgress': {'subjects': <Object>[]},
      'pendingAssignments': <Object>[],
    };

/// A verbatim `/api/attendance/student/{id}` payload — note snake_case.
Map<String, dynamic> _attendanceJson(List<List<String>> daysAndStatus) => {
      'page': 0,
      'size': 31,
      'totalElements': daysAndStatus.length,
      'content': [
        for (final d in daysAndStatus)
          {
            'attendance_date': d[0],
            'status': d[1],
            'section_id': 'sec-1',
            'subject_id': null,
            'updated_at': '2026-08-11T05:02:21.234+00:00',
          },
      ],
    };

_Adapter _happyAdapter({int childCount = 1, String? todayStatus = 'present'}) {
  return _Adapter((o) {
    if (o.path == ApiConfig.guardiansMePath) {
      return _json(200, _guardianJson(childCount: childCount));
    }
    if (o.path.contains(ApiConfig.parentProgressPath)) {
      return _json(200, _progressJson(status: todayStatus));
    }
    return _json(200, _attendanceJson([
      ['2026-08-11', 'present'],
      ['2026-08-10', 'late'],
      ['2026-08-09', 'absent'],
    ]));
  });
}

ParentRepository _repo(_Adapter a) => ParentRepository(
      Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))..httpClientAdapter = a,
    );

Widget host(Widget child, {double textScale = 1.0}) => MaterialApp(
      theme: AppTheme.light(role: AppRole.parent),
      builder: (context, mqChild) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: mqChild!,
      ),
      home: child,
    );

void main() {
  group('Parsing the live payloads', () {
    test('guardians/me: students is an ARRAY and carries sectionId', () {
      final profile = GuardianProfile.fromJson(_guardianJson());

      expect(profile.fullName, 'Imran Ahmed');
      expect(profile.children, hasLength(1));
      expect(profile.children.single.studentId, 'st-1');
      expect(profile.children.single.fullName, 'Bilal Ahmed');
      expect(
        profile.children.single.sectionId,
        'sec-1',
        reason: 'carried directly, so reaching attendance needs no extra call',
      );
      expect(profile.hasMultipleChildren, isFalse);
    });

    test('a guardian with no children parses to an empty list, not a crash',
        () {
      final profile = GuardianProfile.fromJson(const {
        'guardianId': 'g-1',
        'firstName': 'A',
        'lastName': 'B',
        'students': <Object>[],
      });
      expect(profile.children, isEmpty);
    });

    test('classLabel prefers guardians/me\'s complete "Class 9-C" form', () {
      // parent-progress returns the bare section ("C") for the same field;
      // the complete label is the useful one.
      expect(GuardianProfile.fromJson(_guardianJson()).children.single.classLabel,
          'Class 9-C');
    });

    test('parent-progress: a NULL attendanceStatus means NOT MARKED, not '
        'absent', () {
      // Conflating the two would tell a parent their child missed school
      // because a teacher is running late.
      final unmarked = ChildToday.fromJson(_progressJson(status: null));
      expect(unmarked.status, isNull);
      expect(unmarked.isMarked, isFalse);

      final marked = ChildToday.fromJson(_progressJson(status: 'present'));
      expect(marked.status, AttendanceStatus.present);
      expect(marked.isMarked, isTrue);
    });

    test('attendance rows parse from SNAKE_CASE keys', () {
      final day = AttendanceDay.fromJson(const {
        'attendance_date': '2026-08-11',
        'status': 'late',
      });
      expect(day.date, '2026-08-11');
      expect(day.status, AttendanceStatus.late);

      // The camelCase spelling must NOT populate the date — proof the parser
      // matches the endpoint that actually exists. It yields an empty date
      // rather than throwing, since only `status` is structurally required;
      // asserting emptiness is the honest check.
      final wrongCase = AttendanceDay.fromJson(const {
        'attendanceDate': '2026-08-11',
        'status': 'late',
      });
      expect(wrongCase.date, isEmpty);
    });
  });

  group('Repository', () {
    test('attendance sends the REQUIRED from param and sorts newest first',
        () async {
      final adapter = _happyAdapter();
      final days = await _repo(adapter).loadAttendance(
        studentId: 'st-1',
        from: DateTime(2026, 7, 12),
        to: DateTime(2026, 8, 11),
      );

      final req = adapter.requests.single;
      expect(req.queryParameters['from'], '2026-07-12');
      expect(req.queryParameters['to'], '2026-08-11');
      expect(days.first.date, '2026-08-11');
      expect(days.last.date, '2026-08-09');
    });

    test('a 404 from guardians/me maps to notLinked — the D-17 orphan case',
        () {
      // The path is registered in ApiConfig.personRecordPaths, which is what
      // makes this classification work for parents at all.
      final options = RequestOptions(path: ApiConfig.guardiansMePath);
      final failure = mapDioError(_notFound(
        options,
        'Guardian record linked to this login not found: u-1',
      ));

      expect(failure.kind, LoadFailureKind.notLinked);
      expect(failure.isNotLinked, isTrue);
    });
  });

  group('Parent landing', () {
    testWidgets('shows the child and today\'s status', (tester) async {
      await tester.pumpWidget(host(
        ParentHomeScreen(repository: _repo(_happyAdapter())),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Bilal Ahmed'), findsOneWidget);
      expect(find.text('Class 9-C'), findsOneWidget);
      expect(find.byType(StatusPill), findsOneWidget);
    });

    testWidgets('NOT MARKED says so plainly instead of showing a pill',
        (tester) async {
      await tester.pumpWidget(host(
        ParentHomeScreen(repository: _repo(_happyAdapter(todayStatus: null))),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('has not been taken yet'), findsOneWidget);
      expect(
        find.byType(StatusPill),
        findsNothing,
        reason: 'an unmarked register must never render as a status',
      );
    });

    testWidgets('ONE child: no switcher — a single-option picker is noise',
        (tester) async {
      await tester.pumpWidget(host(
        ParentHomeScreen(repository: _repo(_happyAdapter())),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Fatima Noor'), findsNothing);
      // Paired positive: the child IS named, just not as a chooser.
      expect(find.text('Bilal Ahmed'), findsOneWidget);
    });

    testWidgets('TWO children: a switcher appears and switching reloads the '
        'day', (tester) async {
      final adapter = _happyAdapter(childCount: 2);
      await tester.pumpWidget(host(
        ParentHomeScreen(repository: _repo(adapter)),
      ));
      await tester.pumpAndSettle();

      // Both offered.
      expect(find.text('Fatima Noor'), findsOneWidget);
      expect(find.text('Bilal Ahmed'), findsWidgets);

      final before = adapter.requests
          .where((r) => r.path.contains(ApiConfig.parentProgressPath))
          .length;

      await tester.tap(find.text('Fatima Noor'));
      await tester.pumpAndSettle();

      final after = adapter.requests
          .where((r) => r.path.contains(ApiConfig.parentProgressPath))
          .length;
      expect(
        after,
        greaterThan(before),
        reason: 'switching child must re-ask for THAT child\'s day',
      );
      expect(adapter.requests.last.path, contains('st-2'));
    });

    testWidgets('ORPHAN: guardians/me 404 renders UnlinkedProfileState with '
        'no retry', (tester) async {
      final adapter = _Adapter((o) {
        throw _notFound(o, 'Guardian record linked to this login not found');
      });

      await tester.pumpWidget(host(ParentHomeScreen(repository: _repo(adapter))));
      await tester.pumpAndSettle();

      expect(find.byType(UnlinkedProfileState), findsOneWidget);
      // D-17: the parent cannot fix this themselves, so no retry is offered.
      // 'Retry' is ErrorState's FIRST-attempt label ('Try again' only appears
      // after a second failure, per D-11) — asserting the wrong one would
      // have passed trivially.
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('a guardian with NO children shows the empty state, not a '
        'blank screen', (tester) async {
      final adapter = _Adapter((o) => _json(200, {
            'guardianId': 'g-1',
            'firstName': 'Imran',
            'lastName': 'Ahmed',
            'students': <Object>[],
          }));

      await tester.pumpWidget(host(ParentHomeScreen(repository: _repo(adapter))));
      await tester.pumpAndSettle();

      expect(find.text('No children linked'), findsOneWidget);
    });

    testWidgets('a server error offers a WORKING retry', (tester) async {
      var fail = true;
      final adapter = _Adapter((o) {
        if (fail && o.path == ApiConfig.guardiansMePath) {
          throw DioException(
            requestOptions: o,
            response: Response(
              requestOptions: o,
              statusCode: 500,
              data: const {'message': 'Server exploded'},
            ),
          );
        }
        if (o.path == ApiConfig.guardiansMePath) {
          return _json(200, _guardianJson());
        }
        return _json(200, _progressJson(status: 'present'));
      });

      await tester.pumpWidget(host(ParentHomeScreen(repository: _repo(adapter))));
      await tester.pumpAndSettle();

      expect(find.text('Server exploded'), findsOneWidget);

      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Bilal Ahmed'), findsOneWidget);
    });
  });

  group('Child attendance detail', () {
    const child = GuardianChild(
      studentId: 'st-1',
      fullName: 'Bilal Ahmed',
      sectionId: 'sec-1',
      sectionName: 'Class 9-C',
    );

    testWidgets('lists each day with its status pill', (tester) async {
      await tester.pumpWidget(host(ChildAttendanceScreen(
        repository: _repo(_happyAdapter()),
        child: child,
        now: () => DateTime(2026, 8, 11),
      )));
      await tester.pumpAndSettle();

      expect(find.text('2026-08-11'), findsOneWidget);
      expect(find.text('2026-08-10'), findsOneWidget);
      expect(find.byType(StatusPill), findsNWidgets(3));
    });

    testWidgets('READ-ONLY: no marking affordance anywhere', (tester) async {
      // Parents hold attendance.view and NOT attendance.mark (confirmed from
      // the real parent JWT), so any control here would be rejected by the
      // backend — a false affordance.
      await tester.pumpWidget(host(ChildAttendanceScreen(
        repository: _repo(_happyAdapter()),
        child: child,
        now: () => DateTime(2026, 8, 11),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Submit'), findsNothing);
      expect(find.text('Present'), findsWidgets); // pills, not buttons
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('empty range shows the empty state', (tester) async {
      final adapter = _Adapter((o) => _json(200, _attendanceJson(const [])));
      await tester.pumpWidget(host(ChildAttendanceScreen(
        repository: _repo(adapter),
        child: child,
        now: () => DateTime(2026, 8, 11),
      )));
      await tester.pumpAndSettle();

      expect(find.text('No attendance recorded'), findsOneWidget);
    });

    testWidgets('requests exactly the 30-day window it advertises',
        (tester) async {
      final adapter = _happyAdapter();
      await tester.pumpWidget(host(ChildAttendanceScreen(
        repository: _repo(adapter),
        child: child,
        now: () => DateTime(2026, 8, 11),
      )));
      await tester.pumpAndSettle();

      final req = adapter.requests.single;
      expect(req.queryParameters['from'], '2026-07-12');
      expect(req.queryParameters['to'], '2026-08-11');
      expect(find.textContaining('Last 30 days'), findsOneWidget);
    });
  });

  group('No overflow at 360, 768 and 1366px', () {
    for (final width in [360.0, 768.0, 1366.0]) {
      testWidgets('parent landing at ${width.toInt()}px', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(host(
          ParentHomeScreen(repository: _repo(_happyAdapter(childCount: 2))),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('attendance detail at 2x text on a 360px phone',
        (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(
        ChildAttendanceScreen(
          repository: _repo(_happyAdapter()),
          child: const GuardianChild(
            studentId: 'st-1',
            fullName: 'Bilal Ahmed',
            sectionId: 'sec-1',
          ),
          now: () => DateTime(2026, 8, 11),
        ),
        textScale: 2,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  // T16: the fields `/api/parent-progress/student/{id}` has always returned
  // and T9 never read, now that the screens giving them meaning exist.
  group('child progress — the rest of the day', () {
    ChildToday today({
      Map<String, dynamic>? stats,
      Map<String, dynamic>? result,
      List<Map<String, dynamic>> remarks = const [],
      List<String> diary = const [],
    }) =>
        ChildToday.fromJson({
          'studentId': 's1',
          'date': '2026-09-27',
          'studentName': 'Ali Khan',
          'attendanceStatus': 'present',
          'attendanceStats': stats,
          'latestResult': result,
          'remarks': remarks,
          'diaryEntries': diary,
        });

    Widget host(ChildToday value) => MaterialApp(
          theme: AppTheme.light(role: AppRole.parent),
          home: Scaffold(body: ChildProgressDetails(today: value)),
        );

    testWidgets('nothing renders when there is nothing to show',
        (tester) async {
      await tester.pumpWidget(host(today()));
      await tester.pumpAndSettle();

      // Four empty headings is not an answer.
      expect(find.text('Attendance so far'), findsNothing);
      expect(find.text('Latest result'), findsNothing);
      expect(find.text('From the teacher'), findsNothing);
    });

    testWidgets('attendance uses the server’s own below-threshold judgement',
        (tester) async {
      await tester.pumpWidget(host(today(stats: const {
        'totalDays': 20,
        'present': 12,
        'absent': 8,
        'percentage': 60,
        'belowThreshold': true,
      })));
      await tester.pumpAndSettle();

      expect(find.text('60% · 12 of 20 days'), findsOneWidget);
      expect(
        find.textContaining('below the school’s expected attendance'),
        findsOneWidget,
      );
    });

    testWidgets('a healthy attendance is not flagged', (tester) async {
      await tester.pumpWidget(host(today(stats: const {
        'totalDays': 20,
        'present': 19,
        'absent': 1,
        'percentage': 95,
        'belowThreshold': false,
      })));
      await tester.pumpAndSettle();

      expect(find.textContaining('below the school'), findsNothing);
    });

    testWidgets('a result renders the server’s figure verbatim',
        (tester) async {
      await tester.pumpWidget(host(today(result: const {
        'examName': 'First Term',
        'percentage': 90.00,
        'grade': 'A1',
        'position': 2,
      })));
      await tester.pumpAndSettle();

      // Never re-formatted through a double, which is how 90.00 becomes
      // 89.99999 on a parent's phone.
      expect(find.text('90.0%'), findsOneWidget);
      expect(find.text('Grade A1'), findsOneWidget);
      expect(find.text('Position 2'), findsOneWidget);
    });

    testWidgets('remarks render as the server sent them', (tester) async {
      await tester.pumpWidget(host(today(remarks: const [
        {
          'body': 'Doing well in maths',
          'remarkType': 'academic',
          'remarkDate': '2026-09-26',
          'authorName': 'Ayesha Khan',
        },
      ])));
      await tester.pumpAndSettle();

      expect(find.text('Doing well in maths'), findsOneWidget);
      expect(find.text('Ayesha Khan · 2026-09-26'), findsOneWidget);
    });

    test('the app does not filter remarks — the server already did', () {
      // Verified live: a remark flagged isParentVisible:false never arrives
      // here. Filtering on the device would hide a server regression, which
      // is the arrangement T15's remarks defect proved unreliable.
      final value = today(remarks: const [
        {'body': 'a', 'remarkType': 'x', 'remarkDate': 'd', 'authorName': 'n'},
        {'body': 'b', 'remarkType': 'x', 'remarkDate': 'd', 'authorName': 'n'},
      ]);
      expect(value.remarks.length, 2);
    });

    testWidgets('it survives a narrow phone at a large text scale',
        (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(role: AppRole.parent),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: ChildProgressDetails(
                today: today(
                  stats: const {
                    'totalDays': 20,
                    'present': 12,
                    'absent': 8,
                    'percentage': 60,
                    'belowThreshold': true,
                  },
                  result: const {
                    'examName': 'First Term Examination 2026',
                    'percentage': 90.00,
                    'grade': 'A1',
                    'position': 2,
                  },
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
