import 'package:shared_preferences/shared_preferences.dart';

/// Where the session lives between app launches: the bearer (access) and
/// refresh tokens, plus the institution code.
///
/// The institution code is kept here because nothing else can recover it.
/// It is required to log in, but no endpoint returns it afterwards —
/// `/auth/me` yields only `roles`, `userId` and `tenantId` (D-41) — so
/// without persisting it the shell has nothing to display on a relaunch
/// that skips the login screen.
abstract interface class TokenStore {
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<String?> readInstitutionCode();
  Future<void> writeTokens({
    required String accessToken,
    required String? refreshToken,
  });
  Future<void> writeInstitutionCode(String institutionCode);
  Future<void> clear();
}

class SharedPreferencesTokenStore implements TokenStore {
  const SharedPreferencesTokenStore();

  static const _accessKey = 'auth.access_token';
  static const _refreshKey = 'auth.refresh_token';
  static const _institutionKey = 'auth.institution_code';

  @override
  Future<String?> readAccessToken() async =>
      (await SharedPreferences.getInstance()).getString(_accessKey);

  @override
  Future<String?> readRefreshToken() async =>
      (await SharedPreferences.getInstance()).getString(_refreshKey);

  @override
  Future<String?> readInstitutionCode() async =>
      (await SharedPreferences.getInstance()).getString(_institutionKey);

  @override
  Future<void> writeTokens({
    required String accessToken,
    required String? refreshToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessKey, accessToken);
    if (refreshToken != null) {
      await prefs.setString(_refreshKey, refreshToken);
    }
  }

  @override
  Future<void> writeInstitutionCode(String institutionCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_institutionKey, institutionCode);
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
    await prefs.remove(_institutionKey);
  }
}

/// Test/in-memory stand-in — avoids every auth test needing plugin mocking
/// for `SharedPreferences`.
class InMemoryTokenStore implements TokenStore {
  InMemoryTokenStore({
    this.accessToken,
    this.refreshToken,
    this.institutionCode,
  });

  String? accessToken;
  String? refreshToken;
  String? institutionCode;

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<String?> readInstitutionCode() async => institutionCode;

  @override
  Future<void> writeTokens({
    required String accessToken,
    required String? refreshToken,
  }) async {
    this.accessToken = accessToken;
    if (refreshToken != null) this.refreshToken = refreshToken;
  }

  @override
  Future<void> writeInstitutionCode(String institutionCode) async {
    this.institutionCode = institutionCode;
  }

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    institutionCode = null;
  }
}
