import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/api_config.dart';
import 'package:smartems/core/network/token_store.dart';
import 'package:smartems/core/router/auth_state.dart';
import 'package:smartems/core/shell/identity_resolver.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/app_button.dart';
import 'package:smartems/core/widgets/inline_alert.dart';
import 'package:smartems/features/auth/data/auth_repository.dart';
import 'package:smartems/features/auth/presentation/change_password_screen.dart';
import 'package:smartems/features/auth/presentation/login_screen.dart';

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

Dio _dio(_Adapter a) =>
    Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))..httpClientAdapter = a;

Widget host(Widget child) => MaterialApp(
      theme: AppTheme.light(role: AppRole.admin),
      home: child,
    );

Future<void> _fill(WidgetTester tester, List<String> values) async {
  for (var i = 0; i < values.length; i++) {
    await tester.enterText(find.byType(TextField).at(i), values[i]);
  }
  await tester.pump();
}

void main() {
  group('Login reports forcePasswordChange', () {
    test('the flag is carried out of the repository', () async {
      final repo = AuthRepository(
        dio: _dio(_Adapter((o) => _json(200, {
              'accessToken': 'a',
              'refreshToken': 'r',
              'expiresIn': 900,
              'forcePasswordChange': true,
            }))),
        tokenStore: InMemoryTokenStore(),
      );

      final outcome = await repo.login(
        institutionCode: 'test-school',
        username: 'admin',
        password: 'pw',
      );

      expect((outcome as LoginSucceeded).forcePasswordChange, isTrue);
    });

    test('absent flag defaults to false, not to forcing a change', () async {
      final repo = AuthRepository(
        dio: _dio(_Adapter(
            (o) => _json(200, {'accessToken': 'a', 'refreshToken': 'r'}))),
        tokenStore: InMemoryTokenStore(),
      );

      final outcome = await repo.login(
        institutionCode: 'c',
        username: 'u',
        password: 'p',
      );

      expect((outcome as LoginSucceeded).forcePasswordChange, isFalse);
    });

    testWidgets('LoginScreen routes to the change-password callback INSTEAD '
        'of the normal signed-in one', (tester) async {
      var signedIn = 0;
      var forced = 0;

      await tester.pumpWidget(host(LoginScreen(
        repository: AuthRepository(
          dio: _dio(_Adapter((o) => _json(200, {
                'accessToken': 'a',
                'refreshToken': 'r',
                'forcePasswordChange': true,
              }))),
          tokenStore: InMemoryTokenStore(),
        ),
        onSignedIn: () => signedIn++,
        onForcePasswordChange: () => forced++,
      )));

      await _fill(tester, ['test-school', 'admin', 'pw']);
      await tester.tap(find.widgetWithText(AppButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(forced, 1);
      expect(
        signedIn,
        0,
        reason: 'reaching the dashboard is exactly what the flag forbids',
      );
    });
  });

  group('AuthRepository.changePassword', () {
    test('sends the live-verified field names', () async {
      final adapter = _Adapter((o) => _json(200, {'ok': true}));
      final repo = AuthRepository(
        dio: _dio(adapter),
        tokenStore: InMemoryTokenStore(accessToken: 'a', refreshToken: 'r'),
      );

      final failure = await repo.changePassword(
        currentPassword: 'old',
        newPassword: 'new',
      );

      expect(failure, isNull);
      final req = adapter.requests.single;
      expect(req.path, ApiConfig.changePasswordPath);
      expect(req.data, {'currentPassword': 'old', 'newPassword': 'new'});
    });

    test('SUCCESS clears local tokens — every session was revoked, including '
        'this one', () async {
      final store = InMemoryTokenStore(accessToken: 'a', refreshToken: 'r');
      final repo = AuthRepository(
        dio: _dio(_Adapter((o) => _json(200, {'ok': true}))),
        tokenStore: store,
      );

      await repo.changePassword(currentPassword: 'old', newPassword: 'new');

      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    });

    test('FAILURE keeps the session — the old password still works', () async {
      // Paired with the test above: clearing on failure would strand a user
      // who merely mistyped their current password.
      final store = InMemoryTokenStore(accessToken: 'a', refreshToken: 'r');
      final repo = AuthRepository(
        dio: _dio(_Adapter((o) {
          throw DioException(
            requestOptions: o,
            response: Response(
              requestOptions: o,
              statusCode: 400,
              data: const {'message': 'Current password is incorrect'},
            ),
          );
        })),
        tokenStore: store,
      );

      final failure = await repo.changePassword(
        currentPassword: 'wrong',
        newPassword: 'new',
      );

      expect(failure?.message, 'Current password is incorrect');
      expect(await store.readAccessToken(), 'a');
    });
  });

  group('ChangePasswordScreen', () {
    testWidgets('warns UP FRONT that this signs you out everywhere',
        (tester) async {
      await tester.pumpWidget(host(ChangePasswordScreen(
        repository: AuthRepository(
          dio: _dio(_Adapter((o) => _json(200, {}))),
          tokenStore: InMemoryTokenStore(),
        ),
        onChanged: () {},
      )));
      await tester.pumpAndSettle();

      // Stated before the action: being returned to login is expected here,
      // not a bug the user has to interpret afterwards.
      expect(find.textContaining('signs you out everywhere'), findsOneWidget);
    });

    testWidgets('mismatched confirmation is caught locally, with no request',
        (tester) async {
      final adapter = _Adapter((o) => _json(200, {}));
      await tester.pumpWidget(host(ChangePasswordScreen(
        repository: AuthRepository(
          dio: _dio(adapter),
          tokenStore: InMemoryTokenStore(),
        ),
        onChanged: () {},
      )));
      await tester.pumpAndSettle();

      await _fill(tester, ['old', 'newpass', 'typo']);
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('do not match'), findsOneWidget);
      expect(
        adapter.requests,
        isEmpty,
        reason: 'the backend has no confirm field, so a typo here would '
            'otherwise lock the user out of the account they just set',
      );
    });

    testWidgets('a successful change calls onChanged, which returns the user '
        'to login', (tester) async {
      var changed = 0;
      await tester.pumpWidget(host(ChangePasswordScreen(
        repository: AuthRepository(
          dio: _dio(_Adapter((o) => _json(200, {}))),
          tokenStore: InMemoryTokenStore(accessToken: 'a'),
        ),
        onChanged: () => changed++,
      )));
      await tester.pumpAndSettle();

      await _fill(tester, ['old', 'newpass', 'newpass']);
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await tester.pumpAndSettle();

      expect(changed, 1);
    });

    testWidgets('a backend rejection is shown verbatim and keeps the form',
        (tester) async {
      await tester.pumpWidget(host(ChangePasswordScreen(
        repository: AuthRepository(
          dio: _dio(_Adapter((o) {
            throw DioException(
              requestOptions: o,
              response: Response(
                requestOptions: o,
                statusCode: 400,
                data: const {'message': 'Password too short'},
              ),
            );
          })),
          tokenStore: InMemoryTokenStore(),
        ),
        onChanged: () {},
      )));
      await tester.pumpAndSettle();

      await _fill(tester, ['old', 'x', 'x']);
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Password too short'), findsOneWidget);
      expect(find.byType(InlineAlert), findsWidgets);
    });
  });

  group('AuthState — the gate clears correctly', () {
    test('clear() resets mustChangePassword, so a later login is not stuck '
        'on the change screen forever', () async {
      final auth = AuthState(
        tokenStore: InMemoryTokenStore(),
        identityResolver: const StaticIdentityResolver(),
      )..mustChangePassword = true;

      expect(auth.mustChangePassword, isTrue);
      auth.clear();
      expect(auth.mustChangePassword, isFalse);
    });

    test('institutionLabel falls back to the code until the name loads',
        () async {
      final auth = AuthState(
        tokenStore: InMemoryTokenStore(
          accessToken: 'a',
          institutionCode: 'test-school',
        ),
        identityResolver: const StaticIdentityResolver(
          IdentityResult(IdentityResultKind.linked, roles: ['admin']),
        ),
      );

      await auth.restore();

      // No dio supplied, so the name call never happens — a cosmetic
      // failure must not leave the app bar empty.
      expect(auth.institutionLabel, 'test-school');
    });

    test('institutionLabel prefers the real name once loaded', () async {
      final auth = AuthState(
        tokenStore: InMemoryTokenStore(
          accessToken: 'a',
          institutionCode: 'test-school',
        ),
        identityResolver: const StaticIdentityResolver(
          IdentityResult(IdentityResultKind.linked, roles: ['admin']),
        ),
        dio: _dio(_Adapter((o) => _json(200, {
              'id': 't-1',
              'name': 'Test School',
              'code': 'test-school',
            }))),
      );

      await auth.restore();

      expect(auth.institutionLabel, 'Test School');
    });
  });
}
