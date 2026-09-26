import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/api_config.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/features/timetable/data/timetable_repository.dart';
import 'package:smartems/features/timetable/presentation/today_screen.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.responder);

  final ResponseBody Function(RequestOptions o) responder;

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<List<int>>? s, Future<void>? c) async =>
      responder(o);

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

/// A verbatim copy of a real `/api/timetable/teacher/{id}/today` response,
/// captured live on 2026-08-10 after Ali's camelCase + sectionId change.
const _liveTodayRow = {
  'slotId': '019feb16-e383-79d3-96be-c76d454328c0',
  'dayOfWeek': 1,
  'periodId': '019fd1e8-5e3a-7df0-868e-72aafd904e6f',
  'periodName': 'Period 3',
  'startTime': '09:45:00',
  'endTime': '10:30:00',
  'sortOrder': 4,
  'sectionId': '019fd1aa-2827-7fa3-a0ac-5f2fedda6ccc',
  'sectionName': 'Class 9-C',
  'subjectId': '019fd1aa-2be9-7e89-be72-12f30b02303b',
  'subjectName': 'Mathematics',
  'teacherStaffId': '019fd1aa-2fb0-732e-a495-434e880ae8cb',
  'roomId': null,
  'roomName': null,
};

Dio _dio(_Adapter a) =>
    Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))..httpClientAdapter = a;

Widget host(Widget child) => MaterialApp(
      theme: AppTheme.light(role: AppRole.teacher),
      home: child,
    );

void main() {
  group('TimetablePeriod.fromJson — camelCase contract', () {
    // THIS is the test that was missing when the casing changed under us:
    // the whole suite passed while the parser silently produced empty
    // strings for every field. Pinned to a captured live payload so a
    // future rename cannot pass quietly again.
    test('parses a real live payload', () {
      final p = TimetablePeriod.fromJson(_liveTodayRow);

      expect(p.periodName, 'Period 3');
      expect(p.startTime, '09:45:00');
      expect(p.endTime, '10:30:00');
      expect(p.sortOrder, 4);
      expect(p.sectionId, '019fd1aa-2827-7fa3-a0ac-5f2fedda6ccc');
      expect(p.sectionName, 'Class 9-C');
      expect(p.subjectName, 'Mathematics');
    });

    test('the OLD snake_case keys no longer parse — proving the fix is real '
        'and not merely additive', () {
      final p = TimetablePeriod.fromJson(const {
        'period_name': 'Period 3',
        'start_time': '09:45:00',
        'section_id': 'sec-1',
      });

      expect(p.periodName, '');
      expect(p.sectionId, isNull);
    });

    test('sectionName is used verbatim — the app does not compose it', () {
      // The backend already returns "{class}-{section}". Rebuilding that
      // label client-side would drift from whatever the backend decides.
      expect(
        TimetablePeriod.fromJson(_liveTodayRow).sectionName,
        'Class 9-C',
      );
    });

    test('time label trims seconds', () {
      expect(TimetablePeriod.fromJson(_liveTodayRow).timeLabel, '09:45–10:30');
    });

    test('isCurrent brackets the period', () {
      final p = TimetablePeriod.fromJson(_liveTodayRow);
      expect(p.isCurrent(DateTime(2026, 8, 10, 10)), isTrue);
      expect(p.isCurrent(DateTime(2026, 8, 10, 9, 44)), isFalse);
      expect(p.isCurrent(DateTime(2026, 8, 10, 10, 30)), isFalse);
    });
  });

  group('TodayScreen — navigation into the register', () {
    testWidgets('a period WITH a sectionId is tappable and hands it over',
        (tester) async {
      TimetablePeriod? opened;
      await tester.pumpWidget(host(TodayScreen(
        repository: TimetableRepository(
          _dio(_Adapter((o) => _json(200, [_liveTodayRow]))),
        ),
        staffId: 'staff-1',
        onOpenRegister: (p) => opened = p,
        now: () => DateTime(2026, 8, 10, 10),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Class 9-C · Mathematics'), findsOneWidget);

      await tester.tap(find.text('Class 9-C · Mathematics'));
      await tester.pumpAndSettle();

      expect(opened, isNotNull);
      expect(opened!.sectionId, '019fd1aa-2827-7fa3-a0ac-5f2fedda6ccc');
    });

    testWidgets('a period WITHOUT a sectionId is inert and shows no chevron — '
        'opening the wrong register is worse than a dead row',
        (tester) async {
      var taps = 0;
      final noSection = Map<String, dynamic>.from(_liveTodayRow)
        ..remove('sectionId');

      await tester.pumpWidget(host(TodayScreen(
        repository: TimetableRepository(
          _dio(_Adapter((o) => _json(200, [noSection]))),
        ),
        staffId: 'staff-1',
        onOpenRegister: (_) => taps++,
        now: () => DateTime(2026, 8, 10, 10),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Class 9-C · Mathematics'));
      await tester.pumpAndSettle();

      expect(taps, 0);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('POSITIVE PAIR: the tappable case DOES show a chevron',
        (tester) async {
      await tester.pumpWidget(host(TodayScreen(
        repository: TimetableRepository(
          _dio(_Adapter((o) => _json(200, [_liveTodayRow]))),
        ),
        staffId: 'staff-1',
        onOpenRegister: (_) {},
        now: () => DateTime(2026, 8, 10, 10),
      )));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('no staff record: an honest empty state, not a failure',
        (tester) async {
      await tester.pumpWidget(host(TodayScreen(
        repository: TimetableRepository(
          _dio(_Adapter((o) => _json(200, const <Object>[]))),
        ),
        staffId: null,
      )));
      await tester.pumpAndSettle();

      expect(find.text('No teaching schedule'), findsOneWidget);
    });

    testWidgets('the T8 blocker notice is GONE', (tester) async {
      await tester.pumpWidget(host(TodayScreen(
        repository: TimetableRepository(
          _dio(_Adapter((o) => _json(200, [_liveTodayRow]))),
        ),
        staffId: 'staff-1',
        onOpenRegister: (_) {},
        now: () => DateTime(2026, 8, 10, 10),
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('Read-only for now'), findsNothing);
      expect(find.textContaining('does not yet return'), findsNothing);
    });
  });
}
