import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/api_config.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/app_text_field.dart';
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
    if (o.path == ApiConfig.attendanceBulkPath) {
      return _serverDecides(o, serverRecords);
    }
    return _json(200, {'successCount': 1, 'errorCount': 0});
  });
}

/// Mirrors the backend: a queued mark that differs from the server record is
/// held for review (ADR-010); everything else is applied.
ResponseBody _serverDecides(
  RequestOptions o,
  List<Map<String, dynamic>>? serverRecords,
) {
  final held = {
    for (final r in serverRecords ?? const <Map<String, dynamic>>[])
      r['studentId']: r['status'],
  };
  final rows = ((o.data as Map)['rows'] as List).cast<Map>();
  final ops = [
    for (final r in rows)
      held[r['studentId']] != null && held[r['studentId']] != r['status']
          ? {
              'clientUuid': r['clientUuid'],
              'studentId': r['studentId'],
              'outcome': 'review_required',
              'reviewId': 'rev-${r['studentId']}',
            }
          : {
              'clientUuid': r['clientUuid'],
              'studentId': r['studentId'],
              'outcome': 'accepted',
              'eventId': 'ev-${r['studentId']}',
            },
  ];
  return _json(200, {
    'successCount': rows.length,
    'errorCount': 0,
    'operations': ops,
  });
}

Widget host(Widget child, {double textScale = 1.0}) => MaterialApp(
  theme: AppTheme.light(role: AppRole.teacher),
  builder: (context, mqChild) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: mqChild!,
  ),
  home: child,
);

AttendanceRepository _repo(_Adapter a) => AttendanceRepository(
  dio: Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))..httpClientAdapter = a,
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
  registerToolbarTests();
  group('Attendance marking — roster and submission', () {
    // QA-14 (product owner decision A, 2026-10-14) REVERSES the old default:
    // a learner nobody has marked is UNMARKED, never a silent Present.
    testWidgets(
      'loads the roster; untouched learners are Unmarked, not Present (QA-14)',
      (tester) async {
        await tester.pumpWidget(host(_screen(_rosterAdapter())));
        await tester.pumpAndSettle();

        expect(find.text('1  Bilal Ahmed'), findsOneWidget);
        expect(find.text('2  Fatima Noor'), findsOneWidget);
        expect(find.byKey(const Key('unmarked-st1')), findsOneWidget);
        expect(find.byKey(const Key('unmarked-st2')), findsOneWidget);
        expect(
          find.text('Present'),
          findsNWidgets(2),
          reason: 'only the two choice buttons; no Present pill',
        );
        expect(
          find.byKey(const Key('count-present')),
          findsNothing,
          reason: 'unmarked never counts as Present',
        );
        expect(find.text('Unmarked 2'), findsOneWidget);
      },
    );

    testWidgets(
      'QA-14: submitting an untouched register sends NOTHING and says so',
      (tester) async {
        final adapter = _rosterAdapter();
        await tester.pumpWidget(host(_screen(adapter)));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(AppButton, 'Submit'));
        await tester.pumpAndSettle();
        expect(
          adapter.requests.where((r) => r.path == ApiConfig.attendanceBulkPath),
          isEmpty,
          reason: 'no invented Present records',
        );
        expect(
          find.textContaining('2 learners are still unmarked'),
          findsOneWidget,
        );
      },
    );

    testWidgets('QA-14: a partial register sends only the marked learner', (
      tester,
    ) async {
      final adapter = _rosterAdapter();
      await tester.pumpWidget(host(_screen(adapter)));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Absent for Bilal Ahmed'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('pending-st1')),
        findsOneWidget,
        reason: 'deliberate, not yet saved',
      );
      await tester.tap(find.widgetWithText(AppButton, 'Submit'));
      await tester.pumpAndSettle();
      final bulk = adapter.requests.firstWhere(
        (r) => r.path == ApiConfig.attendanceBulkPath,
      );
      final rows = (bulk.data as Map)['rows'] as List;
      expect(rows.map((r) => (r as Map)['studentId']), ['st1']);
      expect((rows.single as Map)['status'], 'absent');
    });

    testWidgets('submitting posts a bulk row per student', (tester) async {
      final adapter = _rosterAdapter();
      await tester.pumpWidget(host(_screen(adapter)));
      await tester.pumpAndSettle();
      // QA-14: every learner is marked deliberately first.
      await tester.tap(find.bySemanticsLabel('Present for Bilal Ahmed'));
      await tester.tap(find.bySemanticsLabel('Late for Fatima Noor'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(AppButton, 'Submit'));
      await tester.pumpAndSettle();

      final bulk = adapter.requests.firstWhere(
        (r) => r.path == ApiConfig.attendanceBulkPath,
      );
      final rows = (bulk.data as Map)['rows'] as List;
      expect(rows.length, 2);
      final ids = rows
          .map((row) => (row as Map)['clientUuid'] as String)
          .toList();
      expect(ids.toSet().length, rows.length);
      for (final id in ids) {
        expect(
          id,
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            ),
          ),
        );
      }
      expect((bulk.data as Map)['sectionId'], 'sec-1');
      expect((bulk.data as Map)['attendanceDate'], '2026-08-05');
    });

    testWidgets('empty roster shows the empty state, not a blank list', (
      tester,
    ) async {
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
      final adapter = _rosterAdapter(
        serverRecords: [
          {'studentId': 'st1', 'status': 'absent'},
        ],
      );
      await tester.pumpWidget(host(_screen(adapter)));
      await tester.pumpAndSettle();

      // F15: the register now opens with the office record (absent); the
      // teacher deliberately disagrees before submitting.
      await tester.tap(find.bySemanticsLabel('Present for Bilal Ahmed'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, 'Submit'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('1 of your marks differs from the office record'),
        findsOneWidget,
        reason: 'server keeps its record, the teacher must be told',
      );
      // Non-blocking: no dialog, and the roster is still on screen.
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('1  Bilal Ahmed'), findsOneWidget);
    });

    // F15 (physical Pixel 7 Pro): a reopened register must show what the
    // server already holds, never a silent all-Present default.
    testWidgets('reopened register shows the marks already recorded', (
      tester,
    ) async {
      final adapter = _rosterAdapter(
        serverRecords: [
          {'student_id': 'st1', 'status': 'absent'},
        ],
      );
      await tester.pumpWidget(host(_screen(adapter)));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Absent for Bilal Ahmed')),
        isSemantics(isSelected: true),
      );
      // QA-14: no server record and no tap → Unmarked (formerly a default Present).
      expect(find.byKey(const Key('unmarked-st2')), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Present for Fatima Noor')),
        isSemantics(isSelected: false),
      );
      expect(find.textContaining('could not be loaded'), findsNothing);
    });

    testWidgets(
      'when existing marks cannot load, the register warns instead of silently defaulting',
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
        expect(
          find.textContaining(
            'Marks already recorded today could not be loaded',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Bilal Ahmed'),
          findsOneWidget,
          reason: 'offline marking remains possible',
        );
      },
    );

    testWidgets('offline submission reports that it queued — not an error', (
      tester,
    ) async {
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
      await tester.tap(find.bySemanticsLabel('Present for Bilal Ahmed'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, 'Submit'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Saved offline'), findsOneWidget);
      expect(
        find.byKey(const Key('pending-st1')),
        findsOneWidget,
        reason: 'queued, not confirmed',
      );
      expect(find.textContaining('will sync'), findsOneWidget);
    });
  });

  group('Lock window — a locked register EXPLAINS itself', () {
    testWidgets('past the window: no submit button, and a stated reason', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          _screen(
            _rosterAdapter(),
            date: DateTime(2026, 8, 1),
            now: DateTime(2026, 8, 5, 10),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // ABSENCE: the control is gone, not silently disabled.
      expect(find.widgetWithText(AppButton, 'Submit'), findsNothing);
      // Paired POSITIVE: an explanation is present, naming who can help.
      expect(find.byType(InlineAlert), findsWidgets);
      expect(
        find.textContaining('closed at the end of the day'),
        findsOneWidget,
      );
      expect(find.textContaining('administrator'), findsOneWidget);
    });

    testWidgets('inside the window: submit is available', (tester) async {
      await tester.pumpWidget(
        host(
          _screen(
            _rosterAdapter(),
            date: DateTime(2026, 8, 5),
            now: DateTime(2026, 8, 5, 10),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppButton, 'Submit'), findsOneWidget);
    });

    test('a zero window is a REAL value, not a special case', () {
      // The production value today. Same arithmetic must grant real extra
      // time once Ali configures a non-zero one — no branching on zero.
      const immediate = LockWindow.immediate();
      final date = DateTime(2026, 8, 5);

      expect(
        immediate.isOpen(
          attendanceDate: date,
          now: DateTime(2026, 8, 5, 23, 59),
        ),
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
        reason:
            'a configured window must extend the deadline with no code '
            'change',
      );
    });
  });

  group('Settings / More — closes the mobile sign-out gap', () {
    testWidgets('offers sign-out and calls it', (tester) async {
      var signedOut = 0;
      await tester.pumpWidget(
        host(
          SettingsScreen(
            onSignOut: () async => signedOut++,
            institutionCode: 'test-school',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('test-school'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppButton, 'Sign out'));
      await tester.pumpAndSettle();

      expect(signedOut, 1);
    });
  });

  group('No overflow at 360, 768 and 1366px', () {
    for (final width in [360.0, 768.0, 1366.0]) {
      testWidgets('marking screen renders clean at ${width.toInt()}px', (
        tester,
      ) async {
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

      await tester.pumpWidget(host(_screen(_rosterAdapter()), textScale: 2));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}

/// Overhaul M3: register totals, bulk action, search, unsaved-change guard.
_Adapter _bigRoster(int n) => _Adapter((o) {
  if (o.path.contains(ApiConfig.enrollmentsSectionPath)) {
    return _json(200, {
      'content': [
        for (var i = 1; i <= n; i++)
          {'studentId': 'st$i', 'status': 'enrolled', 'rollNumber': '$i'},
      ],
    });
  }
  if (o.path == ApiConfig.studentsPath) {
    return _json(200, {
      'content': [
        for (var i = 1; i <= n; i++)
          {
            'id': 'st$i',
            'firstName': i == 7 ? 'Zainab' : 'Learner',
            'lastName': '$i',
          },
      ],
    });
  }
  if (o.path.contains(ApiConfig.attendanceSectionPath)) {
    return _json(200, {
      'records': [
        {'studentId': 'st2', 'status': 'absent'},
      ],
    });
  }
  return _json(200, {'successCount': 1, 'errorCount': 0});
});

void registerToolbarTests() {
  group('Register toolbar (overhaul M3)', () {
    testWidgets('totals reflect the real marks and update as marks change', (
      tester,
    ) async {
      await tester.pumpWidget(host(_screen(_bigRoster(3))));
      await tester.pumpAndSettle();
      // QA-14: 1 saved (Absent from the server), 2 unmarked, no invented Present.
      expect(
        find.text('Absent 1'),
        findsOneWidget,
        reason: 'prefilled from the server (F15)',
      );
      expect(find.text('Unmarked 2'), findsOneWidget);
      expect(find.byKey(const Key('count-present')), findsNothing);
      await tester.tap(find.bySemanticsLabel('Absent for Learner 1'));
      await tester.pumpAndSettle();
      expect(find.text('Absent 2'), findsOneWidget);
      expect(find.text('Unmarked 1'), findsOneWidget);
      expect(find.text('Not yet saved 1'), findsOneWidget);
    });

    testWidgets('Mark all present asks first and changes nothing on Cancel', (
      tester,
    ) async {
      await tester.pumpWidget(host(_screen(_bigRoster(3))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mark-all-present')));
      await tester.pumpAndSettle();
      expect(find.text('Mark unmarked learners present?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Absent 1'), findsOneWidget);
      expect(find.text('Unmarked 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('mark-all-present')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-all-present')));
      await tester.pumpAndSettle();
      // QA-14: only the 2 unmarked learners change; the saved Absent stays.
      expect(find.text('Present 2'), findsOneWidget);
      expect(
        find.text('Absent 1'),
        findsOneWidget,
        reason: 'a saved status is never overwritten in bulk',
      );
      expect(find.text('Unmarked 2'), findsNothing);
      expect(
        find.byKey(const Key('mark-all-present')),
        findsNothing,
        reason: 'nobody left unmarked',
      );
    });

    testWidgets(
      'search appears for larger classes and filters by name or roll number',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(host(_screen(_bigRoster(12))));
        await tester.pumpAndSettle();
        final search = find.widgetWithText(
          AppTextField,
          'Search by name or roll number',
        );
        expect(search, findsOneWidget);
        await tester.enterText(
          find.descendant(of: search, matching: find.byType(TextField)),
          'zain',
        );
        await tester.pumpAndSettle();
        expect(find.text('7  Zainab 7'), findsOneWidget);
        expect(find.text('1  Learner 1'), findsNothing);
        await tester.enterText(
          find.descendant(of: search, matching: find.byType(TextField)),
          '3',
        );
        await tester.pumpAndSettle();
        expect(
          find.text('3  Learner 3'),
          findsOneWidget,
          reason: 'exact roll number',
        );
      },
    );

    testWidgets('small classes get no search box', (tester) async {
      await tester.pumpWidget(host(_screen(_bigRoster(3))));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(AppTextField, 'Search by name or roll number'),
        findsNothing,
      );
    });

    testWidgets('leaving with unsubmitted marks asks before discarding them', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(role: AppRole.teacher),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _screen(_bigRoster(3)),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Late for Learner 1'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Leave without submitting?'), findsOneWidget);
      await tester.tap(find.text('Keep marking'));
      await tester.pumpAndSettle();
      expect(
        find.text('Class 9-C'),
        findsOneWidget,
        reason: 'still on the register',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-leave')));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets(
      'NOTE-QA-17: embedded in a parent flow, "Keep marking" STAYS on the register',
      (tester) async {
        // The Today flow shows the register inside its own state, not as a route.
        // Before the fix a parent back handler closed it on the same back press,
        // so the dialog appeared over Today and unsaved marks were lost.
        final adapter = _bigRoster(3);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(role: AppRole.teacher),
            home: _EmbeddedFlow(
              register: (onExit) => AttendanceMarkingScreen(
                repository: _repo(adapter),
                sectionId: 'sec-1',
                sectionLabel: 'Class 9-C',
                attendanceDate: DateTime(2026, 8, 5),
                now: () => DateTime(2026, 8, 5, 10),
                onExit: onExit,
              ),
            ),
          ),
        );
        await tester.tap(find.text('open register'));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Late for Learner 1'));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Leave without submitting?'), findsOneWidget);
        await tester.tap(find.text('Keep marking'));
        await tester.pumpAndSettle();
        expect(
          find.text('Class 9-C'),
          findsOneWidget,
          reason: 'still on the register',
        );
        expect(find.text('Today list'), findsNothing);
        // The unsaved mark is still there.
        expect(find.textContaining('Late 1'), findsWidgets);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm-leave')));
        await tester.pumpAndSettle();
        expect(
          find.text('Today list'),
          findsOneWidget,
          reason: 'confirmed Leave returns to the parent',
        );
      },
    );

    testWidgets(
      'NOTE-QA-17: embedded with nothing unsaved, back leaves at once',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(role: AppRole.teacher),
            home: _EmbeddedFlow(
              register: (onExit) => AttendanceMarkingScreen(
                repository: _repo(_bigRoster(3)),
                sectionId: 'sec-1',
                sectionLabel: 'Class 9-C',
                attendanceDate: DateTime(2026, 8, 5),
                now: () => DateTime(2026, 8, 5, 10),
                onExit: onExit,
              ),
            ),
          ),
        );
        await tester.tap(find.text('open register'));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Leave without submitting?'), findsNothing);
        expect(find.text('Today list'), findsOneWidget);
      },
    );
  });
}

/// Mirrors the Today flow: a parent that swaps a list for the register.
class _EmbeddedFlow extends StatefulWidget {
  const _EmbeddedFlow({required this.register});
  final Widget Function(VoidCallback onExit) register;
  @override
  State<_EmbeddedFlow> createState() => _EmbeddedFlowState();
}

class _EmbeddedFlowState extends State<_EmbeddedFlow> {
  bool _open = false;
  @override
  Widget build(BuildContext context) => _open
      ? widget.register(() => setState(() => _open = false))
      : Scaffold(
          body: Column(
            children: [
              const Text('Today list'),
              TextButton(
                onPressed: () => setState(() => _open = true),
                child: const Text('open register'),
              ),
            ],
          ),
        );
}
