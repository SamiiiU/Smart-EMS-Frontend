import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'dart:ui' show Tristate;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/api_config.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/status_pill.dart';
import 'package:smartems/features/parent/data/parent_repository.dart';
import 'package:smartems/features/parent/domain/parent_models.dart';
import 'package:smartems/features/parent/presentation/child_attendance_screen.dart';
import 'package:smartems/features/parent/presentation/parent_home_screen.dart';

/// M5 parent portal: child switcher and Child Attendance. Synthetic fixtures
/// on a scripted transport that records every request; every test asserts the
/// app sent reads only.

class _Adapter implements HttpClientAdapter {
  _Adapter(this.responder);
  final Future<ResponseBody> Function(RequestOptions o) responder;
  final List<RequestOptions> requests = [];
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<List<int>>? s,
    Future<void>? c,
  ) {
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

Map<String, dynamic> _kid(String id, String first, String klass, String sec) =>
    {
      'studentId': id,
      'firstName': first,
      'lastName': 'Synthetic',
      'className': klass,
      'sectionName': '$klass-$sec',
      'sectionId': 'sec-$id',
      'academicYearId': 'ay-1',
    };

final _guardian = {
  'guardianId': 'g-1',
  'firstName': 'Parent',
  'lastName': 'Synthetic',
  'students': [
    _kid('st-1', 'Bilal', 'Class 9', 'C'),
    _kid('st-2', 'Fatima', 'Class 7', 'A'),
  ],
};

Map<String, dynamic> _today(String id, String? status) => {
  'studentId': id,
  'date': '2026-08-11',
  'attendanceStatus': status,
};

Map<String, dynamic> _history(List<List<String>> rows) => {
  'content': [
    for (final r in rows) {'attendance_date': r[0], 'status': r[1]},
  ],
};

/// Bilal is absent today, Fatima present; histories differ per child.
_Adapter _family({Completer<void>? holdBilal}) => _Adapter((o) async {
  if (o.path == ApiConfig.guardiansMePath) return _json(200, _guardian);
  if (o.path.contains(ApiConfig.parentProgressPath)) {
    if (o.path.endsWith('st-1')) {
      if (holdBilal != null) await holdBilal.future;
      return _json(200, _today('st-1', 'absent'));
    }
    return _json(200, _today('st-2', 'present'));
  }
  if (o.path.endsWith('st-1')) {
    return _json(
      200,
      _history([
        ['2026-08-10', 'absent'],
      ]),
    );
  }
  return _json(
    200,
    _history([
      ['2026-08-11', 'present'],
      ['2026-08-10', 'late'],
      ['2026-08-09', 'absent'],
      ['2026-08-08', 'leave'],
      ['2026-08-07', 'excused'],
    ]),
  );
});

ParentRepository _repo(_Adapter a) => ParentRepository(
  Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))..httpClientAdapter = a,
);

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light(role: AppRole.parent),
  home: child,
);

void _onlyReads(_Adapter a) => expect(
  a.requests.map((r) => r.method).toSet(),
  {'GET'},
  reason: 'the parent portal never mutates anything',
);

Future<void> _tab(WidgetTester tester, [int n = 1]) async {
  for (var i = 0; i < n; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
  }
}

String? _focusedLabel(WidgetTester tester) {
  final node = FocusManager.instance.primaryFocus;
  final ctx = node?.context;
  if (ctx == null) return null;
  final sem = tester.getSemantics(find.byElementPredicate((e) => e == ctx));
  return sem.label;
}

void main() {
  const child = GuardianChild(
    studentId: 'st-2',
    fullName: 'Fatima Synthetic',
    sectionId: 'sec-st-2',
    className: 'Class 7',
    sectionName: 'Class 7-A',
  );

  group('Responsive (no overflow)', () {
    for (final w in [320.0, 390.0, 768.0, 1024.0, 1440.0]) {
      testWidgets('home overview, one child and attendance at ${w.toInt()}px', (
        tester,
      ) async {
        tester.view.physicalSize = Size(w, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final a = _family();
        await tester.pumpWidget(_host(ParentHomeScreen(repository: _repo(a))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('open-st-2')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.bySemanticsLabel('View attendance history'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(StatusPill), findsNWidgets(5));
        _onlyReads(a);
      });
    }
  });

  group('Child switcher', () {
    testWidgets('chips announce name + class and the selected state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(ParentHomeScreen(repository: _repo(_family()))),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.bySemanticsLabel('All children')),
        isSemantics(
          label: 'All children',
          isButton: true,
          isSelected: true,
          isFocusable: true,
          hasTapAction: true,
        ),
      );
      expect(
        find.bySemanticsLabel('Bilal Synthetic, Class 9 · C'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Fatima Synthetic, Class 7 · A'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('chips are at least 48 px tall (touch)', (tester) async {
      await tester.pumpWidget(
        _host(ParentHomeScreen(repository: _repo(_family()))),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.bySemanticsLabel('All children')).height,
        greaterThanOrEqualTo(48),
      );
      // Natural width (never stretched) with the label vertically centred.
      final chip = tester.getRect(find.bySemanticsLabel('All children'));
      expect(chip.width, lessThan(300));
      final label = tester.getRect(find.text('All children'));
      expect((label.center.dy - chip.center.dy).abs(), lessThan(1));
    });

    testWidgets('keyboard: Tab walks All, Bilal, Fatima; Enter selects', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final a = _family();
      await tester.pumpWidget(_host(ParentHomeScreen(repository: _repo(a))));
      await tester.pumpAndSettle();
      await _tab(tester);
      expect(_focusedLabel(tester), 'All children');
      await _tab(tester);
      expect(_focusedLabel(tester), 'Bilal Synthetic, Class 9 · C');
      await _tab(tester);
      expect(_focusedLabel(tester), 'Fatima Synthetic, Class 7 · A');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overview-st-1')), findsNothing);
      expect(
        tester
                .getSemantics(
                  find.bySemanticsLabel('Fatima Synthetic, Class 7 · A'),
                )
                .flagsCollection
                .isSelected ==
            Tristate.isTrue,
        isTrue,
      );
      // Space returns to All children.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(_focusedLabel(tester), 'All children');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overview-st-1')), findsOneWidget);
      _onlyReads(a);
      handle.dispose();
    });

    testWidgets('overview card has a real "View <name> only" button', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(ParentHomeScreen(repository: _repo(_family()))),
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('View Bilal Synthetic only'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('open-st-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overview-st-2')), findsNothing);
      expect(find.text('Bilal Synthetic'), findsWidgets);
      handle.dispose();
    });
  });

  group('Privacy: no data crosses between children', () {
    testWidgets('while the new child loads, the previous child\'s status is '
        'not shown under the new name', (tester) async {
      final hold = Completer<void>();
      final a = _family(holdBilal: hold);
      await tester.pumpWidget(_host(ParentHomeScreen(repository: _repo(a))));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.tap(find.byKey(const Key('open-st-2'))); // Fatima: present
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<StatusPill>(find.byType(StatusPill))
            .map((p) => p.status),
        [AppStatus.present],
      );
      // Switch to Bilal (answer held): Fatima's "present" must disappear.
      await tester.tap(find.bySemanticsLabel('Bilal Synthetic, Class 9 · C'));
      await tester.pump();
      expect(find.byType(StatusPill), findsNothing);
      hold.complete();
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<StatusPill>(find.byType(StatusPill))
            .map((p) => p.status),
        [AppStatus.absent],
      );
    });

    testWidgets('history opens for the CURRENT child only', (tester) async {
      final a = _family();
      await tester.pumpWidget(_host(ParentHomeScreen(repository: _repo(a))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-st-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Fatima Synthetic, Class 7 · A'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('View attendance history'));
      await tester.pumpAndSettle();
      final history = a.requests.where(
        (r) => r.path.startsWith(ApiConfig.attendanceStudentPath),
      );
      expect(history.map((r) => r.path.split('/').last), ['st-2']);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('attendance-child-name')))
            .data,
        'Fatima Synthetic',
      );
      expect(find.byType(StatusPill), findsNWidgets(5));
      _onlyReads(a);
    });
  });

  group('Child Attendance', () {
    testWidgets('identity, class and the exact requested period', (
      tester,
    ) async {
      final a = _family();
      await tester.pumpWidget(
        _host(
          ChildAttendanceScreen(
            repository: _repo(a),
            child: child,
            now: () => DateTime(2026, 8, 11, 9),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Fatima Synthetic'), findsOneWidget);
      expect(find.text('Class 7 · A'), findsOneWidget);
      expect(
        find.text('Last 30 days · Jul 12, 2026 – Aug 11, 2026'),
        findsOneWidget,
      );
      final req = a.requests.single;
      expect(req.queryParameters, {'from': '2026-07-12', 'to': '2026-08-11'});
      _onlyReads(a);
    });

    testWidgets('every server status, one spoken node per day, no derived '
        'statistics', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          ChildAttendanceScreen(
            repository: _repo(_family()),
            child: child,
            now: () => DateTime(2026, 8, 11),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in [
        'Tuesday, Aug 11, 2026: Present',
        'Monday, Aug 10, 2026: Late',
        'Sunday, Aug 9, 2026: Absent',
        'Saturday, Aug 8, 2026: Leave',
        'Friday, Aug 7, 2026: Excused',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      expect(find.textContaining('%'), findsNothing);
      // Raw ISO never shown.
      expect(find.textContaining('2026-08'), findsNothing);
      handle.dispose();
    });

    testWidgets('a load failure offers a working retry; nothing is invented', (
      tester,
    ) async {
      var fail = true;
      final a = _Adapter((o) async {
        if (fail) return _json(500, {'status': 500, 'message': 'x'});
        return _json(
          200,
          _history([
            ['2026-08-11', 'present'],
          ]),
        );
      });
      await tester.pumpWidget(
        _host(
          ChildAttendanceScreen(
            repository: _repo(a),
            child: child,
            now: () => DateTime(2026, 8, 11),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(StatusPill), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(StatusPill), findsOneWidget);
      _onlyReads(a);
    });

    testWidgets('history column is capped on wide screens', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          ChildAttendanceScreen(
            repository: _repo(_family()),
            child: child,
            now: () => DateTime(2026, 8, 11),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getSize(find.bySemanticsLabel('Tuesday, Aug 11, 2026: Present'))
            .width,
        lessThanOrEqualTo(ChildAttendanceScreen.maxContentWidth),
      );
    });
  });
}
