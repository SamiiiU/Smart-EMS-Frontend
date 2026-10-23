import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartems/core/network/api_client.dart';
import 'package:smartems/core/network/api_config.dart';
import 'package:smartems/core/network/auth_interceptor.dart';
import 'package:smartems/core/network/token_store.dart';
import 'package:smartems/core/network/web_session.dart';

class _Server implements HttpClientAdapter {
  _Server(this.responder);
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'web requests never carry or persist the refresh token, and send CSRF',
    () async {
      final server = _Server((o) async {
        if (o.path == ApiConfig.loginPath)
          return _json(200, {
            'accessToken': 'a1',
            'refreshToken': null,
            'expiresIn': 900,
          });
        if (o.path == ApiConfig.refreshPath)
          return _json(200, {
            'accessToken': 'a2',
            'refreshToken': null,
            'expiresIn': 900,
          });
        if (o.path == ApiConfig.mePath) {
          return o.headers['Authorization'] == 'Bearer a2'
              ? _json(200, {'roles': []})
              : _json(401, {});
        }
        return _json(200, {});
      });
      final store = SerializedTokenStore(
        WebSessionTokenStore(hasCookieSession: () => false),
      );
      final dio = buildApiClient(
        tokenStore: store,
        web: true,
        readCsrf: () => 'csrf-1',
      );
      dio.httpClientAdapter = server;
      // The plain refresh client shares the adapter through the retry path.
      final login = await dio.post<Map<String, dynamic>>(
        ApiConfig.loginPath,
        data: {'username': 'x'},
      );
      expect(
        login.data?['refreshToken'],
        kCookieSession,
        reason: 'marker, never the secret',
      );
      await store.writeTokens(accessToken: 'a1', refreshToken: kCookieSession);

      expect(server.requests.first.headers['X-EMS-Client'], 'web');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where((k) => k.contains('token')),
        isEmpty,
        reason: 'nothing in localStorage',
      );
    },
  );

  test(
    'cookie refresh/logout strip the marker and add the CSRF header',
    () async {
      final seen = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))
        ..httpClientAdapter = _Server((o) async {
          seen.add(o);
          return _json(200, {'accessToken': 'a2', 'refreshToken': null});
        })
        ..interceptors.add(WebSessionInterceptor(readCsrf: () => 'csrf-1'));
      final res = await dio.post<Map<String, dynamic>>(
        ApiConfig.refreshPath,
        data: {'refreshToken': kCookieSession},
      );
      expect((seen.single.data as Map).containsKey('refreshToken'), isFalse);
      expect(seen.single.headers['X-CSRF-Token'], 'csrf-1');
      expect(res.data?['refreshToken'], kCookieSession);
      await dio.post<dynamic>(
        ApiConfig.logoutPath,
        data: {'refreshToken': kCookieSession},
      );
      expect((seen.last.data as Map).containsKey('refreshToken'), isFalse);
      expect(seen.last.headers['X-CSRF-Token'], 'csrf-1');
    },
  );

  test(
    'memory store: reload resumes only via a cookie session; logout forgets it',
    () async {
      var cookie = true;
      final store = WebSessionTokenStore(hasCookieSession: () => cookie);
      expect(await store.readAccessToken(), isNull);
      expect(
        await store.readRefreshToken(),
        kCookieSession,
        reason: 'restore may ask the server',
      );
      await store.writeTokens(accessToken: 'a', refreshToken: kCookieSession);
      expect(await store.readAccessToken(), 'a');
      await store.clear();
      expect(await store.readAccessToken(), isNull);
      expect(
        await store.readRefreshToken(),
        isNull,
        reason: 'signed out in this tab',
      );
      cookie = false;
      expect(
        await WebSessionTokenStore(
          hasCookieSession: () => cookie,
        ).readRefreshToken(),
        isNull,
      );
    },
  );

  test('refreshes are serialized through the cross-tab lock', () async {
    var running = 0, maxConcurrent = 0;
    final inner = _CountingRefresher(() async {
      running++;
      maxConcurrent = running > maxConcurrent ? running : maxConcurrent;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      running--;
      return 'a';
    });
    var tail = Future<void>.value();
    Future<String?> lock(Future<String?> Function() action) {
      final result = tail.then((_) => action());
      tail = result.then((_) {}, onError: (_) {});
      return result;
    }

    final refresher = CrossTabRefresher(inner, lock);
    await Future.wait([
      refresher.refresh('x'),
      refresher.refresh('x'),
      refresher.refresh('x'),
    ]);
    expect(maxConcurrent, 1);
    expect(inner.calls, 3);
  });
}

class _CountingRefresher implements TokenRefresher {
  _CountingRefresher(this.body);
  final Future<String?> Function() body;
  int calls = 0;
  @override
  Future<String?> refresh(String refreshToken) {
    calls++;
    return body();
  }
}
