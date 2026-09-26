import 'package:dio/dio.dart';

import 'api_config.dart';
import 'auth_interceptor.dart';
import 'token_store.dart';

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
      if (accessToken != null) {
        await _tokenStore.writeTokens(
          accessToken: accessToken,
          refreshToken: rotatedRefreshToken,
        );
      }
      return accessToken;
    } on DioException {
      return null;
    }
  }
}

/// Builds the single [Dio] instance every repository should share — base
/// URL, timeouts, and the auth interceptor wired in one place so nothing
/// under `lib/` hand-rolls its own HTTP client.
Dio buildApiClient({required TokenStore tokenStore}) {
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
  dio.interceptors.add(
    AuthInterceptor(
      tokenStore: tokenStore,
      refresher: DioTokenRefresher(plainDio, tokenStore),
      retryDio: plainDio,
    ),
  );
  return dio;
}
