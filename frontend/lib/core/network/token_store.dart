import 'dart:async';
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

/// Atomic within the single application isolate. Browser multi-tab coordination
/// is separate and must be implemented with the cookie transport.
abstract interface class ConditionalTokenStore implements TokenStore {
  Future<bool> rotateIfCurrent(
    String expectedRefresh,
    String access,
    String refresh,
  );
  Future<bool> clearIfCurrent(String? expectedRefresh);
}

class SerializedTokenStore implements ConditionalTokenStore {
  SerializedTokenStore(this.delegate);
  final TokenStore delegate;
  Future<void> _tail = Future<void>.value();
  Future<T> _run<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  @override
  Future<String?> readAccessToken() => _run(delegate.readAccessToken);
  @override
  Future<String?> readRefreshToken() => _run(delegate.readRefreshToken);
  @override
  Future<String?> readInstitutionCode() => _run(delegate.readInstitutionCode);
  @override
  Future<void> writeTokens({
    required String accessToken,
    required String? refreshToken,
  }) => _run(
    () => delegate.writeTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    ),
  );
  @override
  Future<void> writeInstitutionCode(String code) =>
      _run(() => delegate.writeInstitutionCode(code));
  @override
  Future<void> clear() => _run(delegate.clear);
  @override
  Future<bool> rotateIfCurrent(
    String expectedRefresh,
    String access,
    String refresh,
  ) => _run(() async {
    if (await delegate.readRefreshToken() != expectedRefresh) return false;
    await delegate.writeTokens(accessToken: access, refreshToken: refresh);
    return true;
  });
  @override
  Future<bool> clearIfCurrent(String? expectedRefresh) => _run(() async {
    if (await delegate.readRefreshToken() != expectedRefresh) return false;
    await delegate.clear();
    return true;
  });
}
