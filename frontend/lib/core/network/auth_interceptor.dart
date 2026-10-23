import 'dart:convert';
import 'package:dio/dio.dart';

import 'api_config.dart';
import 'token_store.dart';

/// Performs the actual refresh call. A seam, not a hardcoded Dio call inside
/// the interceptor — the real implementation ([DioTokenRefresher]) hits
/// [ApiConfig.refreshPath] (UNCONFIRMED, see `api_config.dart`); tests supply
/// a fake that never touches the network.
abstract interface class TokenRefresher {
  /// Returns the new access token, or null if refresh failed (expired/
  /// revoked refresh token — caller should treat this as a hard sign-out).
  Future<String?> refresh(String refreshToken);
}

/// Attaches the bearer token to outgoing requests and retries once, after a
/// refresh, on 401.
///
/// Two rules keep a dead session from becoming a lockout, both added after
/// one did exactly that:
///
///  - the token is NEVER attached to the endpoints that exist to obtain one
///    (see [unauthenticatedPaths]);
///  - when the server rejects the token AND it cannot be refreshed, local
///    tokens are CLEARED rather than left to be re-sent forever.
///
/// Clearing happens only on a real 401 from the server, never on a network
/// failure — a flaky connection at startup must not sign the user out.
///
/// The one property worth a test on its own: if N requests are in flight
/// when the token expires, exactly ONE refresh call happens, not N — the
/// rest wait on the same in-flight [Future] rather than each firing their
/// own refresh. See `_refreshInFlight`.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.tokenStore,
    required this.refresher,
    required this.retryDio,
  });

  final TokenStore tokenStore;
  final TokenRefresher refresher;

  /// A separate [Dio] instance (no interceptors) used to replay a request
  /// after refresh — reusing the intercepted client would re-enter this
  /// interceptor.
  final Dio retryDio;

  bool _matchesAttendanceOwner(RequestOptions options, String? token) {
    final expected =
        options.extra['expectedOwner'] ?? options.extra['attendanceOwner'];
    if (expected == null) return true;
    try {
      if (token == null) return false;
      final claims =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(base64Url.normalize(token.split('.')[1])),
                ),
              )
              as Map;
      return expected == '${claims['tid']}:${claims['sub']}';
    } catch (_) {
      return false;
    }
  }

  Future<String?>? _refreshInFlight;

  /// Endpoints that must NEVER carry a bearer token.
  ///
  /// 🔴 This is load-bearing, and its absence caused a real lockout.
  ///
  /// These two endpoints exist to OBTAIN a token, so they are reached
  /// precisely when the stored one is missing, expired or otherwise dead.
  /// The backend checks the `Authorization` header at the gate, before the
  /// login handler runs: a stale token on `POST /auth/login` is rejected
  /// with `401 "Access token missing or invalid"` — the login is never even
  /// attempted, and the message names the wrong problem entirely.
  ///
  /// Verified live 2026-09-25, same credentials in all three cases:
  ///   - no header          → **200**, signed in
  ///   - stale header       → 401 "Access token missing or invalid"
  ///   - wrong password     → 401 "Invalid credentials"
  ///
  /// Because nothing cleared the dead token, every later attempt re-sent it:
  /// the user could not sign in, and could not sign out to fix it either.
  /// `/auth/logout` is deliberately NOT in this set — it authenticates the
  /// session it is ending.
  static const Set<String> unauthenticatedPaths = {
    ApiConfig.loginPath,
    ApiConfig.refreshPath,
  };

  /// Endpoints whose 401 can mean "this code was not accepted" (DEF-22).
  static const Set<String> codeCheckPaths = {
    ApiConfig.mfaVerifyPath,
    ApiConfig.mfaStepUpPath,
    ApiConfig.mfaEnrollmentConfirmPath,
    // A wrong CURRENT password is also answered 401; replaying it after a
    // refresh counted a second failed password attempt.
    '/api/users/me/change-password',
  };

  /// The gate's message for a missing/expired/invalid access token (verified
  /// against the backend; a rejected code says "Invalid verification code").
  static bool _isTokenRejection(Object? body) {
    final data = body is String ? _tryDecode(body) : body;
    return data is Map && data['message'] == 'Access token missing or invalid';
  }

  static Object? _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (unauthenticatedPaths.contains(options.uri.path)) {
      // Strip anything already set, so a caller cannot reintroduce the bug
      // by attaching a header itself.
      options.headers.remove('Authorization');
      handler.next(options);
      return;
    }

    final token = await tokenStore.readAccessToken();
    if (!_matchesAttendanceOwner(options, token)) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
          error: 'Attendance account changed',
        ),
      );
      return;
    }
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    final alreadyRetried = err.requestOptions.extra['_retried'] == true;

    if (response?.statusCode != 401 || alreadyRetried) {
      handler.next(err);
      return;
    }

    // Login/refresh rejection must never refresh or erase a different session.
    if (unauthenticatedPaths.contains(err.requestOptions.uri.path)) {
      handler.next(err);
      return;
    }
    // DEF-22: on a code-checking endpoint a 401 usually means the CODE was
    // rejected ("Invalid verification code"), not that the token expired.
    // Refreshing and replaying it re-submitted the same wrong code, counting a
    // second failure toward the MFA lockout. Only a genuine token rejection is
    // refreshed and retried here.
    if (codeCheckPaths.contains(err.requestOptions.uri.path) &&
        !_isTokenRejection(response?.data)) {
      handler.next(err);
      return;
    }
    final refreshToken = await tokenStore.readRefreshToken();
    if (refreshToken == null) {
      // The server rejected the token and there is nothing to recover with.
      await _clearIfCurrent(null);
      handler.next(err);
      return;
    }

    String? newAccessToken;
    try {
      newAccessToken = await _singleFlightRefresh(refreshToken);
    } on DioException catch (refreshError) {
      handler.next(
        DioException(
          requestOptions: err.requestOptions,
          response: refreshError.response,
          type: refreshError.type,
          error: refreshError.error,
        ),
      );
      return;
    } catch (error) {
      // Storage and unexpected refresh failures are not proof of revocation.
      handler.next(
        DioException(
          requestOptions: err.requestOptions,
          type: DioExceptionType.unknown,
          error: error,
        ),
      );
      return;
    }
    if (newAccessToken == null) {
      // Refresh failed too — the session is dead, not merely stale.
      await _clearIfCurrent(refreshToken);
      handler.next(err);
      return;
    }

    if (!_matchesAttendanceOwner(err.requestOptions, newAccessToken)) {
      handler.next(err);
      return;
    }
    final retryOptions = err.requestOptions
      ..headers['Authorization'] = 'Bearer $newAccessToken'
      ..extra['_retried'] = true;

    if (retryOptions.data is FormData) {
      retryOptions.data = (retryOptions.data as FormData).clone();
    }
    try {
      final retryResponse = await retryDio.fetch<dynamic>(retryOptions);
      handler.resolve(retryResponse);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  /// Ensures concurrent 401s share one refresh call. The first caller starts
  /// [refresher.refresh] and stores the [Future]; every caller that arrives
  /// while it is still running awaits that SAME future instead of starting
  /// its own. Cleared once it settles so the next expiry starts a fresh one.
  /// Persisting the new tokens is the [TokenRefresher]'s job, not this
  /// method's — the backend ROTATES refresh tokens, so only the refresher
  /// sees the new refresh token in the response body. Writing the access
  /// token here too would be a redundant second write that cannot carry the
  /// rotated refresh token with it.
  Future<void> _clearIfCurrent(String? refreshToken) async {
    final store = tokenStore;
    if (store is ConditionalTokenStore) {
      await store.clearIfCurrent(refreshToken);
    } else {
      await store.clear();
    }
  }

  Future<String?> _singleFlightRefresh(String refreshToken) {
    return _refreshInFlight ??= refresher
        .refresh(refreshToken)
        .whenComplete(() => _refreshInFlight = null);
  }
}
