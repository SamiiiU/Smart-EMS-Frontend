import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/api_config.dart';
import 'package:smartems/core/network/campus_filter_interceptor.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/features/academy/data/academy_repository.dart';
import 'package:smartems/features/academy/presentation/academy_today_panel.dart';
import 'package:smartems/features/academy/presentation/session_attendance_screen.dart';

/// Report 11 A-2: Teacher Today lists the teacher's own dated Academy
/// sessions (server: GET /api/academy/sessions/mine; assignment, campus and
/// mark rules are enforced and tested server-side in AcademyTests).
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

Map<String, dynamic> _row(
  String id,
  String course,
  String start,
  String end, {
  String status = 'scheduled',
  bool canMark = true,
  int marked = 0,
  int learners = 2,
  String campus = 'c1',
}) => {
  'id': id,
  'batch_id': 'b-$course',
  'session_date': '2026-10-15',
  'start_time': '$start:00',
  'end_time': '$end:00',
  'room': 'Lab 1',
  'status': status,
  'batch_name': '$course A',
  'course_name': course,
  'campus_id': campus,
  'active_learners': learners,
  'marked': marked,
  'can_mark': canMark,
};

class _Campus extends ChangeNotifier {
  String? selected;
  void select(String? id) {
    selected = id;
    notifyListeners();
  }
}

Future<_Adapter> _pump(
  WidgetTester tester,
  ResponseBody Function(RequestOptions) responder, {
  _Campus? campus,
}) async {
  final a = _Adapter(responder);
  final dio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))
    ..httpClientAdapter = a;
  if (campus != null) {
    dio.interceptors.add(
      CampusFilterInterceptor(selectedCampus: () => campus.selected),
    );
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(role: AppRole.teacher),
      home: Scaffold(
        body: ListView(
          children: [
            AcademyTodayPanel(
              repository: AcademyRepository(dio),
              campusChanges: campus,
              now: () => DateTime(2026, 10, 15, 10, 30),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return a;
}

void main() {
  testWidgets(
    'several sessions: upcoming, in progress, ended and cancelled; only markable ones open',
    (tester) async {
      await _pump(
        tester,
        (o) => _json(200, {
          'date': '2026-10-15',
          'sessions': [
            _row(
              's1',
              'Mathematics',
              '08:00',
              '09:00',
              status: 'held',
              marked: 2,
            ),
            _row('s2', 'Physics', '10:00', '11:00'),
            _row(
              's3',
              'Chemistry',
              '12:00',
              '13:00',
              status: 'cancelled',
              canMark: false,
            ),
            _row(
              's4',
              'Biology',
              '15:00',
              '16:00',
              canMark: false,
            ), // no attendance.mark on campus
          ],
        }),
      );
      expect(find.text('Course sessions today'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp(
            '^Mathematics · Mathematics A, 08:00–09:00 · Lab 1, Ended, Marked 2 of 2',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(
            '^Physics · Physics A, 10:00–11:00 · Lab 1, In progress, Marked 0 of 2',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(
            r'^Chemistry · Chemistry A, .*Cancelled, No attendance \(cancelled\)',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp('^Biology · Biology A, 15:00–16:00 · Lab 1, Upcoming'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('academy-today-open-s1')), findsOneWidget);
      expect(find.byKey(const Key('academy-today-open-s2')), findsOneWidget);
      expect(
        find.byKey(const Key('academy-today-open-s3')),
        findsNothing,
        reason: 'cancelled',
      );
      expect(
        find.byKey(const Key('academy-today-open-s4')),
        findsNothing,
        reason: 'server says not markable',
      );
      expect(
        find.bySemanticsLabel('Take attendance, Physics · Physics A, 10:00'),
        findsOneWidget,
      );
    },
  );

  testWidgets('empty day says so (no fabricated sessions)', (tester) async {
    await _pump(
      tester,
      (o) => _json(200, {'date': '2026-10-15', 'sessions': <Object>[]}),
    );
    expect(
      find.text('No course sessions scheduled for you today.'),
      findsOneWidget,
    );
    expect(find.text('Take attendance'), findsNothing);
  });

  testWidgets('a failure is an error with a retry, never an empty day', (
    tester,
  ) async {
    var fail = true;
    final a = await _pump(
      tester,
      (o) => fail
          ? _json(409, {'status': 409, 'message': 'ACADEMY_DISABLED'})
          : _json(200, {
              'date': '2026-10-15',
              'sessions': [_row('s2', 'Physics', '10:00', '11:00')],
            }),
    );
    expect(find.text('Could not load course sessions.'), findsOneWidget);
    expect(
      find.text('No course sessions scheduled for you today.'),
      findsNothing,
    );
    fail = false;
    await tester.tap(find.bySemanticsLabel('Retry course sessions'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('academy-today-open-s2')), findsOneWidget);
    expect(a.requests, hasLength(2));
  });

  testWidgets('campus switch reloads for the active campus only', (
    tester,
  ) async {
    final campus = _Campus()..selected = 'c1';
    final a = await _pump(tester, (o) {
      final c = o.queryParameters['campusId'];
      return _json(200, {
        'date': '2026-10-15',
        'sessions': [
          if (c == 'c1')
            _row('s1', 'Mathematics', '08:00', '09:00', campus: 'c1')
          else
            _row('n1', 'North Physics', '09:00', '10:00', campus: 'c2'),
        ],
      });
    }, campus: campus);
    expect(a.requests.single.queryParameters['campusId'], 'c1');
    expect(find.byKey(const Key('academy-today-open-s1')), findsOneWidget);
    campus.select('c2');
    await tester.pumpAndSettle();
    expect(a.requests.last.queryParameters['campusId'], 'c2');
    expect(
      find.byKey(const Key('academy-today-open-s1')),
      findsNothing,
      reason: 'no cross-campus leftovers',
    );
    expect(find.byKey(const Key('academy-today-open-n1')), findsOneWidget);
    expect(find.textContaining('Mathematics'), findsNothing);
  });

  testWidgets(
    'Take attendance opens the online-only session sheet and reloads on return',
    (tester) async {
      final a = await _pump(tester, (o) {
        if (o.path == '/api/academy/sessions/mine') {
          return _json(200, {
            'date': '2026-10-15',
            'sessions': [_row('s2', 'Physics', '10:00', '11:00')],
          });
        }
        return _json(200, {'session': {}, 'learners': <Object>[]});
      });
      await tester.tap(find.byKey(const Key('academy-today-open-s2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(SessionAttendanceScreen), findsOneWidget);
      expect(
        a.requests.where((r) => r.method != 'GET'),
        isEmpty,
        reason: 'opening never submits anything',
      );
      Navigator.of(tester.element(find.byType(SessionAttendanceScreen))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        a.requests.where((r) => r.path == '/api/academy/sessions/mine'),
        hasLength(2),
      );
    },
  );
}
