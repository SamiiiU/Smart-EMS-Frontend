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
import 'package:smartems/features/auth/data/mfa_repository.dart';
import 'package:smartems/features/auth/presentation/mfa_screen.dart';

class _Server implements HttpClientAdapter {
  _Server(this.responder);

  final ResponseBody Function(RequestOptions o) responder;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    requests.add(o);
    return responder(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromBytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
);

ResponseBody _forbidden(String code) =>
    _json(403, {'status': 403, 'error': 'Forbidden', 'message': 'x', 'details': {'code': code}});

Dio _dio(_Server s) => Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))..httpClientAdapter = s;

Map<String, Object> _status({required bool required, required bool enrolled, required bool verified}) => {
  'required': required,
  'enrolled': enrolled,
  'sessionVerified': verified,
  'stepUpActive': false,
  'recoveryCodesRemaining': 10,
};

class _Resolver implements IdentityResolver {
  int calls = 0;
  @override
  Future<IdentityResult> resolveIdentity() async {
    calls++;
    return const IdentityResult(IdentityResultKind.linked, roles: ['admin'], userId: 'u', tenantId: 't');
  }
}

void main() {
  group('StepUpInterceptor', () {
    test('prompts once and replays the refused finance request once', () async {
      var approvals = 0;
      final server = _Server((o) {
        if (o.path.endsWith('/approve')) {
          approvals++;
          return approvals == 1 ? _forbidden('STEP_UP_REQUIRED') : _json(200, {'status': 'approved'});
        }
        return _json(404, {});
      });
      final dio = _dio(server);
      final reasons = <String>[];
      dio.interceptors.add(StepUpInterceptor(retryDio: dio, prompt: (r) async {
        reasons.add(r);
        return true;
      }));
      final res = await dio.post<Map<String, dynamic>>('/api/fee/payments/p/approve');
      expect(res.data?['status'], 'approved');
      expect(reasons, ['STEP_UP_REQUIRED']);
      expect(approvals, 2);
    });

    test('a cancelled prompt surfaces the original 403 without replay', () async {
      final server = _Server((o) => _forbidden('STEP_UP_REQUIRED'));
      final dio = _dio(server);
      dio.interceptors.add(StepUpInterceptor(retryDio: dio, prompt: (_) async => false));
      await expectLater(dio.post<dynamic>('/api/fee/payments/p/approve'),
          throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 403)));
      expect(server.requests, hasLength(1));
    });

    test('a second refusal after replay is not prompted again (no loop)', () async {
      final server = _Server((o) => _forbidden('STEP_UP_REQUIRED'));
      final dio = _dio(server);
      var prompts = 0;
      dio.interceptors.add(StepUpInterceptor(retryDio: dio, prompt: (_) async {
        prompts++;
        return true;
      }));
      await expectLater(dio.post<dynamic>('/api/fee/payments/p/approve'), throwsA(isA<DioException>()));
      expect(prompts, 1);
      expect(server.requests, hasLength(2));
    });

    test('enrolment-required informs but never replays', () async {
      final server = _Server((o) => _forbidden('MFA_ENROLLMENT_REQUIRED'));
      final dio = _dio(server);
      dio.interceptors.add(StepUpInterceptor(retryDio: dio, prompt: (_) async => true));
      await expectLater(dio.post<dynamic>('/api/fee/payments/p/reject'), throwsA(isA<DioException>()));
      expect(server.requests, hasLength(1));
    });

    test('MFA_REQUIRED reports a restricted session instead of signing out', () async {
      final server = _Server((o) => _forbidden('MFA_REQUIRED'));
      final dio = _dio(server);
      var restricted = 0;
      dio.interceptors.add(StepUpInterceptor(retryDio: dio)..onMfaRequired = () => restricted++);
      await expectLater(dio.get<dynamic>('/api/students'), throwsA(isA<DioException>()));
      expect(restricted, 1);
    });

    test('ordinary 403 is untouched', () async {
      final server = _Server((o) => _json(403, {'message': 'Forbidden'}));
      final dio = _dio(server);
      var prompts = 0;
      dio.interceptors.add(StepUpInterceptor(retryDio: dio, prompt: (_) async {
        prompts++;
        return true;
      }));
      await expectLater(dio.get<dynamic>('/api/students'), throwsA(isA<DioException>()));
      expect(prompts, 0);
    });
  });

  group('AuthState two-factor gate', () {
    test('a restricted session does not resolve identity until verified', () async {
      final server = _Server((o) => _json(200, _status(required: true, enrolled: true, verified: false)));
      final resolver = _Resolver();
      final store = InMemoryTokenStore();
      await store.writeTokens(accessToken: 'a', refreshToken: 'r');
      final auth = AuthState(tokenStore: store, identityResolver: resolver, mfa: MfaRepository(_dio(server)));
      await auth.restore();
      expect(auth.mfaPending, isTrue);
      expect(auth.isSignedIn, isFalse);
      expect(resolver.calls, 0);
      await auth.mfaVerified();
      expect(auth.mfaPending, isFalse);
      expect(auth.isSignedIn, isTrue);
    });

    test('an unrestricted session signs in directly', () async {
      final server = _Server((o) => _json(200, _status(required: false, enrolled: false, verified: false)));
      final resolver = _Resolver();
      final store = InMemoryTokenStore();
      await store.writeTokens(accessToken: 'a', refreshToken: 'r');
      final auth = AuthState(tokenStore: store, identityResolver: resolver, mfa: MfaRepository(_dio(server)));
      await auth.restore();
      expect(auth.mfaPending, isFalse);
      expect(auth.isSignedIn, isTrue);
    });

    test('sign-out clears the restricted flag', () async {
      final server = _Server((o) => _json(200, _status(required: true, enrolled: false, verified: false)));
      final store = InMemoryTokenStore();
      await store.writeTokens(accessToken: 'a', refreshToken: 'r');
      final auth = AuthState(tokenStore: store, identityResolver: _Resolver(), mfa: MfaRepository(_dio(server)));
      await auth.restore();
      expect(auth.mfaPending, isTrue);
      auth.clear();
      expect(auth.mfaPending, isFalse);
    });
  });

  group('MfaScreen', () {
    Widget host(Widget child) => MaterialApp(theme: AppTheme.light(role: AppRole.admin), home: child);

    testWidgets('enrolment shows the key, confirms the code and shows recovery codes once', (tester) async {
      final server = _Server((o) {
        if (o.path == ApiConfig.mfaPath) return _json(200, _status(required: true, enrolled: false, verified: false));
        if (o.path == ApiConfig.mfaEnrollmentPath) return _json(200, {'secret': 'JBSWY3DPEHPK3PXP', 'otpauthUrl': 'otpauth://totp/x'});
        if (o.path == ApiConfig.mfaEnrollmentConfirmPath) return _json(200, {'recoveryCodes': ['AAAAA-BBBBB-CCCCC-DDDDD']});
        return _json(404, {});
      });
      var verified = 0;
      await tester.pumpWidget(host(MfaScreen(
        repository: MfaRepository(_dio(server)),
        onVerified: () => verified++,
        onSignOut: () async {},
      )));
      await tester.pumpAndSettle();
      expect(find.text('JBSWY3DPEHPK3PXP'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();
      expect(jsonDecode(jsonEncode(server.requests.last.data))['code'], '123456');
      expect(find.text('AAAAA-BBBBB-CCCCC-DDDDD'), findsOneWidget);
      expect(verified, 0, reason: 'codes must be acknowledged first');
      await tester.tap(find.text('I have saved them'));
      expect(verified, 1);
    });

    testWidgets('a rejected code keeps the user on the screen with the server message', (tester) async {
      final server = _Server((o) {
        if (o.path == ApiConfig.mfaPath) return _json(200, _status(required: true, enrolled: true, verified: false));
        if (o.path == ApiConfig.mfaVerifyPath) return _json(401, {'message': 'Invalid verification code'});
        return _json(404, {});
      });
      var verified = 0;
      await tester.pumpWidget(host(MfaScreen(
        repository: MfaRepository(_dio(server)),
        onVerified: () => verified++,
        onSignOut: () async {},
      )));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '000000');
      await tester.pump();
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();
      expect(find.text('Invalid verification code'), findsOneWidget);
      expect(verified, 0);
    });

    testWidgets('recovery codes are sent as recoveryCode, not as a TOTP', (tester) async {
      final server = _Server((o) {
        if (o.path == ApiConfig.mfaPath) return _json(200, _status(required: true, enrolled: true, verified: false));
        if (o.path == ApiConfig.mfaVerifyPath) return _json(200, {'status': 'verified'});
        return _json(404, {});
      });
      var verified = 0;
      await tester.pumpWidget(host(MfaScreen(
        repository: MfaRepository(_dio(server)),
        onVerified: () => verified++,
        onSignOut: () async {},
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use a recovery code'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'AAAAA-BBBBB-CCCCC-DDDDD');
      await tester.pump();
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();
      final body = server.requests.last.data as Map;
      expect(body.containsKey('code'), isFalse);
      expect(body['recoveryCode'], 'AAAAA-BBBBB-CCCCC-DDDDD');
      expect(verified, 1);
    });
  });
}
