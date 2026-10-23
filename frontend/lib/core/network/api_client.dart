import 'package:dio/dio.dart';

import 'api_config.dart';
import 'auth_interceptor.dart';
import 'test_ca_trust.dart';
import 'token_store.dart';
import 'web_session.dart';

/// Hits [ApiConfig.refreshPath] — CONFIRMED shape (2026-08-03):
/// `POST {refreshToken}` → `{accessToken, refreshToken, expiresIn}`.
///
/// The backend **rotates refresh tokens**: the response carries a NEW
/// refresh token, not just a new access token. T6 read only `accessToken`
/// and stored `refreshToken: null`, which meant the rotated token was
/// discarded and the stale one kept — so once the original expired (30d,
/// or sooner if the backend invalidates on use) refresh would fail
/// permanently and silently log the user out. Both tokens are now
/// persisted.
class DioTokenRefresher implements TokenRefresher {
  DioTokenRefresher(this._plainDio, this._tokenStore);

  final Dio _plainDio;
  final TokenStore _tokenStore;

  @override
  Future<String?> refresh(String refreshToken) async {
    try {
      final response = await _plainDio.post<Map<String, dynamic>>(
        ApiConfig.refreshPath,
        data: {'refreshToken': refreshToken},
      );
      final accessToken = response.data?['accessToken'] as String?;
      final rotatedRefreshToken = response.data?['refreshToken'] as String?;
      if (accessToken == null ||
          accessToken.isEmpty ||
          rotatedRefreshToken == null ||
          rotatedRefreshToken.isEmpty) {
        throw DioException(
          requestOptions: response.requestOptions,
          type: DioExceptionType.unknown,
          error: 'Incomplete refresh response',
        );
      }
      final store = _tokenStore;
      if (store is ConditionalTokenStore) {
        final saved = await store.rotateIfCurrent(
          refreshToken,
          accessToken,
          rotatedRefreshToken,
        );
        if (!saved) {
          throw DioException(
            requestOptions: response.requestOptions,
            type: DioExceptionType.cancel,
            error: 'Session changed during refresh',
          );
        }
      } else {
        await store.writeTokens(
          accessToken: accessToken,
          refreshToken: rotatedRefreshToken,
        );
      }
      return accessToken;
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) return null;
      rethrow;
    }
  }
}

/// Builds the single [Dio] instance every repository should share — base
/// URL, timeouts, and the auth interceptor wired in one place so nothing
/// under `lib/` hand-rolls its own HTTP client.
/// [web] installs the ADR-010 cookie-session rules on BOTH clients (the plain
/// one performs refresh) and serializes refreshes across browser tabs.
Dio buildApiClient({
  required TokenStore tokenStore,
  bool web = false,
  String? Function()? readCsrf,
  Future<String?> Function(Future<String?> Function())? crossTabLock,
}) {
  final baseOptions = BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: ApiConfig.connectTimeout,
    receiveTimeout: ApiConfig.receiveTimeout,
    headers: const {'Content-Type': 'application/json'},
  );

  // A second, interceptor-free client: used both for the refresh call itself
  // (must not recurse into the auth interceptor it would otherwise trigger)
  // and for replaying a request after a successful refresh.
  final plainDio = Dio(baseOptions);

  final dio = Dio(baseOptions);
  // Local rehearsal on a physical device: trust only the test CA (non-release only).
  final testTrust = testCaAdapter();
  if (testTrust != null) {
    plainDio.httpClientAdapter = testTrust;
    dio.httpClientAdapter = testTrust;
  }
  TokenRefresher refresher = DioTokenRefresher(plainDio, tokenStore);
  if (web) {
    final session = WebSessionInterceptor(readCsrf: readCsrf ?? () => null);
    plainDio.interceptors.add(session);
    dio.interceptors.add(session);
    if (crossTabLock != null) refresher = CrossTabRefresher(refresher, crossTabLock);
  }
  dio.interceptors.add(
    AuthInterceptor(
      tokenStore: tokenStore,
      refresher: refresher,
      retryDio: plainDio,
    ),
  );
  return dio;
}
