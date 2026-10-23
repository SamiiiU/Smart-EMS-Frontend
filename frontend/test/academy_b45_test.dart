import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/api_config.dart';
import 'package:smartems/core/network/step_up_interceptor.dart';
import 'package:smartems/core/network/token_store.dart';
import 'package:smartems/core/router/auth_state.dart';
import 'package:smartems/core/shell/identity_resolver.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/features/academy/data/academy_repository.dart';
import 'package:smartems/features/academy/presentation/academy_finance_screen.dart';
import 'package:smartems/features/academy/presentation/academy_navigation.dart';
import 'package:smartems/features/finance/data/finance_repository.dart';

/// B4.5: profile lookup states, finance discovery/report screens, navigation.
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
    final h = routes['${o.method} ${o.path}'];
    if (h == null) return _body(404, {'message': 'Not found'});
    final r = h(o);
    if (r is DioException) throw r;
    if (r is (int, Object)) return _body(r.$1, r.$2);
    return _body(200, r);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _body(int status, Object body) => ResponseBody.fromBytes(
  utf8.encode(body is String ? body : jsonEncode(body)),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Dio _dio(_Server s) =>
    Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))..httpClientAdapter = s;

Future<AuthState> _signedIn(_Server s) async {
  final auth = AuthState(
    tokenStore: InMemoryTokenStore(accessToken: 'a', refreshToken: 'r'),
    identityResolver: const StaticIdentityResolver(),
    dio: _dio(s),
  );
  await auth.refreshIdentity();
  return auth;
}

const _profilePath = 'GET /api/institution/profile';

void main() {
  group('institution profile lookup', () {
    test(
      'absent row: server default SCHOOL, not explicit; no Academy',
      () async {
        final auth = await _signedIn(
          _Server({
            _profilePath: (_) => {
              'profile': 'SCHOOL',
              'academyEnabled': false,
              'updatedAt': null,
            },
          }),
        );
        expect(auth.profileLookup, ProfileLookup.loaded);
        expect(auth.institutionProfile, 'SCHOOL');
        expect(auth.profileExplicit, isFalse);
        expect(auth.academyEnabled, isFalse);
      },
    );

    test('explicit SCHOOL and ACADEMY are distinguished', () async {
      final school = await _signedIn(
        _Server({
          _profilePath: (_) => {
            'profile': 'SCHOOL',
            'updatedAt': '2026-10-14T10:00:00Z',
          },
        }),
      );
      expect(school.profileExplicit, isTrue);
      expect(school.academyEnabled, isFalse);
      final academy = await _signedIn(
        _Server({
          _profilePath: (_) => {
            'profile': 'ACADEMY',
            'academyEnabled': true,
            'updatedAt': '2026-10-14T10:00:00Z',
          },
        }),
      );
      expect(academy.academyEnabled, isTrue);
    });

    test('a failed lookup is FAILED, not SCHOOL; retry recovers', () async {
      var fail = true;
      final auth = await _signedIn(
        _Server({
          _profilePath: (o) => fail
              ? DioException(
                  requestOptions: o,
                  type: DioExceptionType.connectionError,
                )
              : {'profile': 'ACADEMY', 'updatedAt': 'x'},
        }),
      );
      expect(auth.profileLookup, ProfileLookup.failed);
      expect(auth.institutionProfile, isNull);
      expect(auth.academyEnabled, isFalse);
      fail = false;
      await auth.reloadInstitutionProfile();
      expect(auth.profileLookup, ProfileLookup.loaded);
      expect(auth.academyEnabled, isTrue);
    });

    test('a 500 or a malformed body is also FAILED', () async {
      final error = await _signedIn(
        _Server({
          _profilePath: (_) => (500, {'message': 'boom'}),
        }),
      );
      expect(error.profileLookup, ProfileLookup.failed);
      final malformed = await _signedIn(
        _Server({
          _profilePath: (_) => {'unexpected': true},
        }),
      );
      expect(malformed.profileLookup, ProfileLookup.failed);
    });

    test('sign-out clears the profile state', () async {
      final auth = await _signedIn(
        _Server({
          _profilePath: (_) => {'profile': 'ACADEMY'},
        }),
      );
      auth.clear();
      expect(auth.profileLookup, ProfileLookup.unknown);
      expect(auth.academyEnabled, isFalse);
    });
  });

  group('navigation', () {
    final repo = AcademyRepository(Dio());
    const owner = IdentityResult(
      IdentityResultKind.linked,
      roles: ['owner'],
      permissions: ['campus.manage', 'academy.manage', 'fee.manage'],
      grants: [
        GrantScope(
          role: 'owner',
          campusId: null,
          permissions: ['campus.manage', 'academy.manage', 'fee.manage'],
        ),
      ],
      permissionsKnown: true,
    );
    const finance = IdentityResult(
      IdentityResultKind.linked,
      roles: ['finance_staff'],
      permissions: ['fee.manage'],
      grants: [
        GrantScope(
          role: 'finance_staff',
          campusId: 'c1',
          permissions: ['fee.manage'],
        ),
      ],
      permissionsKnown: true,
    );
    List<String> ids(
      IdentityResult id, {
      bool enabled = true,
      bool failed = false,
    }) => [
      for (final d in academyDestinations(
        repository: repo,
        identity: id,
        academyEnabled: enabled,
        personal: false,
        adminShell: true,
        teacherShell: false,
        profileFailed: failed,
        onProfileChanged: () async {},
      ))
        d.id,
    ];

    test('failed lookup: a retry entry only, no Academy workflows', () {
      expect(ids(owner, enabled: false, failed: true), [
        'institution_profile',
        'institution_status',
      ]);
      expect(ids(finance, enabled: false, failed: true), [
        'institution_status',
      ]);
    });

    test(
      'finance staff get Academy fees only; School institutions get nothing Academy',
      () {
        expect(ids(finance), ['academy_fees']);
        expect(ids(owner), ['institution_profile', 'academy_fees', 'academy']);
        expect(ids(finance, enabled: false), isEmpty);
      },
    );
  });

  group('finance screens', () {
    Widget app(Widget child) => MaterialApp(
      theme: AppTheme.light(role: AppRole.admin),
      home: Scaffold(body: child),
    );

    testWidgets('finance batches show fee terms from the server, exact PKR', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = _Server({
        'GET /api/academy/finance/batches': (_) =>
            '{"content":[{"id":"b1","name":"ETP","status":"open","campus_id":"c1","course_name":"Entry Test",'
            '"active_learners":2,"fee_amount":4500.50,"fee_frequency":"monthly"},{"id":"b2","name":"New","status":"open",'
            '"campus_id":"c1","course_name":"Physics","active_learners":0,"fee_amount":null}],"totalElements":2}',
      });
      await tester.pumpWidget(
        app(AcademyFinanceScreen(repository: AcademyRepository(_dio(s)))),
      );
      await tester.pumpAndSettle();
      expect(find.text('PKR 4,500.50 / month'), findsOneWidget);
      expect(find.text('Not set'), findsOneWidget);
    });

    testWidgets('collection report shows server totals, kept apart from school', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = _Server({
        'GET /api/academy/finance/reports/collection': (_) =>
            '{"rows":[{"campus_name":"Main","course_name":"Maths","batch_name":"A","period":"2026-10","invoices":2,'
            '"invoiced":9000.00,"collected":1000.00,"outstanding":8000.00}],'
            '"totals":{"invoices":2,"invoiced":9000.00,"collected":1000.00,"outstanding":8000.00}}',
      });
      await tester.pumpWidget(
        app(AcademyCollectionReport(repository: AcademyRepository(_dio(s)))),
      );
      await tester.pumpAndSettle();
      expect(find.text('PKR 8,000.00'), findsWidgets);
      expect(
        find.textContaining('school class-wise report is separate'),
        findsOneWidget,
      );
      expect(s.requests.single.queryParameters.containsKey('period'), isFalse);
    });

    testWidgets('profile-unavailable screen retries', (tester) async {
      var retried = 0;
      await tester.pumpWidget(
        app(
          ProfileUnavailableScreen(
            onRetry: () async => retried++,
            loading: false,
          ),
        ),
      );
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(retried, 1);
      expect(
        find.textContaining('hidden until it is confirmed'),
        findsOneWidget,
      );
    });
  });

  group('step-up on raw-text repositories', () {
    test(
      'a 403 STEP_UP_REQUIRED from a plain-text Academy call prompts once and replays',
      () async {
        var attempts = 0;
        final s = _Server({
          'PUT /api/institution/profile': (_) => ++attempts == 1
              ? (
                  403,
                  {
                    'status': 403,
                    'message': 'Confirm with your authenticator code',
                    'details': {'code': 'STEP_UP_REQUIRED'},
                  },
                )
              : {
                  'profile': 'ACADEMY',
                  'academyEnabled': true,
                  'supportedCapabilities': [],
                },
        });
        final dio = _dio(s);
        final reasons = <String>[];
        dio.interceptors.add(
          StepUpInterceptor(
            retryDio: dio,
            prompt: (r) async {
              reasons.add(r);
              return true;
            },
          ),
        );
        final p = await AcademyRepository(
          dio,
        ).changeProfile('ACADEMY', 'Becoming an academy');
        expect(p.academyEnabled, isTrue);
        expect(reasons, ['STEP_UP_REQUIRED']);
        expect(attempts, 2);
      },
    );

    test(
      'a declined step-up surfaces the refusal and is not replayed',
      () async {
        var attempts = 0;
        final s = _Server({
          'PUT /api/institution/profile': (_) {
            attempts++;
            return (
              403,
              {
                'status': 403,
                'message': 'Confirm with your authenticator code',
                'details': {'code': 'STEP_UP_REQUIRED'},
              },
            );
          },
        });
        final dio = _dio(s);
        dio.interceptors.add(
          StepUpInterceptor(retryDio: dio, prompt: (_) async => false),
        );
        await expectLater(
          AcademyRepository(
            dio,
          ).changeProfile('ACADEMY', 'Becoming an academy'),
          throwsA(anything),
        );
        expect(attempts, 1);
      },
    );
  });

  group('shared step-up interceptor — School finance regression', () {
    const stepUp = (
      403,
      {
        'status': 403,
        'message': 'Confirm with your authenticator code',
        'details': {'code': 'STEP_UP_REQUIRED'},
      },
    );

    Dio wired(_Server s, List<String> reasons, {bool confirm = true}) {
      final dio = _dio(s);
      dio.interceptors.add(
        StepUpInterceptor(
          retryDio: dio,
          prompt: (r) async {
            reasons.add(r);
            return confirm;
          },
        ),
      );
      return dio;
    }

    test(
      'fee head creation (raw-text Finance call) prompts once and succeeds after step-up',
      () async {
        var attempts = 0;
        final s = _Server({
          'POST /api/fee/heads': (_) => ++attempts == 1
              ? stepUp
              : '{"id":"h1","name":"Tuition","isRecurring":true,"taxRate":0.00}',
        });
        final reasons = <String>[];
        final head = await FinanceRepository(
          wired(s, reasons),
        ).createHead(name: 'Tuition', isRecurring: true);
        expect(head.name, 'Tuition');
        expect(reasons, ['STEP_UP_REQUIRED']);
        expect(attempts, 2);
      },
    );

    test(
      'payment approval (raw-text Finance call) prompts and replays exactly once',
      () async {
        var attempts = 0;
        final s = _Server({
          'POST /api/fee/payments/p1/approve': (_) => ++attempts == 1
              ? stepUp
              : '{"id":"p1","status":"approved","invoiceId":"i1","invoiceStatus":"paid","amount":500.00}',
        });
        final reasons = <String>[];
        final r = await FinanceRepository(
          wired(s, reasons),
        ).approvePayment('p1');
        expect(r.error, isNull);
        expect(reasons, ['STEP_UP_REQUIRED']);
        expect(attempts, 2);
      },
    );

    test('an ordinary 403 (not step-up) is never prompted', () async {
      final s = _Server({
        'POST /api/fee/heads': (_) =>
            (403, {'status': 403, 'message': 'Forbidden'}),
      });
      final reasons = <String>[];
      await expectLater(
        FinanceRepository(
          wired(s, reasons),
        ).createHead(name: 'X', isRecurring: true),
        throwsA(anything),
      );
      expect(reasons, isEmpty);
      expect(s.requests, hasLength(1));
    });

    test('Academy batch fee PUT prompts and succeeds after step-up', () async {
      var attempts = 0;
      final s = _Server({
        'PUT /api/academy/batches/b1/fee': (_) => ++attempts == 1
            ? stepUp
            : '{"fee_head_name":"Tuition","amount":3000.00,"frequency":"monthly","due_day":10}',
      });
      final reasons = <String>[];
      final fee = await AcademyRepository(wired(s, reasons)).setBatchFee(
        'b1',
        feeHeadId: 'h1',
        amount: '3000.00',
        frequency: 'monthly',
        dueDay: 10,
      );
      expect(fee.amount, '3000.00');
      expect(reasons, ['STEP_UP_REQUIRED']);
    });
  });
}
