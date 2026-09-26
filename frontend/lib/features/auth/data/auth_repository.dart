import 'package:dio/dio.dart';

import '../../../core/network/api_config.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/network/token_store.dart';
import '../../../core/widgets/states/screen_state.dart';

/// Result of a login attempt. Deliberately NOT a `ScreenState` — login is a
/// one-shot command, not a screen's data, and it has no "empty" or "cached"
/// case for the precedence rule to resolve.
sealed class LoginOutcome {
  const LoginOutcome();
}

class LoginSucceeded extends LoginOutcome {
  const LoginSucceeded({this.forcePasswordChange = false});

  /// The backend says this account must set a new password before doing
  /// anything else (a provisioned or admin-reset account). Carried out of
  /// the repository rather than acted on here, because it is a routing
  /// decision, not a network one.
  final bool forcePasswordChange;
}

class LoginFailed extends LoginOutcome {
  const LoginFailed(this.failure);

  final LoadFailure failure;
}

/// Login and logout against the CONFIRMED `/auth/*` endpoints.
///
/// Uses the shared [Dio] client from `buildApiClient()` — there is exactly
/// one HTTP client in this app. The auth interceptor on it is harmless here:
/// login carries no bearer token to attach, and a 401 from `/auth/login`
/// means "wrong password", which the interceptor leaves alone because there
/// is no stored refresh token to retry with on a fresh install.
class AuthRepository {
  const AuthRepository({required this.dio, required this.tokenStore});

  final Dio dio;
  final TokenStore tokenStore;

  /// `POST /auth/login` with `{institutionCode, username, password}` — all
  /// three required (confirmed against the live OpenAPI schema).
  ///
  /// On success both tokens are persisted before returning, so the shell
  /// that renders next already has a usable session.
  Future<LoginOutcome> login({
    required String institutionCode,
    required String username,
    required String password,
  }) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        ApiConfig.loginPath,
        data: {
          'institutionCode': institutionCode,
          'username': username,
          'password': password,
        },
      );

      final accessToken = response.data?['accessToken'] as String?;
      final refreshToken = response.data?['refreshToken'] as String?;

      if (accessToken == null) {
        return const LoginFailed(
          LoadFailure(message: 'The server did not return a session token.'),
        );
      }

      await tokenStore.writeTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
      // Persisted because no endpoint returns it afterwards — see TokenStore.
      await tokenStore.writeInstitutionCode(institutionCode);
      return LoginSucceeded(
        forcePasswordChange:
            response.data?['forcePasswordChange'] as bool? ?? false,
      );
    } on DioException catch (err) {
      // The backend's own message is shown verbatim — for a bad password it
      // is "Invalid credentials" (verified live), which is more useful and
      // more honest than a generic string.
      return LoginFailed(mapDioError(err));
    }
  }

  /// `POST /api/users/me/change-password` with the live-verified shape
  /// `{currentPassword, newPassword}`.
  ///
  /// On success the backend REVOKES EVERY SESSION, including this one, so
  /// local tokens are cleared here. The caller must return to login; there
  /// is no valid session left to continue with.
  Future<LoadFailure?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await dio.post<dynamic>(
        ApiConfig.changePasswordPath,
        data: {
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        },
      );
      await tokenStore.clear();
      return null;
    } on DioException catch (err) {
      return mapDioError(err);
    }
  }

  /// `POST /auth/logout` to invalidate the refresh token server-side, then
  /// clear local storage.
  ///
  /// Local tokens are cleared even if the network call fails: the user asked
  /// to sign out, and leaving a usable token on the device because the
  /// server was unreachable would be the wrong failure mode.
  Future<void> logout() async {
    final refreshToken = await tokenStore.readRefreshToken();
    if (refreshToken != null) {
      try {
        await dio.post<dynamic>(
          ApiConfig.logoutPath,
          data: {'refreshToken': refreshToken},
        );
      } on DioException {
        // Intentionally swallowed — see doc comment.
      }
    }
    await tokenStore.clear();
  }
}
