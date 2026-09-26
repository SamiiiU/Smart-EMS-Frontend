import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/api_client.dart';
import 'package:smartems/core/network/api_config.dart';
import 'package:smartems/core/network/api_error_mapper.dart';
import 'package:smartems/core/network/auth_interceptor.dart';
import 'package:smartems/core/network/connectivity_sync_status_source.dart';
import 'package:smartems/core/network/network_identity_resolver.dart';
import 'package:smartems/core/network/screen_state_adapter.dart';
import 'package:smartems/core/network/token_store.dart';
import 'package:smartems/core/shell/identity_resolver.dart';
import 'package:smartems/core/widgets/states/screen_state.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// A canned response or exception, keyed by request path, so tests can
/// script a fake server without a real network call.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.responder);

  /// Called once per request. Returning a [ResponseBody] resolves the
  /// request; throwing a [DioException] fails it, exactly like a real
  /// server error would surface through Dio.
  final ResponseBody Function(RequestOptions options) responder;

  int callCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    callCount++;
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonBody(int status, Map<String, dynamic> json) {
  final bytes = utf8.encode(jsonEncode(json));
  return ResponseBody.fromBytes(bytes, status, headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  });
}

void main() {
  group('AuthInterceptor — single-flight refresh under concurrency', () {
    test('N concurrent 401s trigger exactly ONE refresh call', () async {
      final tokenStore = InMemoryTokenStore(
        accessToken: 'expired-token',
        refreshToken: 'valid-refresh-token',
      );

      var refreshCalls = 0;
      final refresher = _FakeRefresher(onRefresh: () {
        refreshCalls++;
        return Future.delayed(
          const Duration(milliseconds: 20),
          () => 'fresh-access-token',
        );
      });

      final retryDio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      retryDio.httpClientAdapter = _ScriptedAdapter(
        // Retried requests carry the refreshed token — succeed.
        (options) => _jsonBody(200, {'ok': true}),
      );

      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.httpClientAdapter = _ScriptedAdapter((options) {
        // Every first attempt (no retry marker yet) is expired.
        if (options.extra['_retried'] == true) {
          return _jsonBody(200, {'ok': true});
        }
        throw DioException(
          requestOptions: options,
          response: Response(
            requestOptions: options,
            statusCode: 401,
            data: {
              'status': 401,
              'error': 'Unauthorized',
              'message': 'Access token missing or invalid',
              'path': options.path,
            },
          ),
        );
      });
      dio.interceptors.add(AuthInterceptor(
        tokenStore: tokenStore,
        refresher: refresher,
        retryDio: retryDio,
      ));

      final results = await Future.wait([
        dio.get<dynamic>('/a'),
        dio.get<dynamic>('/b'),
        dio.get<dynamic>('/c'),
      ]);

      expect(refreshCalls, 1,
          reason: 'three concurrent 401s must share one refresh call, not '
              'fire one each');
      for (final r in results) {
        expect(r.statusCode, 200);
      }
    });

    test('a second, later expiry starts a NEW refresh call', () async {
      final tokenStore = InMemoryTokenStore(
        accessToken: 'expired-token',
        refreshToken: 'valid-refresh-token',
      );
      var refreshCalls = 0;
      final refresher = _FakeRefresher(onRefresh: () {
        refreshCalls++;
        return Future.value('fresh-access-token-$refreshCalls');
      });

      final retryDio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      retryDio.httpClientAdapter =
          _ScriptedAdapter((options) => _jsonBody(200, {'ok': true}));

      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.httpClientAdapter = _ScriptedAdapter((options) {
        if (options.extra['_retried'] == true) {
          return _jsonBody(200, {'ok': true});
        }
        throw DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 401),
        );
      });
      dio.interceptors.add(AuthInterceptor(
        tokenStore: tokenStore,
        refresher: refresher,
        retryDio: retryDio,
      ));

      await dio.get<dynamic>('/first');
      expect(refreshCalls, 1);

      await dio.get<dynamic>('/second');
      expect(refreshCalls, 2,
          reason: 'a fresh 401 after the first refresh settled must start '
              'its own refresh, not reuse the completed one');
    });
  });

  group('DioTokenRefresher — token rotation', () {
    test('stores the ROTATED refresh token from the response, not just the '
        'access token', () async {
      // Regression test. The backend rotates refresh tokens: /auth/refresh
      // returns {accessToken, refreshToken, expiresIn}. T6 read only
      // accessToken and kept the OLD refresh token, so once the original was
      // consumed/expired the user would be silently signed out with no way
      // back. Confirmed against the live OpenAPI doc 2026-08-03.
      final tokenStore = InMemoryTokenStore(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
      );

      final dio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl));
      dio.httpClientAdapter = _ScriptedAdapter(
        (options) => _jsonBody(200, {
          'accessToken': 'new-access',
          'refreshToken': 'new-refresh',
          'expiresIn': 900,
        }),
      );

      final refresher = DioTokenRefresher(dio, tokenStore);
      final returned = await refresher.refresh('old-refresh');

      expect(returned, 'new-access');
      expect(await tokenStore.readAccessToken(), 'new-access');
      expect(
        await tokenStore.readRefreshToken(),
        'new-refresh',
        reason: 'the rotated refresh token must replace the old one, or the '
            'next refresh will present a spent token and fail permanently',
      );
    });
  });

  group('mapDioError — LoadFailureKind classification', () {
    test('a PERSON-RECORD 404 maps to notLinked, message preserved verbatim',
        () {
      // Keyed off /api/staff/me, not /auth/me. T6 had this wrong twice over:
      // it guessed the path as `/me`, and it attached orphan semantics to
      // the account endpoint. Verified live 2026-08-03 that /auth/me returns
      // 200 for any valid token and only the person endpoints can 404.
      final options = RequestOptions(path: ApiConfig.staffMePath);
      final err = DioException(
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: 404,
          data: {
            'status': 404,
            'error': 'Not Found',
            'message': 'Staff record linked to this login not found: u-1',
            'path': ApiConfig.staffMePath,
          },
        ),
      );

      final failure = mapDioError(err);
      expect(failure.kind, LoadFailureKind.notLinked);
      expect(failure.isNotLinked, isTrue);
      expect(
        failure.message,
        'Staff record linked to this login not found: u-1',
      );
    });

    test('a 404 from the ACCOUNT endpoint is NOT notLinked — /auth/me cannot '
        'express an orphaned profile', () {
      final options = RequestOptions(path: ApiConfig.mePath);
      final err = DioException(
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: 404,
          data: {'status': 404, 'message': 'Not Found'},
        ),
      );

      expect(mapDioError(err).kind, LoadFailureKind.transient);
    });

    test('a 404 on a DIFFERENT path is an ordinary transient error, not '
        'notLinked', () {
      final options = RequestOptions(path: '/students/42');
      final err = DioException(
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: 404,
          data: {
            'status': 404,
            'error': 'Not Found',
            'message': 'Student not found',
            'path': '/students/42',
          },
        ),
      );

      final failure = mapDioError(err);
      expect(failure.kind, LoadFailureKind.transient);
      expect(failure.message, 'Student not found');
    });

    test('5xx maps to transient with the backend message verbatim', () {
      final options = RequestOptions(path: '/attendance');
      final err = DioException(
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: 500,
          data: {
            'status': 500,
            'error': 'Internal Server Error',
            'message': 'Database unavailable',
            'path': '/attendance',
          },
        ),
      );

      final failure = mapDioError(err);
      expect(failure.kind, LoadFailureKind.transient);
      expect(failure.message, 'Database unavailable');
    });

    test('connection timeout maps to transient with a fallback message '
        'when the backend gave none', () {
      final options = RequestOptions(path: '/attendance');
      final err = DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
      );

      final failure = mapDioError(err);
      expect(failure.kind, LoadFailureKind.transient);
      expect(failure.message, isNotNull);
    });

    test('connection error (offline) maps to transient with a fallback '
        'message', () {
      final options = RequestOptions(path: '/attendance');
      final err = DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );

      final failure = mapDioError(err);
      expect(failure.kind, LoadFailureKind.transient);
      expect(failure.message, isNotNull);
    });
  });

  group('NetworkIdentityResolver', () {
    test('200 on /me resolves linked', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.httpClientAdapter =
          _ScriptedAdapter((options) => _jsonBody(200, {'id': 1}));
      final resolver = NetworkIdentityResolver(dio);

      final result = await resolver.resolveIdentity();
      expect(result.kind, IdentityResultKind.linked);
    });

    test('404 from the ACCOUNT endpoint resolves error, not notLinked',
        () async {
      // The orphan (notLinked) path is driven by the person-record call and
      // is covered thoroughly, per role, in `auth_test.dart`. What matters
      // here is the boundary: a failure of /auth/me itself must never be
      // dressed up as an orphaned profile, because that would tell a user
      // with a broken session to go contact their administrator.
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.httpClientAdapter = _ScriptedAdapter((options) {
        throw DioException(
          requestOptions: options,
          response: Response(
            requestOptions: options,
            statusCode: 404,
            data: {'status': 404, 'message': 'Not Found'},
          ),
        );
      });
      final resolver = NetworkIdentityResolver(dio);

      final result = await resolver.resolveIdentity();
      expect(result.kind, IdentityResultKind.error);
    });

    test('5xx on /me resolves error, with the backend message carried '
        'through for ErrorState\'s retry UI', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.httpClientAdapter = _ScriptedAdapter((options) {
        throw DioException(
          requestOptions: options,
          response: Response(
            requestOptions: options,
            statusCode: 503,
            data: {'status': 503, 'message': 'Service unavailable'},
          ),
        );
      });
      final resolver = NetworkIdentityResolver(dio);

      final result = await resolver.resolveIdentity();
      expect(result.kind, IdentityResultKind.error);
      expect(result.message, 'Service unavailable');
    });
  });

  group('loadIntoScreenState — Dio result to ScreenState<T> (D-40)', () {
    test('a successful request produces a loaded state', () async {
      final state = await loadIntoScreenState<String>(() async => 'hello');
      expect(state.status, ScreenStatus.loaded);
      expect(state.data, 'hello');
    });

    test('a failed request with no prior data produces an errored state '
        'with no cached data (row 5, not row 6)', () async {
      final options = RequestOptions(path: '/x');
      final state = await loadIntoScreenState<String>(() async {
        throw DioException(
          requestOptions: options,
          response: Response(
            requestOptions: options,
            statusCode: 500,
            data: {'message': 'boom'},
          ),
        );
      });
      expect(state.status, ScreenStatus.error);
      expect(state.hasData, isFalse);
      expect(state.failure?.message, 'boom');
    });

    test('a failed request WITH prior data keeps the prior data (row 6, '
        'D-30 — existing data is never replaced by a failure)', () async {
      final options = RequestOptions(path: '/x');
      final previous = const ScreenState<String>.data('cached value');
      final state = await loadIntoScreenState<String>(
        () async {
          throw DioException(
            requestOptions: options,
            response: Response(
              requestOptions: options,
              statusCode: 500,
              data: {'message': 'boom'},
            ),
          );
        },
        previous: previous,
      );
      expect(state.status, ScreenStatus.error);
      expect(state.data, 'cached value');
    });
  });

  group('isOffline — connectivity_plus result classification', () {
    test('an empty result list is offline', () {
      expect(isOffline(const []), isTrue);
    });

    test('all-none results are offline', () {
      expect(
        isOffline(const [ConnectivityResult.none, ConnectivityResult.none]),
        isTrue,
      );
    });

    test('any non-none result is online', () {
      expect(
        isOffline(const [ConnectivityResult.none, ConnectivityResult.wifi]),
        isFalse,
      );
    });
  });

  // A real lockout, found on 2026-09-25 and reproduced against the live
  // backend: the app attached a stale token to `POST /auth/login`, the
  // backend rejected it at the gate with "Access token missing or invalid",
  // and because nothing ever cleared that token every later attempt did the
  // same. The user could not sign in — and could not sign out to fix it,
  // because signing out requires being signed in.
  group('AuthInterceptor — a dead token must not become a lockout', () {
    ({Dio dio, InMemoryTokenStore store, List<RequestOptions> seen}) wire({
      required ResponseBody Function(RequestOptions) responder,
      Future<String?> Function()? onRefresh,
      String? accessToken = 'stale-token',
      String? refreshToken,
    }) {
      final store = InMemoryTokenStore(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
      final seen = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.httpClientAdapter = _ScriptedAdapter((options) {
        seen.add(options);
        return responder(options);
      });
      dio.interceptors.add(AuthInterceptor(
        tokenStore: store,
        refresher:
            _FakeRefresher(onRefresh: onRefresh ?? () async => null),
        retryDio: Dio(BaseOptions(baseUrl: 'https://example.test')),
      ));
      return (dio: dio, store: store, seen: seen);
    }

    test('sign-in carries NO Authorization header, even with a token stored',
        () async {
      final w = wire(responder: (_) => _jsonBody(200, {'accessToken': 'new'}));

      await w.dio.post<dynamic>(ApiConfig.loginPath, data: const {});

      expect(
        w.seen.single.headers.containsKey('Authorization'),
        isFalse,
        reason: 'a stale token here is rejected at the gate and the login '
            'is never attempted',
      );
    });

    test('a header set by the caller is stripped from sign-in too', () async {
      final w = wire(responder: (_) => _jsonBody(200, {'accessToken': 'new'}));

      await w.dio.post<dynamic>(
        ApiConfig.loginPath,
        data: const {},
        options: Options(headers: {'Authorization': 'Bearer sneaky'}),
      );

      expect(w.seen.single.headers.containsKey('Authorization'), isFalse);
    });

    test('token refresh carries no Authorization header either', () async {
      final w = wire(responder: (_) => _jsonBody(200, {'accessToken': 'new'}));

      await w.dio.post<dynamic>(ApiConfig.refreshPath, data: const {});

      expect(w.seen.single.headers.containsKey('Authorization'), isFalse);
    });

    test('every OTHER request still carries the token', () async {
      final w = wire(responder: (_) => _jsonBody(200, {'ok': true}));

      await w.dio.get<dynamic>('/api/students');

      expect(w.seen.single.headers['Authorization'], 'Bearer stale-token');
    });

    test('signing out still authenticates — it ends the session it holds',
        () async {
      final w = wire(responder: (_) => _jsonBody(200, {'ok': true}));

      await w.dio.post<dynamic>(ApiConfig.logoutPath, data: const {});

      expect(w.seen.single.headers['Authorization'], 'Bearer stale-token');
    });

    test('a 401 with nothing to refresh with CLEARS the dead token',
        () async {
      final w = wire(
        responder: (options) => throw DioException(
          requestOptions: options,
          response: Response<dynamic>(
            requestOptions: options,
            statusCode: 401,
            data: const {'message': 'Access token missing or invalid'},
          ),
        ),
      );

      await expectLater(
        w.dio.get<dynamic>('/api/students'),
        throwsA(isA<DioException>()),
      );

      // Left in place, this is what turned one dead session into a lockout.
      expect(w.store.accessToken, isNull);
      expect(w.store.refreshToken, isNull);
    });

    test('a 401 whose refresh ALSO fails clears the dead session', () async {
      final w = wire(
        accessToken: 'expired',
        refreshToken: 'expired-refresh',
        onRefresh: () async => null,
        responder: (options) => throw DioException(
          requestOptions: options,
          response: Response<dynamic>(
            requestOptions: options,
            statusCode: 401,
            data: const {'message': 'Access token missing or invalid'},
          ),
        ),
      );

      await expectLater(
        w.dio.get<dynamic>('/api/students'),
        throwsA(isA<DioException>()),
      );

      expect(w.store.accessToken, isNull);
      expect(w.store.refreshToken, isNull);
    });

    test('a 401 that refresh RECOVERS from keeps the session', () async {
      final store = InMemoryTokenStore(
        accessToken: 'expired',
        refreshToken: 'good-refresh',
      );
      final retryDio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter =
            _ScriptedAdapter((_) => _jsonBody(200, {'ok': true}));
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.httpClientAdapter = _ScriptedAdapter((options) {
        if (options.extra['_retried'] == true) {
          return _jsonBody(200, {'ok': true});
        }
        throw DioException(
          requestOptions: options,
          response: Response<dynamic>(
            requestOptions: options,
            statusCode: 401,
            data: const {'message': 'Access token missing or invalid'},
          ),
        );
      });
      dio.interceptors.add(AuthInterceptor(
        tokenStore: store,
        refresher: _FakeRefresher(onRefresh: () async => 'fresh'),
        retryDio: retryDio,
      ));

      await dio.get<dynamic>('/api/students');

      // A recoverable expiry is not a dead session — nothing is wiped.
      expect(store.refreshToken, 'good-refresh');
    });

    test('a NETWORK failure never clears the session', () async {
      final w = wire(
        accessToken: 'good',
        refreshToken: 'good-refresh',
        responder: (options) => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        w.dio.get<dynamic>('/api/students'),
        throwsA(isA<DioException>()),
      );

      // A flaky connection at startup must not sign the user out.
      expect(w.store.accessToken, 'good');
      expect(w.store.refreshToken, 'good-refresh');
    });
  });
}

class _FakeRefresher implements TokenRefresher {
  _FakeRefresher({required this.onRefresh});

  final Future<String?> Function() onRefresh;

  @override
  Future<String?> refresh(String refreshToken) => onRefresh();
}
