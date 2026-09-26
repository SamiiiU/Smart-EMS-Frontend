import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/api_config.dart';
import 'package:smartems/core/network/network_identity_resolver.dart';
import 'package:smartems/core/network/token_store.dart';
import 'package:smartems/core/shell/identity_resolver.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/states/screen_state.dart';
import 'package:smartems/core/widgets/app_button.dart';
import 'package:smartems/core/widgets/app_text_field.dart';
import 'package:smartems/core/widgets/inline_alert.dart';
import 'package:smartems/features/auth/data/auth_repository.dart';
import 'package:smartems/features/auth/presentation/login_screen.dart';

/// Scripts responses per request path, so a test can model the real
/// two-call identity flow without touching the network.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.responder);

  final ResponseBody Function(RequestOptions options) responder;

  final List<String> requestedPaths = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedPaths.add(options.path);
    return responder(options);
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

Dio _dioWith(_ScriptedAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl));
  dio.httpClientAdapter = adapter;
  return dio;
}

Widget host(Widget child, {double textScale = 1.0, TextDirection? direction}) {
  return MaterialApp(
    theme: AppTheme.light(role: AppRole.admin),
    darkTheme: AppTheme.dark(role: AppRole.admin),
    builder: (context, mqChild) {
      var out = mqChild!;
      if (direction != null) {
        out = Directionality(textDirection: direction, child: out);
      }
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: out,
      );
    },
    home: child,
  );
}

void main() {
  group('AuthRepository.login', () {
    test('success persists BOTH tokens before returning', () async {
      final store = InMemoryTokenStore();
      final adapter = _ScriptedAdapter(
        (o) => _json(200, {
          'accessToken': 'access-abc',
          'refreshToken': 'refresh-xyz',
          'expiresIn': 900,
        }),
      );
      final repo = AuthRepository(dio: _dioWith(adapter), tokenStore: store);

      final outcome = await repo.login(
        institutionCode: 'test-school',
        username: 'admin',
        password: 'Test1234!',
      );

      expect(outcome, isA<LoginSucceeded>());
      expect(await store.readAccessToken(), 'access-abc');
      expect(
        await store.readRefreshToken(),
        'refresh-xyz',
        reason: 'the refresh token must be stored at login, or the first '
            'token expiry 15 minutes later signs the user out for good',
      );
      expect(adapter.requestedPaths.single, ApiConfig.loginPath);
    });

    test('sends all three required fields — the API rejects a login without '
        'institutionCode', () async {
      Map<String, dynamic>? sentBody;
      final adapter = _ScriptedAdapter((o) {
        sentBody = o.data as Map<String, dynamic>;
        return _json(200, {'accessToken': 'a', 'refreshToken': 'r'});
      });
      final repo = AuthRepository(
        dio: _dioWith(adapter),
        tokenStore: InMemoryTokenStore(),
      );

      await repo.login(
        institutionCode: 'test-school',
        username: 'admin',
        password: 'pw',
      );

      expect(sentBody, {
        'institutionCode': 'test-school',
        'username': 'admin',
        'password': 'pw',
      });
    });

    test('401 surfaces the backend message VERBATIM and stores nothing',
        () async {
      final store = InMemoryTokenStore();
      final adapter = _ScriptedAdapter((o) {
        throw DioException(
          requestOptions: o,
          response: Response(
            requestOptions: o,
            statusCode: 401,
            // The real body, copied from a live call.
            data: const {
              'status': 401,
              'error': 'Unauthorized',
              'message': 'Invalid credentials',
              'path': '/auth/login',
            },
          ),
        );
      });
      final repo = AuthRepository(dio: _dioWith(adapter), tokenStore: store);

      final outcome = await repo.login(
        institutionCode: 'test-school',
        username: 'admin',
        password: 'wrong',
      );

      expect(outcome, isA<LoginFailed>());
      expect((outcome as LoginFailed).failure.message, 'Invalid credentials');
      expect(await store.readAccessToken(), isNull);
    });
  });

  group('AuthRepository.logout', () {
    test('clears local tokens even when the network call fails — a user who '
        'asked to sign out must not be left holding a live token', () async {
      final store = InMemoryTokenStore(
        accessToken: 'a',
        refreshToken: 'r',
      );
      final repo = AuthRepository(
        dio: _dioWith(_ScriptedAdapter((o) {
          throw DioException(
            requestOptions: o,
            type: DioExceptionType.connectionError,
          );
        })),
        tokenStore: store,
      );

      await repo.logout();

      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    });
  });

  group('NetworkIdentityResolver — two-step resolution', () {
    test('admin: /auth/me only, NO person-record call, resolves linked',
        () async {
      // POSITIVE CASE for the absence assertion below: an admin legitimately
      // has no staff or student row (verified live — both return 404), so
      // calling them would wrongly orphan the one person who can fix orphans.
      final adapter = _ScriptedAdapter(
        (o) => _json(200, {
          'roles': ['admin'],
          'userId': 'u-1',
          'tenantId': 't-1',
        }),
      );

      final result =
          await NetworkIdentityResolver(_dioWith(adapter)).resolveIdentity();

      expect(result.kind, IdentityResultKind.linked);
      expect(result.roles, ['admin']);
      expect(result.tenantId, 't-1');
      expect(
        adapter.requestedPaths,
        [ApiConfig.mePath],
        reason: 'an admin must not be person-record checked at all',
      );
    });

    test('teacher WITH a staff record resolves linked, after checking it',
        () async {
      final adapter = _ScriptedAdapter((o) {
        if (o.path == ApiConfig.mePath) {
          return _json(200, {
            'roles': ['teacher'],
            'userId': 'u-2',
            'tenantId': 't-1',
          });
        }
        return _json(200, {'id': 'staff-1'});
      });

      final result =
          await NetworkIdentityResolver(_dioWith(adapter)).resolveIdentity();

      expect(result.kind, IdentityResultKind.linked);
      expect(adapter.requestedPaths, [
        ApiConfig.mePath,
        ApiConfig.staffMePath,
      ]);
    });

    test('teacher WITHOUT a staff record resolves notLinked — the D-17 '
        'orphan case, keyed off the person endpoint not /auth/me', () async {
      final adapter = _ScriptedAdapter((o) {
        if (o.path == ApiConfig.mePath) {
          return _json(200, {
            'roles': ['teacher'],
            'userId': 'u-3',
            'tenantId': 't-1',
          });
        }
        throw DioException(
          requestOptions: o,
          response: Response(
            requestOptions: o,
            statusCode: 404,
            // Real message shape, copied from a live call.
            data: const {
              'status': 404,
              'message': 'Staff record linked to this login not found: u-3',
            },
          ),
        );
      });

      final result =
          await NetworkIdentityResolver(_dioWith(adapter)).resolveIdentity();

      expect(result.kind, IdentityResultKind.notLinked);
    });

    test('student without a student record resolves notLinked via the '
        'STUDENT endpoint', () async {
      final adapter = _ScriptedAdapter((o) {
        if (o.path == ApiConfig.mePath) {
          return _json(200, {
            'roles': ['student'],
            'userId': 'u-4',
            'tenantId': 't-1',
          });
        }
        throw DioException(
          requestOptions: o,
          response: Response(
            requestOptions: o,
            statusCode: 404,
            data: const {'message': 'Student record ... not found'},
          ),
        );
      });

      final result =
          await NetworkIdentityResolver(_dioWith(adapter)).resolveIdentity();

      expect(result.kind, IdentityResultKind.notLinked);
      expect(adapter.requestedPaths.last, ApiConfig.studentMePath);
    });

    test('an expired/invalid token resolves error, NOT notLinked — a 401 '
        'must never be mistaken for an orphaned profile', () async {
      final adapter = _ScriptedAdapter((o) {
        throw DioException(
          requestOptions: o,
          response: Response(
            requestOptions: o,
            statusCode: 401,
            data: const {'message': 'Access token missing or invalid'},
          ),
        );
      });

      final result =
          await NetworkIdentityResolver(_dioWith(adapter)).resolveIdentity();

      expect(result.kind, IdentityResultKind.error);
      expect(result.message, 'Access token missing or invalid');
    });
  });

  group('LoginScreen', () {
    AuthRepository repoReturning(LoginOutcome outcome, {Duration? delay}) {
      return _FakeRepository(outcome, delay: delay);
    }

    testWidgets('submit is disabled until all three fields are filled',
        (tester) async {
      await tester.pumpWidget(host(LoginScreen(
        repository: repoReturning(const LoginSucceeded()),
        onSignedIn: () {},
      )));

      AppButton button() => tester.widget<AppButton>(find.byType(AppButton));
      expect(button().onPressed, isNull);

      await tester.enterText(find.byType(TextField).at(0), 'test-school');
      await tester.pump();
      expect(button().onPressed, isNull, reason: 'still missing two fields');

      await tester.enterText(find.byType(TextField).at(1), 'admin');
      await tester.pump();
      expect(button().onPressed, isNull, reason: 'still missing password');

      await tester.enterText(find.byType(TextField).at(2), 'Test1234!');
      await tester.pump();
      expect(button().onPressed, isNotNull);
    });

    testWidgets('a failed sign-in shows the backend message and KEEPS the '
        'typed input', (tester) async {
      await tester.pumpWidget(host(LoginScreen(
        repository: repoReturning(
          const LoginFailed(LoadFailureStub.invalidCredentials),
        ),
        onSignedIn: () {},
      )));

      await tester.enterText(find.byType(TextField).at(0), 'test-school');
      await tester.enterText(find.byType(TextField).at(1), 'admin');
      await tester.enterText(find.byType(TextField).at(2), 'wrong');
      await tester.pump();

      await tester.tap(find.byType(AppButton));
      await tester.pumpAndSettle();

      expect(find.byType(InlineAlert), findsOneWidget);
      expect(find.text('Invalid credentials'), findsOneWidget);
      // D-30's spirit: a failure never wipes what the user can already see.
      expect(find.text('test-school'), findsOneWidget);
      expect(find.text('admin'), findsOneWidget);
    });

    testWidgets('a successful sign-in calls onSignedIn exactly once',
        (tester) async {
      var signedIn = 0;
      await tester.pumpWidget(host(LoginScreen(
        repository: repoReturning(const LoginSucceeded()),
        onSignedIn: () => signedIn++,
      )));

      await tester.enterText(find.byType(TextField).at(0), 'test-school');
      await tester.enterText(find.byType(TextField).at(1), 'admin');
      await tester.enterText(find.byType(TextField).at(2), 'Test1234!');
      await tester.pump();

      await tester.tap(find.byType(AppButton));
      await tester.pumpAndSettle();

      expect(signedIn, 1);
    });

    testWidgets('while submitting, the button is disabled so a double tap '
        'cannot fire two logins', (tester) async {
      var calls = 0;
      final repo = _CountingRepository(() => calls++);
      await tester.pumpWidget(host(LoginScreen(
        repository: repo,
        onSignedIn: () {},
      )));

      await tester.enterText(find.byType(TextField).at(0), 'test-school');
      await tester.enterText(find.byType(TextField).at(1), 'admin');
      await tester.enterText(find.byType(TextField).at(2), 'pw');
      await tester.pump();

      await tester.tap(find.byType(AppButton));
      await tester.pump(); // submitting = true, not yet resolved
      await tester.tap(find.byType(AppButton), warnIfMissed: false);
      await tester.pump();

      await tester.pumpAndSettle();
      expect(calls, 1);
    });

    testWidgets('ABSENCE: there is no signup/create-account affordance, '
        'because no such endpoint exists', (tester) async {
      await tester.pumpWidget(host(LoginScreen(
        repository: repoReturning(const LoginSucceeded()),
        onSignedIn: () {},
      )));

      // Exactly one button on the screen: Sign in.
      expect(find.byType(AppButton), findsOneWidget);
      expect(
        tester.widget<AppButton>(find.byType(AppButton)).label,
        'Sign in',
      );
      // POSITIVE CASE pairing the absence: the screen still TELLS the user
      // where accounts come from, rather than silently offering nothing.
      expect(
        find.textContaining('administrator'),
        findsOneWidget,
        reason: 'a dead end with no explanation would be worse than a link',
      );
    });

    testWidgets('accessibility: renders without overflow at 2x text scale',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(
        LoginScreen(
          repository: repoReturning(const LoginSucceeded()),
          onSignedIn: () {},
        ),
        textScale: 2,
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('accessibility: renders in RTL without overflow',
        (tester) async {
      await tester.pumpWidget(host(
        LoginScreen(
          repository: repoReturning(const LoginSucceeded()),
          onSignedIn: () {},
        ),
        direction: TextDirection.rtl,
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AppTextField), findsNWidgets(3));
    });
  });
}

/// A `LoadFailure` carrying the real backend message, as a named constant so
/// the expectation and the fixture cannot drift apart.
abstract final class LoadFailureStub {
  static const invalidCredentials = LoadFailure(message: 'Invalid credentials');
}

class _FakeRepository implements AuthRepository {
  _FakeRepository(this._outcome, {this.delay});

  final LoginOutcome _outcome;
  final Duration? delay;

  @override
  Dio get dio => throw UnimplementedError();

  @override
  TokenStore get tokenStore => throw UnimplementedError();

  @override
  Future<LoginOutcome> login({
    required String institutionCode,
    required String username,
    required String password,
  }) async {
    if (delay != null) await Future<void>.delayed(delay!);
    return _outcome;
  }

  @override
  Future<LoadFailure?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async =>
      null;

  @override
  Future<void> logout() async {}
}

class _CountingRepository implements AuthRepository {
  _CountingRepository(this.onLogin);

  final VoidCallback onLogin;

  @override
  Dio get dio => throw UnimplementedError();

  @override
  TokenStore get tokenStore => throw UnimplementedError();

  @override
  Future<LoginOutcome> login({
    required String institutionCode,
    required String username,
    required String password,
  }) async {
    onLogin();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return const LoginSucceeded();
  }

  @override
  Future<LoadFailure?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async =>
      null;

  @override
  Future<void> logout() async {}
}
