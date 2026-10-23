import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';
import 'auth_interceptor.dart';
import 'token_store.dart';

/// Stands in for the refresh token on Web. The real token lives only in the
/// backend's HttpOnly `ems_refresh` cookie (ADR-010); this marker lets the
/// existing refresh/rotation/race logic run unchanged without the secret ever
/// reaching Dart, storage or logs.
const String kCookieSession = 'cookie-session';

/// Web request rules (ADR-010, backend WebSessionCookies):
/// * every request says `X-EMS-Client: web`, so the server keeps the refresh
///   token in the cookie and out of response bodies;
/// * cookie-authenticated `/auth/refresh` and `/auth/logout` carry the
///   double-submit `X-CSRF-Token` and never send the [kCookieSession] marker;
/// * login/refresh responses get the marker back, so callers see a session.
class WebSessionInterceptor extends Interceptor {
  WebSessionInterceptor({required this.readCsrf});

  final String? Function() readCsrf;

  static bool _cookieRoute(String path) =>
      path == ApiConfig.refreshPath || path == ApiConfig.logoutPath;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['X-EMS-Client'] = 'web';
    if (_cookieRoute(options.path)) {
      final data = options.data;
      if (data is Map && data['refreshToken'] == kCookieSession) {
        options.data = Map.of(data)..remove('refreshToken');
      }
      final csrf = readCsrf();
      if (csrf != null) options.headers['X-CSRF-Token'] = csrf;
    }
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final path = response.requestOptions.path;
    final data = response.data;
    if ((path == ApiConfig.loginPath || path == ApiConfig.refreshPath) &&
        data is Map &&
        data['accessToken'] is String &&
        data['refreshToken'] == null) {
      response.data = Map<String, dynamic>.of(data.cast<String, dynamic>())
        ..['refreshToken'] = kCookieSession;
    }
    handler.next(response);
  }
}

/// Web token store: the access token is kept in MEMORY only (never
/// localStorage), the refresh token is the cookie marker, and only the
/// non-secret institution code is persisted. A reload starts with no access
/// token; [hasCookieSession] lets restore ask the server via the cookie.
class WebSessionTokenStore implements TokenStore {
  WebSessionTokenStore({required this.hasCookieSession});

  /// True when the script-visible CSRF cookie exists, i.e. the browser may
  /// still hold a refresh cookie. The server decides whether it is valid.
  final bool Function() hasCookieSession;

  String? _access;
  bool _signedOut = false;
  static const _institutionKey = 'auth.institution_code';

  @override
  Future<String?> readAccessToken() async => _access;

  @override
  Future<String?> readRefreshToken() async =>
      !_signedOut && (_access != null || hasCookieSession()) ? kCookieSession : null;

  @override
  Future<String?> readInstitutionCode() async =>
      (await SharedPreferences.getInstance()).getString(_institutionKey);

  @override
  Future<void> writeTokens({required String accessToken, String? refreshToken}) async {
    _access = accessToken;
    _signedOut = false;
  }

  @override
  Future<void> writeInstitutionCode(String institutionCode) async =>
      (await SharedPreferences.getInstance()).setString(_institutionKey, institutionCode);

  @override
  Future<void> clear() async {
    _access = null;
    _signedOut = true;
  }
}

/// Serializes refreshes across browser tabs (see `withCrossTabLock`).
class CrossTabRefresher implements TokenRefresher {
  CrossTabRefresher(this.inner, this.withLock);

  final TokenRefresher inner;
  final Future<String?> Function(Future<String?> Function()) withLock;

  @override
  Future<String?> refresh(String refreshToken) => withLock(() => inner.refresh(refreshToken));
}
