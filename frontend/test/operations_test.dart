import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/shell/app_shell.dart';
import 'package:smartems/core/shell/bottom_nav.dart';
import 'package:smartems/core/shell/nav_destination.dart';
import 'package:smartems/core/shell/phone_nav_drawer.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/status_pill.dart';
import 'package:smartems/features/notifications/data/notifications_repository.dart';
import 'package:smartems/features/notifications/domain/notification_models.dart';
import 'package:smartems/features/notifications/presentation/notifications_screen.dart';
import 'package:smartems/features/staff_attendance/data/staff_attendance_repository.dart';
import 'package:smartems/features/staff_attendance/domain/staff_attendance_models.dart';
import 'package:smartems/features/staff_attendance/presentation/staff_attendance_screen.dart';

class _OpsServer implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  String notificationsJson = '[]';
  String dayJson = '{"date":"2026-09-27","totalStaff":0,"unmarked":0,'
      '"present":0,"absent":0,"records":[]}';
  int marked = 0;
  Object? lastBody;

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    requests.add(o);
    final path = o.uri.path;

    if (path == '/api/notifications') {
      return _raw(200, '{"content":$notificationsJson}');
    }
    if (path == '/api/notifications/unread-count') {
      return _raw(200, '{"unreadCount":2}');
    }
    if (path == '/api/notifications/read-all') {
      return _raw(200, '{"marked":$marked,"status":"ok"}');
    }
    if (path.startsWith('/api/notifications/')) return _raw(200, '{}');
    if (path == '/api/staff-attendance/daily') return _raw(200, dayJson);
    if (path == '/api/staff-attendance') {
      lastBody = o.data;
      return _raw(201, '{"ok":true}');
    }
    return _raw(404, '{"message":"no route"}');
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _raw(int status, String json) => ResponseBody.fromBytes(
      utf8.encode(json),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

typedef _Wired = ({Dio dio, _OpsServer server});

_Wired _wire() {
  final server = _OpsServer();
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = server;
  return (dio: dio, server: server);
}

Widget _host(Widget child, {bool dark = false}) => MaterialApp(
      theme: dark
          ? AppTheme.dark(role: AppRole.admin)
          : AppTheme.light(role: AppRole.admin),
      home: child,
    );

void main() {
  group('notifications', () {
    testWidgets('it admits a notification cannot be opened', (tester) async {
      final w = _wire();
      w.server.notificationsJson = '[{"id":"n1","title":"Fee due",'
          '"body":"Invoice for July","category":"fee","priority":"medium",'
          '"createdAt":"2026-09-26T10:00:00Z","readAt":null}]';

      await tester.pumpWidget(_host(NotificationsScreen(
        repository: NotificationsRepository(w.dio),
      )));
      await tester.pumpAndSettle();

      // `data` is null on every row the live API produces and no target id
      // exists, so tapping through would be a fabricated affordance (D-19).
      expect(
        find.textContaining('cannot be opened yet'),
        findsOneWidget,
      );
      expect(find.text('Fee due'), findsOneWidget);
    });

    testWidgets('unread is carried by a word, not only by colour',
        (tester) async {
      final w = _wire();
      w.server.notificationsJson = '[{"id":"n1","title":"Fee due",'
          '"body":"x","category":"fee","priority":"medium",'
          '"createdAt":"2026-09-26T10:00:00Z","readAt":null}]';

      await tester.pumpWidget(_host(NotificationsScreen(
        repository: NotificationsRepository(w.dio),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Unread'), findsOneWidget);
      expect(find.text('Mark read'), findsOneWidget);
    });

    testWidgets('a read notification offers no mark-read action',
        (tester) async {
      final w = _wire();
      w.server.notificationsJson = '[{"id":"n1","title":"Fee due",'
          '"body":"x","category":"fee","priority":"medium",'
          '"createdAt":"2026-09-26T10:00:00Z",'
          '"readAt":"2026-09-26T11:00:00Z"}]';

      await tester.pumpWidget(_host(NotificationsScreen(
        repository: NotificationsRepository(w.dio),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Mark read'), findsNothing);
      expect(find.text('Mark all as read'), findsNothing);
    });

    testWidgets('mark-all reports the SERVER’s count', (tester) async {
      final w = _wire();
      w.server.marked = 7;
      w.server.notificationsJson = '[{"id":"n1","title":"A","body":"x",'
          '"category":"fee","priority":"medium","createdAt":"z",'
          '"readAt":null}]';

      await tester.pumpWidget(_host(NotificationsScreen(
        repository: NotificationsRepository(w.dio),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mark all as read'));
      await tester.pumpAndSettle();

      // Not "1", which is what was on screen — the server knows better.
      expect(find.text('7 notifications marked as read.'), findsOneWidget);
    });

    test('grouping puts the group with unread first', () {
      final rows = [
        AppNotification.fromJson(const {
          'id': 'a',
          'title': 'Read one',
          'body': '',
          'category': 'attendance',
          'createdAt': '2026-09-26',
          'readAt': '2026-09-26',
        }),
        AppNotification.fromJson(const {
          'id': 'b',
          'title': 'Unread one',
          'body': '',
          'category': 'fee',
          'createdAt': '2026-09-25',
          'readAt': null,
        }),
      ];

      final groups = groupNotifications(rows);
      // Fifty attendance notices must not bury one fee notice.
      expect(groups.first.label, 'Fees');
      expect(groups.first.unreadCount, 1);
    });

    test('an unknown category is shown, never dropped', () {
      final n = AppNotification.fromJson(const {
        'id': 'a',
        'title': 't',
        'body': '',
        'category': 'something_new',
        'createdAt': 'z',
      });
      expect(n.categoryLabel, 'something_new');
    });
  });

  group('staff attendance', () {
    testWidgets('the whole roster arrives in one call', (tester) async {
      final w = _wire();
      w.server.dayJson = '{"date":"2026-09-27","totalStaff":2,"unmarked":1,'
          '"present":1,"absent":0,"records":['
          '{"staff_id":"s1","first_name":"Ayesha","last_name":"Khan",'
          '"employee_code":"EMP-002","status":"present"},'
          '{"staff_id":"s2","first_name":"Bilal","last_name":"Ahmed",'
          '"employee_code":"EMP-003","status":"unmarked"}]}';

      await tester.pumpWidget(_host(StaffAttendanceScreen(
        repository: StaffAttendanceRepository(w.dio),
        today: DateTime(2026, 9, 27),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Ayesha Khan'), findsOneWidget);
      expect(find.text('Bilal Ahmed'), findsOneWidget);
      // One call, not the two-call join students need.
      expect(
        w.server.requests.where((r) => r.path.contains('daily')).length,
        1,
      );
    });

    testWidgets('the summary uses the SERVER’s counts', (tester) async {
      final w = _wire();
      w.server.dayJson = '{"date":"2026-09-27","totalStaff":40,"unmarked":38,'
          '"present":2,"absent":0,"records":['
          '{"staff_id":"s1","first_name":"A","last_name":"B",'
          '"employee_code":"E","status":"present"}]}';

      await tester.pumpWidget(_host(StaffAttendanceScreen(
        repository: StaffAttendanceRepository(w.dio),
        today: DateTime(2026, 9, 27),
      )));
      await tester.pumpAndSettle();

      // 40 staff even though one record is loaded: the header cannot
      // disagree with the server by counting the list itself.
      expect(find.text('2 of 40 marked'), findsOneWidget);
      expect(find.text('38 left'), findsOneWidget);
    });

    testWidgets('an unmarked member says so — it is not a status',
        (tester) async {
      final w = _wire();
      w.server.dayJson = '{"date":"2026-09-27","totalStaff":1,"unmarked":1,'
          '"present":0,"absent":0,"records":['
          '{"staff_id":"s1","first_name":"A","last_name":"B",'
          '"employee_code":"E","status":"unmarked"}]}';

      await tester.pumpWidget(_host(StaffAttendanceScreen(
        repository: StaffAttendanceRepository(w.dio),
        today: DateTime(2026, 9, 27),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Not marked'), findsOneWidget);
    });

    testWidgets('marking sends the wire value and a UUID idempotency key',
        (tester) async {
      final w = _wire();
      w.server.dayJson = '{"date":"2026-09-27","totalStaff":1,"unmarked":1,'
          '"present":0,"absent":0,"records":['
          '{"staff_id":"s1","first_name":"A","last_name":"B",'
          '"employee_code":"E","status":"unmarked"}]}';

      await tester.pumpWidget(_host(StaffAttendanceScreen(
        repository: StaffAttendanceRepository(w.dio),
        today: DateTime(2026, 9, 27),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Half day'));
      await tester.pumpAndSettle();

      final body = w.server.lastBody! as Map;
      expect(body['status'], 'half_day');
      expect(body['attendanceDate'], '2026-09-27');
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
                r'[0-9a-f]{12}$')
            .hasMatch(body['clientUuid'] as String),
        isTrue,
      );
    });

    test('the staff vocabulary is NOT the student one', () {
      // Four shared values, one different each way. Sharing an enum would
      // compile and then send a status the server rejects.
      expect(
        StaffAttendanceStatus.values.map((s) => s.wire),
        ['present', 'absent', 'late', 'leave', 'half_day'],
      );
      expect(
        StaffAttendanceStatus.values.map((s) => s.wire).contains('excused'),
        isFalse,
      );
    });

    test('`unmarked` is the absence of a status, not one of them', () {
      expect(StaffAttendanceStatus.parse('unmarked'), isNull);
      expect(StaffAttendanceStatus.parse('half_day'),
          StaffAttendanceStatus.halfDay);
    });

    test('half day keeps D-21 — colour, letter AND shape', () {
      expect(AppStatus.halfDay.isAttendance, isTrue);
      expect(StatusPill.letterFor(AppStatus.halfDay), 'H');
      expect(StatusPill.shapeFor(AppStatus.halfDay), isNotNull);
    });

    testWidgets('a choice announces what it will do', (tester) async {
      final w = _wire();
      w.server.dayJson = '{"date":"2026-09-27","totalStaff":1,"unmarked":1,'
          '"present":0,"absent":0,"records":['
          '{"staff_id":"s1","first_name":"Ayesha","last_name":"Khan",'
          '"employee_code":"E","status":"unmarked"}]}';

      await tester.pumpWidget(_host(StaffAttendanceScreen(
        repository: StaffAttendanceRepository(w.dio),
        today: DateTime(2026, 9, 27),
      )));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Mark Ayesha Khan Half day'),
        findsOneWidget,
      );
    });
  });

  group('D-27 amendment — the admin phone drawer', () {
    List<NavDestination> nine() => [
          for (var i = 0; i < 9; i++)
            NavDestination(
              id: 'd$i',
              label: 'Destination $i',
              icon: Icons.circle_outlined,
              route: '/d$i',
              builder: (_) => Text('screen $i'),
            ),
        ];

    testWidgets('admin gets a drawer with EVERY destination on a phone',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final destinations = nine();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(role: AppRole.admin),
        home: AppShell(
          institutionName: 'Test',
          destinations: destinations,
          entitledIds: destinations.map((d) => d.id).toSet(),
          usePhoneDrawer: true,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();

      expect(find.byType(PhoneNavDrawer), findsOneWidget);
      // Nothing is truncated — the failure that put Import out of reach.
      for (var i = 0; i < 9; i++) {
        expect(find.text('Destination $i'), findsWidgets,
            reason: 'destination $i must be reachable');
      }
    });

    testWidgets('the other roles keep the bottom bar, unchanged',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final destinations = nine();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(role: AppRole.teacher),
        home: AppShell(
          institutionName: 'Test',
          destinations: destinations,
          entitledIds: destinations.map((d) => d.id).toSet(),
          // usePhoneDrawer defaults to false — D-27 as written.
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(PhoneNavDrawer), findsNothing);
      expect(find.byType(BottomNav), findsOneWidget);
      // D-27 as written: three destinations plus More, not all nine.
      expect(find.byTooltip('Open navigation menu'), findsNothing);
    });

    testWidgets('choosing from the drawer switches tab and closes it',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final destinations = nine();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(role: AppRole.admin),
        home: AppShell(
          institutionName: 'Test',
          destinations: destinations,
          entitledIds: destinations.map((d) => d.id).toSet(),
          usePhoneDrawer: true,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Destination 5').last);
      await tester.pumpAndSettle();

      // Closed, so it does not cover what the tap just navigated to.
      expect(find.byType(PhoneNavDrawer), findsNothing);
    });

    testWidgets('a wide viewport still uses the sidebar, drawer flag or not',
        (tester) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final destinations = nine();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(role: AppRole.admin),
        home: AppShell(
          institutionName: 'Test',
          destinations: destinations,
          entitledIds: destinations.map((d) => d.id).toSet(),
          usePhoneDrawer: true,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(PhoneNavDrawer), findsNothing);
    });
  });

  group('both themes and no overflow', () {
    for (final dark in [false, true]) {
      testWidgets('operations screens render in ${dark ? 'dark' : 'light'}',
          (tester) async {
        final w = _wire();
        w.server.notificationsJson = '[{"id":"n1","title":"A","body":"x",'
            '"category":"fee","priority":"medium","createdAt":"z",'
            '"readAt":null}]';
        w.server.dayJson = '{"date":"2026-09-27","totalStaff":1,'
            '"unmarked":0,"present":1,"absent":0,"records":['
            '{"staff_id":"s1","first_name":"A","last_name":"B",'
            '"employee_code":"E","status":"present"}]}';

        for (final screen in <Widget>[
          NotificationsScreen(repository: NotificationsRepository(w.dio)),
          StaffAttendanceScreen(
            repository: StaffAttendanceRepository(w.dio),
            today: DateTime(2026, 9, 27),
          ),
        ]) {
          await tester.pumpWidget(_host(screen, dark: dark));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }

    for (final width in [360.0, 768.0, 1366.0]) {
      testWidgets('no operations screen overflows at ${width.toInt()}px',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final w = _wire();
        w.server.notificationsJson = '[{"id":"n1",'
            '"title":"A notification with a fairly long title",'
            '"body":"And a body that goes on for a while too",'
            '"category":"fee","priority":"medium","createdAt":"z",'
            '"readAt":null}]';
        w.server.dayJson = '{"date":"2026-09-27","totalStaff":1,'
            '"unmarked":1,"present":0,"absent":0,"records":['
            '{"staff_id":"s1","first_name":"Muhammad Abdul",'
            '"last_name":"Rehman","employee_code":"EMP-0001",'
            '"status":"unmarked"}]}';

        for (final screen in <Widget>[
          NotificationsScreen(repository: NotificationsRepository(w.dio)),
          StaffAttendanceScreen(
            repository: StaffAttendanceRepository(w.dio),
            today: DateTime(2026, 9, 27),
          ),
        ]) {
          await tester.pumpWidget(_host(screen));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  });
}
