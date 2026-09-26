import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/api_config.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/app_button.dart';
import 'package:smartems/core/widgets/inline_alert.dart';
import 'package:smartems/features/attendance/data/attendance_queue.dart';
import 'package:smartems/features/attendance/data/attendance_repository.dart';
import 'package:smartems/features/attendance/domain/lock_window.dart';
import 'package:smartems/features/attendance/presentation/attendance_marking_screen.dart';
import 'package:smartems/features/settings/presentation/settings_screen.dart';

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

/// A roster of two, plus an empty attendance summary.
_Adapter _rosterAdapter({List<Map<String, dynamic>>? serverRecords}) {
  return _Adapter((o) {
    if (o.path.contains(ApiConfig.enrollmentsSectionPath)) {
      return _json(200, {
        'content': [
          {'studentId': 'st1', 'status': 'enrolled', 'rollNumber': '1'},
          {'studentId': 'st2', 'status': 'enrolled', 'rollNumber': '2'},
        ],
      });
    }
    if (o.path == ApiConfig.studentsPath) {
      return _json(200, {
        'content': [
          {'id': 'st1', 'firstName': 'Bilal', 'lastName': 'Ahmed'},
          {'id': 'st2', 'firstName': 'Fatima', 'lastName': 'Noor'},
        ],
      });
    }
    if (o.path.contains(ApiConfig.attendanceSectionPath)) {
      return _json(200, {'records': serverRecords ?? const <Object>[]});
    }
    return _json(200, {'successCount': 2, 'errorCount': 0});
  });
}

Widget host(Widget child, {double textScale = 1.0}) => MaterialApp(
      theme: AppTheme.light(role: AppRole.teacher),
      builder: (context, mqChild) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: mqChild!,
      ),
      home: child,
    );

AttendanceRepository _repo(_Adapter a) => AttendanceRepository(
      dio: Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))
        ..httpClientAdapter = a,
      queue: AttendanceQueue(NativeDatabase.memory()),
    );

Widget _screen(
  _Adapter adapter, {
  LockWindow lockWindow = const LockWindow.immediate(),
  DateTime? date,
  DateTime? now,
}) {
  final d = date ?? DateTime(2026, 8, 5);
  return AttendanceMarkingScreen(
    repository: _repo(adapter),
    sectionId: 'sec-1',
    sectionLabel: 'Class 9-C',
    attendanceDate: d,
    lockWindow: lockWindow,
    now: () => now ?? DateTime(2026, 8, 5, 10),
  );
}

void main() {
  group('Attendance marking — roster and submission', () {
    testWidgets('loads the roster and defaults everyone to Present',
        (tester) async {
      await tester.pumpWidget(host(_screen(_rosterAdapter())));
      await tester.pumpAndSettle();

      expect(find.text('1  Bilal Ahmed'), findsOneWidget);
      expect(find.text('2  Fatima Noor'), findsOneWidget);
      // Both rows show a Present pill by default: the backend has no default
      // status, so the client must pick one, and marking the exceptions is
      // less work than marking the majority.
      expect(find.text('Present'), findsNWidgets(4)); // 2 pills + 2 choices
    });

    testWidgets('submitting posts a bulk row per student', (tester) async {
      final adapter = _rosterAdapter();
      await tester.pumpWidget(host(_screen(adapter)));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(AppButton, 'Submit'));
      await tester.pumpAndSettle();

      final bulk = adapter.requests
          .firstWhere((r) => r.path == ApiConfig.attendanceBulkPath);
      final rows = (bulk.data as Map)['rows'] as List;
      expect(rows.length, 2);
      expect((bulk.data as Map)['sectionId'], 'sec-1');
      expect((bulk.data as Map)['attendanceDate'], '2026-08-05');
    });

    testWidgets('empty roster shows the empty state, not a blank list',
        (tester) async {
      final adapter = _Adapter((o) {
        if (o.path.contains(ApiConfig.enrollmentsSectionPath)) {
          return _json(200, {'content': <Object>[]});
        }
        return _json(200, {'content': <Object>[]});
      });
      await tester.pumpWidget(host(_screen(adapter)));
      await tester.pumpAndSettle();

      expect(find.text('No students enrolled'), findsOneWidget);
    });

    testWidgets('a conflict surfaces a NON-BLOCKING notice and adopts the '
        'server value', (tester) async {
      final adapter = _rosterAdapter(serverRecords: [
        {'studentId': 'st1', 'status': 'absent'},
      ]);
      await tester.pumpWidget(host(_screen(adapter)));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(AppButton, 'Submit'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('replaced 1 of your marks'),
        findsOneWidget,
        reason: 'server wins, but the teacher must be told',
      );
      // Non-blocking: no dialog, and the roster is still on screen.
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('1  Bilal Ahmed'), findsOneWidget);
    });

    testWidgets('offline submission reports that it queued — not an error',
        (tester) async {
      final adapter = _Adapter((o) {
        if (o.path.contains(ApiConfig.enrollmentsSectionPath)) {
          return _json(200, {
            'content': [
              {'studentId': 'st1', 'status': 'enrolled'},
            ],
          });
        }
        if (o.path == ApiConfig.studentsPath) {
          return _json(200, {
            'content': [
              {'id': 'st1', 'firstName': 'Bilal', 'lastName': 'Ahmed'},
            ],
          });
        }
        throw DioException(
          requestOptions: o,
          type: DioExceptionType.connectionError,
        );
      });

      await tester.pumpWidget(host(_screen(adapter)));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, 'Submit'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Saved offline'), findsOneWidget);
      expect(find.textContaining('will sync'), findsOneWidget);
    });
  });

  group('Lock window — a locked register EXPLAINS itself', () {
    testWidgets('past the window: no submit button, and a stated reason',
        (tester) async {
      await tester.pumpWidget(host(_screen(
        _rosterAdapter(),
        date: DateTime(2026, 8, 1),
        now: DateTime(2026, 8, 5, 10),
      )));
      await tester.pumpAndSettle();

      // ABSENCE: the control is gone, not silently disabled.
      expect(find.widgetWithText(AppButton, 'Submit'), findsNothing);
      // Paired POSITIVE: an explanation is present, naming who can help.
      expect(find.byType(InlineAlert), findsWidgets);
      expect(find.textContaining('closed at the end of the day'), findsOneWidget);
      expect(find.textContaining('administrator'), findsOneWidget);
    });

    testWidgets('inside the window: submit is available', (tester) async {
      await tester.pumpWidget(host(_screen(
        _rosterAdapter(),
        date: DateTime(2026, 8, 5),
        now: DateTime(2026, 8, 5, 10),
      )));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(AppButton, 'Submit'),
        findsOneWidget,
      );
    });

    test('a zero window is a REAL value, not a special case', () {
      // The production value today. Same arithmetic must grant real extra
      // time once Ali configures a non-zero one — no branching on zero.
      const immediate = LockWindow.immediate();
      final date = DateTime(2026, 8, 5);

      expect(
        immediate.isOpen(
            attendanceDate: date, now: DateTime(2026, 8, 5, 23, 59)),
        isTrue,
      );
      expect(
        immediate.isOpen(attendanceDate: date, now: DateTime(2026, 8, 6, 0, 1)),
        isFalse,
      );

      const oneDay = LockWindow(Duration(days: 1));
      expect(
        oneDay.isOpen(attendanceDate: date, now: DateTime(2026, 8, 6, 12)),
        isTrue,
        reason: 'a configured window must extend the deadline with no code '
            'change',
      );
    });
  });

  group('Settings / More — closes the mobile sign-out gap', () {
    testWidgets('offers sign-out and calls it', (tester) async {
      var signedOut = 0;
      await tester.pumpWidget(host(SettingsScreen(
        onSignOut: () async => signedOut++,
        institutionCode: 'test-school',
      )));
      await tester.pumpAndSettle();

      expect(find.text('test-school'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppButton, 'Sign out'));
      await tester.pumpAndSettle();

      expect(signedOut, 1);
    });
  });

  group('No overflow at 360, 768 and 1366px', () {
    for (final width in [360.0, 768.0, 1366.0]) {
      testWidgets('marking screen renders clean at ${width.toInt()}px',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(host(_screen(_rosterAdapter())));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('five status choices reflow rather than overflow at 2x text '
        'scale on a 360px phone', (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester
          .pumpWidget(host(_screen(_rosterAdapter()), textScale: 2));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
