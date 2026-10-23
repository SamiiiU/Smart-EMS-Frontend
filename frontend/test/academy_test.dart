import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartems/core/network/api_config.dart';
import 'package:smartems/core/shell/campus_context.dart';
import 'package:smartems/core/shell/identity_resolver.dart';
import 'package:smartems/core/shell/nav_destination.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/app_button.dart';
import 'package:smartems/core/widgets/states/screen_state.dart';
import 'package:smartems/features/academy/data/academy_repository.dart';
import 'package:smartems/features/academy/domain/academy_models.dart';
import 'package:smartems/features/academy/presentation/academy_navigation.dart';
import 'package:smartems/features/academy/presentation/assessment_screen.dart';
import 'package:smartems/features/academy/presentation/batch_fee_panel.dart';
import 'package:smartems/features/academy/presentation/batches_screen.dart';
import 'package:smartems/features/academy/presentation/courses_screen.dart';
import 'package:smartems/features/academy/presentation/learner_academy_screen.dart';
import 'package:smartems/features/academy/presentation/session_attendance_screen.dart';

/// Answers by "METHOD path"; records every request. Unknown routes → 404.
class _Server implements HttpClientAdapter {
  _Server(this.routes);
  final Map<String, Object Function(RequestOptions o)> routes;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<List<int>>? s,
    Future<void>? c,
  ) async {
    requests.add(o);
    final handler = routes['${o.method} ${o.path}'];
    if (handler == null) {
      return _body(404, {'status': 404, 'message': 'Not found'});
    }
    final r = handler(o);
    if (r is _Reply) return _body(r.status, r.body);
    if (r is DioException) throw r;
    return _body(200, r);
  }

  @override
  void close({bool force = false}) {}
}

class _Reply {
  const _Reply(this.status, this.body);
  final int status;
  final Object body;
}

/// Raw text, so decimals arrive exactly as the server writes them.
ResponseBody _body(int status, Object body) => ResponseBody.fromBytes(
  utf8.encode(body is String ? body : jsonEncode(body)),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

AcademyRepository _repo(_Server s, {List<String>? keys}) {
  var i = 0;
  return AcademyRepository(
    Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))..httpClientAdapter = s,
    newKey: keys == null ? null : () => keys[i++ % keys.length],
  );
}

Widget _app(Widget child, {CampusContext? campus}) => MaterialApp(
  theme: AppTheme.light(role: AppRole.admin),
  home: Scaffold(
    body: campus == null ? child : CampusScope(campus: campus, child: child),
  ),
);

Future<CampusContext> _campus(
  WidgetTester tester,
  List<Map<String, Object>> campuses, {
  bool all = false,
}) async {
  final s = _Server({
    'GET /api/campuses/mine': (_) => {'campuses': campuses, 'allCampuses': all},
  });
  final ctx = CampusContext(
    dio: Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))..httpClientAdapter = s,
  );
  await tester.runAsync(() => ctx.load(tenantId: 't', userId: 'u'));
  return ctx;
}

const _session = Session(
  id: 's1',
  batchId: 'b1',
  date: '2026-10-01',
  start: '16:00',
  end: '17:00',
  status: 'scheduled',
);

Map<String, Object> _sheet(List<List<String>> learners) => {
  'id': 's1',
  'batch_id': 'b1',
  'campus_id': 'c1',
  'session_date': '2026-10-01',
  'start_time': '16:00:00',
  'end_time': '17:00:00',
  'status': 'scheduled',
  'learners': [
    for (final l in learners)
      {
        'student_id': l[0],
        'first_name': l[1],
        'last_name': 'L',
        'admission_number': 'A',
        'status': l[2],
      },
  ],
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('repository contract', () {
    test('money and marks are decoded as exact strings, never doubles', () {
      final d =
          AcademyRepository.decode(
                '{"amount":4500.50,"max_marks":25.00,"marks":21.5,"count":3}',
              )
              as Map;
      expect(d['amount'], '4500.50');
      expect(d['max_marks'], '25.00');
      expect(d['marks'], '21.5');
      expect(d['count'], 3);
    });

    test('server codes become readable text; conflicts are itemised', () {
      expect(
        AcademyRepository.explain(
          const LoadFailure(
            message: 'WRONG_CAMPUS: learner belongs to a different campus',
          ),
        ),
        contains('own campus'),
      );
      expect(
        AcademyRepository.explain(
          const LoadFailure(message: 'Plain server text'),
        ),
        'Plain server text',
      );
      final c = AcademyRepository.conflicts(
        const LoadFailure(
          message:
              'SESSION_CONFLICT: BATCH_OVERLAP; INSTRUCTOR_BUSY:x; ROOM_BUSY:Lab 2',
        ),
      );
      expect(c, hasLength(3));
      expect(c.last, contains('Lab 2'));
    });

    test('enroll retries reuse the caller\'s idempotency key', () async {
      final s = _Server({
        'POST /api/academy/batches/b1/enrollments': (o) => {
          'id': 'e1',
          'batch_id': 'b1',
          'student_id': 'st',
          'status': 'active',
          'enrolled_on': '2026-10-01',
          'idempotentReplay':
              (o.data as Map)['idempotencyKey'] == 'k-1' && s0 > 0,
        },
      });
      final repo = _repo(s);
      final first = await repo.enroll('b1', 'st', 'k-1');
      s0++;
      final again = await repo.enroll('b1', 'st', 'k-1');
      expect(first.replay, isFalse);
      expect(again.replay, isTrue);
      expect(
        [for (final r in s.requests) (r.data as Map)['idempotencyKey']],
        ['k-1', 'k-1'],
      );
    });
  });

  group('navigation', () {
    final fakeRepo = AcademyRepository(Dio());
    IdentityResult id(List<String> roles, List<GrantScope> grants) =>
        IdentityResult(
          IdentityResultKind.linked,
          roles: roles,
          permissions: [for (final g in grants) ...g.permissions],
          grants: grants,
          permissionsKnown: true,
        );
    List<String> ids(List<NavDestination> d) => [for (final x in d) x.id];

    test(
      'a School institution gets no Academy entry; owners still get the profile screen',
      () {
        final owner = id(
          ['owner'],
          const [
            GrantScope(
              role: 'owner',
              campusId: null,
              permissions: ['campus.manage', 'academy.manage'],
            ),
          ],
        );
        expect(
          ids(
            academyDestinations(
              repository: fakeRepo,
              identity: owner,
              academyEnabled: false,
              personal: false,
              adminShell: true,
              teacherShell: false,
            ),
          ),
          ['institution_profile'],
        );
        expect(
          ids(
            academyDestinations(
              repository: fakeRepo,
              identity: owner,
              academyEnabled: true,
              personal: false,
              adminShell: true,
              teacherShell: false,
            ),
          ),
          ['institution_profile', 'academy'],
        );
      },
    );

    test(
      'finance-only and campus admins get no profile screen; finance gets no Academy hub',
      () {
        final finance = id(
          ['finance_staff'],
          const [
            GrantScope(
              role: 'finance_staff',
              campusId: 'c1',
              permissions: ['fee.manage'],
            ),
          ],
        );
        expect(
          academyDestinations(
            repository: fakeRepo,
            identity: finance,
            academyEnabled: true,
            personal: false,
            adminShell: true,
            teacherShell: false,
          ).map((d) => d.id).toList(),
          ['academy_fees'],
          reason:
              'B4.5: read-only finance entry only — no profile screen, no Academy hub',
        );
        final campusAdmin = id(
          ['campus_admin'],
          const [
            GrantScope(
              role: 'campus_admin',
              campusId: 'c1',
              permissions: ['campus.manage', 'academy.manage'],
            ),
          ],
        );
        expect(
          ids(
            academyDestinations(
              repository: fakeRepo,
              identity: campusAdmin,
              academyEnabled: true,
              personal: false,
              adminShell: true,
              teacherShell: false,
            ),
          ),
          ['academy'],
        );
      },
    );

    test('teachers get their batches; learners and guardians get Courses', () {
      final teacher = id(
        ['teacher'],
        const [
          GrantScope(
            role: 'teacher',
            campusId: null,
            permissions: ['attendance.mark'],
          ),
        ],
      );
      expect(
        ids(
          academyDestinations(
            repository: fakeRepo,
            identity: teacher,
            academyEnabled: true,
            personal: false,
            adminShell: false,
            teacherShell: true,
          ),
        ),
        ['academy'],
      );
      final parent = id(['parent'], const []);
      expect(
        ids(
          academyDestinations(
            repository: fakeRepo,
            identity: parent,
            academyEnabled: true,
            personal: true,
            adminShell: false,
            teacherShell: false,
          ),
        ),
        ['courses'],
      );
      expect(
        academyDestinations(
          repository: fakeRepo,
          identity: parent,
          academyEnabled: false,
          personal: true,
          adminShell: false,
          teacherShell: false,
        ),
        isEmpty,
      );
    });

    test('extras are inserted before More and never duplicated', () {
      NavDestination d(String id) => NavDestination(
        id: id,
        label: id,
        icon: Icons.circle,
        route: '/$id',
        builder: (_) => const SizedBox(),
      );
      expect(
        ids(withDestinations([d('a'), d('more')], [d('academy'), d('a')])),
        ['a', 'academy', 'more'],
      );
    });
  });

  group('session attendance (online-only)', () {
    testWidgets(
      'unmarked learners are listed separately and nothing is defaulted',
      (tester) async {
        final s = _Server({
          'GET /api/academy/sessions/s1/attendance': (_) => _sheet([
            ['a', 'Ayesha', 'present'],
            ['b', 'Bilal', 'unmarked'],
          ]),
        });
        await tester.pumpWidget(
          _app(
            SessionAttendanceScreen(
              repository: _repo(s),
              session: _session,
              title: 'Maths',
              isOnline: () async => true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Unmarked (1)'), findsOneWidget);
        expect(find.text('Marked (1)'), findsOneWidget);
        expect(
          find.text('No changes'),
          findsOneWidget,
          reason: 'untouched learners are not submitted',
        );
      },
    );

    testWidgets(
      'offline: submission disabled with an explanation, no request sent',
      (tester) async {
        final s = _Server({
          'GET /api/academy/sessions/s1/attendance': (_) => _sheet([
            ['b', 'Bilal', 'unmarked'],
          ]),
        });
        await tester.pumpWidget(
          _app(
            SessionAttendanceScreen(
              repository: _repo(s),
              session: _session,
              title: 'Maths',
              isOnline: () async => false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('online-only'), findsWidgets);
        await tester.tap(find.text('Present'));
        await tester.pump();
        final submit = tester.widget<AppButton>(
          find.byKey(const ValueKey('academy-attendance-submit')),
        );
        expect(submit.onPressed, isNull);
        expect(s.requests.where((r) => r.method == 'POST'), isEmpty);
      },
    );

    testWidgets(
      'a dropped connection keeps the clientUuid; the retry replays instead of duplicating',
      (tester) async {
        var attempts = 0;
        late _Server s;
        s = _Server({
          'GET /api/academy/sessions/s1/attendance': (_) => _sheet([
            ['b', 'Bilal', attempts > 1 ? 'present' : 'unmarked'],
          ]),
          'POST /api/academy/sessions/s1/attendance': (o) {
            attempts++;
            if (attempts == 1) {
              return DioException(
                requestOptions: o,
                type: DioExceptionType.connectionError,
              );
            }
            final row = ((o.data as Map)['rows'] as List).single as Map;
            return {
              'successCount': 1,
              'errorCount': 0,
              'results': [
                {
                  'clientUuid': row['clientUuid'],
                  'studentId': 'b',
                  'outcome': 'replayed',
                  'eventId': 'e',
                },
              ],
            };
          },
        });
        await tester.pumpWidget(
          _app(
            SessionAttendanceScreen(
              repository: _repo(s, keys: ['op-1', 'op-2']),
              session: _session,
              title: 'Maths',
              isOnline: () async => true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Present'));
        await tester.pump();
        await tester.tap(find.text('Submit 1 change'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('not known whether'),
          findsOneWidget,
          reason: 'never a false success',
        );
        await tester.tap(find.text('Submit 1 change'));
        await tester.pumpAndSettle();
        final posted = [
          for (final r in s.requests.where((r) => r.method == 'POST'))
            (((r.data as Map)['rows'] as List).single as Map)['clientUuid'],
        ];
        expect(posted, ['op-1', 'op-1']);
        expect(find.text('Saved 1 mark.'), findsOneWidget);
        expect(
          (s.requests.where((r) => r.method == 'POST').last.data
              as Map)['source'],
          'app',
        );
      },
    );

    testWidgets('a rejected row is highlighted and not reported as saved', (
      tester,
    ) async {
      final s = _Server({
        'GET /api/academy/sessions/s1/attendance': (_) => _sheet([
          ['b', 'Bilal', 'unmarked'],
        ]),
        'POST /api/academy/sessions/s1/attendance': (o) => {
          'successCount': 0,
          'errorCount': 1,
          'results': [
            {
              'clientUuid': 'x',
              'studentId': 'b',
              'outcome': 'rejected',
              'errorCode': 'NOT_ENROLLED',
            },
          ],
        },
      });
      await tester.pumpWidget(
        _app(
          SessionAttendanceScreen(
            repository: _repo(s),
            session: _session,
            title: 'Maths',
            isOnline: () async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Absent'));
      await tester.pump();
      await tester.tap(find.text('Submit 1 change'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Saved 0; 1 not saved'), findsOneWidget);
      expect(find.textContaining('Not an active member'), findsOneWidget);
    });
  });

  group('assessments', () {
    testWidgets('published assessment is read-only with no Save/Publish', (
      tester,
    ) async {
      final s = _Server({
        'GET /api/academy/assessments/a1/marks': (_) =>
            '{"id":"a1","batch_id":"b1","title":"Unit 1","max_marks":25.00,"assessed_on":"2026-10-01","status":"published",'
            '"marks":[{"student_id":"b","first_name":"Bilal","last_name":"L","marks":21.50,"absent":false}]}',
        'GET /api/academy/batches/b1/roster': (_) => [
          {
            'enrollment_id': 'e',
            'student_id': 'b',
            'first_name': 'Bilal',
            'last_name': 'L',
            'admission_number': 'A',
            'enrolled_on': '2026-09-01',
          },
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(role: AppRole.admin),
          home: MarksScreen(
            repository: _repo(s),
            assessmentId: 'a1',
            canPublish: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('read-only'), findsOneWidget);
      expect(
        find.text('21.50'),
        findsOneWidget,
        reason: 'exact decimal, not 21.5',
      );
      expect(find.text('Save marks'), findsNothing);
      expect(find.text('Publish'), findsNothing);
    });

    testWidgets(
      'draft: teacher without publish rights sees why; marks above maximum are flagged',
      (tester) async {
        final s = _Server({
          'GET /api/academy/assessments/a1/marks': (_) =>
              '{"id":"a1","batch_id":"b1","title":"Unit 1","max_marks":25,"assessed_on":"2026-10-01","status":"draft","marks":[]}',
          'GET /api/academy/batches/b1/roster': (_) => [
            {
              'enrollment_id': 'e',
              'student_id': 'b',
              'first_name': 'Bilal',
              'last_name': 'L',
              'admission_number': 'A',
              'enrolled_on': '2026-09-01',
            },
          ],
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(role: AppRole.teacher),
            home: MarksScreen(
              repository: _repo(s),
              assessmentId: 'a1',
              canPublish: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('cannot see these marks until published'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Publishing needs an administrator'),
          findsOneWidget,
        );
        await tester.enterText(find.byKey(const ValueKey('marks-b')), '30');
        await tester.pump();
        expect(find.text('More than 25'), findsOneWidget);
      },
    );

    testWidgets(
      'learners see published results only, even if a draft row slipped through',
      (tester) async {
        final s = _Server({
          'GET /api/students/me': (_) => {
            'id': 'st1',
            'firstName': 'Ayesha',
            'lastName': 'K',
          },
          'GET /api/academy/students/st1/enrollments': (_) => [
            {
              'id': 'e',
              'batch_id': 'b1',
              'batch_name': 'Evening A',
              'course_name': 'Mathematics',
              'student_id': 'st1',
              'status': 'active',
              'enrolled_on': '2026-09-01',
            },
            {
              'id': 'e2',
              'batch_id': 'b2',
              'batch_name': 'Weekend B',
              'course_name': 'Physics',
              'student_id': 'st1',
              'status': 'active',
              'enrolled_on': '2026-09-01',
            },
          ],
          'GET /api/academy/students/st1/attendance': (_) => [],
          'GET /api/academy/students/st1/results': (_) =>
              '[{"course_name":"Mathematics","batch_name":"A","title":"Published test","max_marks":25,"marks":20,"absent":false,"status":"published","assessed_on":"2026-10-01"},'
              '{"course_name":"Physics","batch_name":"B","title":"Secret draft","max_marks":25,"marks":5,"absent":false,"status":"draft","assessed_on":"2026-10-01"}]',
        });
        await tester.pumpWidget(
          _app(LearnerAcademyScreen(repository: _repo(s), isStudent: true)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Mathematics'), findsWidgets);
        expect(
          find.text('Physics'),
          findsWidgets,
          reason: 'two concurrent batches are both shown',
        );
        expect(find.text('Published test'), findsOneWidget);
        expect(find.text('Secret draft'), findsNothing);
      },
    );
  });

  group('fees', () {
    const batch = Batch(
      id: 'b1',
      name: 'ETP',
      status: 'open',
      campusId: 'c1',
      offeringId: 'o',
      offeringName: 'O',
      courseName: 'Entry Test',
      courseCode: 'ETP',
      startDate: '2026-09-01',
      endDate: '2026-12-31',
      activeLearners: 2,
    );

    testWidgets(
      'fee terms are fixed; a second generation reports nothing new instead of double billing',
      (tester) async {
        var runs = 0;
        final s = _Server({
          'GET /api/academy/batches/b1/fee': (_) =>
              '{"fee_head_name":"Tuition","amount":4500.50,"frequency":"monthly","due_day":5}',
          'POST /api/academy/batches/b1/fee/invoices': (_) => ++runs == 1
              ? {'billingKey': '2026-10', 'generated': 2, 'alreadyBilled': 0}
              : {'billingKey': '2026-10', 'generated': 0, 'alreadyBilled': 2},
        });
        await tester.pumpWidget(
          _app(BatchFeePanel(repository: _repo(s), batch: batch)),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('PKR 4,500.50'), findsOneWidget);
        expect(
          find.textContaining('PKR PKR'),
          findsNothing,
          reason: 'currency prefix appears once',
        );
        expect(
          find.text('Set fee'),
          findsNothing,
          reason: 'no overwrite of an existing price',
        );
        await tester.tap(find.text('Generate invoices'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Created 2 invoices'), findsOneWidget);
        await tester.tap(find.text('Generate invoices'));
        await tester.pumpAndSettle();
        expect(find.textContaining('already billed'), findsOneWidget);
      },
    );

    testWidgets('no fee yet offers Set fee', (tester) async {
      final s = _Server({
        'GET /api/academy/batches/b1/fee': (_) =>
            const _Reply(404, {'status': 404, 'message': 'BatchFee not found'}),
      });
      await tester.pumpWidget(
        _app(BatchFeePanel(repository: _repo(s), batch: batch)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Set fee'), findsOneWidget);
    });
  });

  group('catalogue and campus', () {
    testWidgets('course list loads, searches, and the form validates codes', (
      tester,
    ) async {
      final s = _Server({
        'GET /api/academy/courses': (_) => {
          'content': [
            {
              'id': '1',
              'code': 'MATH',
              'name': 'Mathematics',
              'status': 'active',
            },
            {'id': '2', 'code': 'PHY', 'name': 'Physics', 'status': 'active'},
          ],
          'totalElements': 2,
        },
      });
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(CoursesScreen(repository: _repo(s))));
      await tester.pumpAndSettle();
      expect(find.text('Physics'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'math');
      await tester.pump();
      expect(find.text('Physics'), findsNothing);
      await tester.tap(find.text('Add course'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'e.g. MATH-11'),
        'bad code!',
      );
      await tester.pump();
      expect(find.textContaining('Letters, digits'), findsOneWidget);
    });

    testWidgets(
      'several managed campuses and none chosen: no create button, an instruction instead',
      (tester) async {
        final campus = await _campus(tester, [
          {
            'id': 'c1',
            'name': 'Main',
            'permissions': ['academy.manage'],
          },
          {
            'id': 'c2',
            'name': 'North',
            'permissions': ['academy.manage'],
          },
        ], all: true);
        final s = _Server({
          'GET /api/academy/batches': (_) => {
            'content': [],
            'totalElements': 0,
          },
        });
        await tester.pumpWidget(
          _app(BatchesScreen(repository: _repo(s)), campus: campus),
        );
        await tester.pumpAndSettle();
        expect(find.text('New batch'), findsNothing);
        expect(find.textContaining('Choose a campus'), findsOneWidget);
        expect(
          s.requests.single.queryParameters.containsKey('campusId'),
          isFalse,
          reason: 'All Campuses lists every authorised campus',
        );
      },
    );

    testWidgets('a chosen campus narrows the list and enables creation there', (
      tester,
    ) async {
      final campus = await _campus(tester, [
        {
          'id': 'c1',
          'name': 'Main',
          'permissions': ['academy.manage'],
        },
        {
          'id': 'c2',
          'name': 'North',
          'permissions': ['student.view'],
        },
      ]);
      await tester.runAsync(() => campus.select('c1'));
      final s = _Server({
        'GET /api/academy/batches': (_) => {'content': [], 'totalElements': 0},
      });
      await tester.pumpWidget(
        _app(BatchesScreen(repository: _repo(s)), campus: campus),
      );
      await tester.pumpAndSettle();
      expect(find.text('New batch'), findsOneWidget);
      expect(s.requests.single.queryParameters['campusId'], 'c1');
    });

    testWidgets('an instructor with no assignment sees an honest empty state', (
      tester,
    ) async {
      final s = _Server({
        'GET /api/academy/batches': (_) => {'content': [], 'totalElements': 0},
      });
      await tester.pumpWidget(
        _app(BatchesScreen(repository: _repo(s), mine: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('No batches assigned'), findsOneWidget);
      expect(s.requests.single.queryParameters['mine'], true);
    });

    testWidgets('a server error is shown, not an empty list', (tester) async {
      final s = _Server({
        'GET /api/academy/batches': (_) => const _Reply(409, {
          'status': 409,
          'message': 'ACADEMY_NOT_ENABLED: off',
        }),
      });
      await tester.pumpWidget(
        _app(BatchesScreen(repository: _repo(s), mine: true)),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('not enabled for this institution'),
        findsOneWidget,
      );
    });
  });
}

var s0 = 0;
