import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'token_store.dart';

/// Native credentials are stored together to avoid partially rotated token pairs.
/// Never deletes the separate attendance vault or falls back to plaintext.
class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
    : storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: false),
          );
  final FlutterSecureStorage storage;
  static const key = 'auth.native.session.v1';
  Future<void>? _ready;

  Future<void> _prepare() =>
      _ready ??= _removeLegacy().catchError((Object error) {
        _ready = null;
        throw error;
      });
  Future<void> _removeLegacy() async {
    final prefs = await SharedPreferences.getInstance();
    // V40 rejects old session-less credentials. Require fresh login instead
    // of copying untrusted historical credentials into the new vault.
    await prefs.remove('auth.access_token');
    await prefs.remove('auth.refresh_token');
  }

  Future<Map<String, dynamic>> _read() async {
    await _prepare();
    final value = await storage.read(key: key);
    if (value == null) return {};
    final data = jsonDecode(value) as Map<String, dynamic>;
    if (data['version'] != 1) {
      throw StateError('Unsupported session storage version');
    }
    return data;
  }

  @override
  Future<String?> readAccessToken() async =>
      (await _read())['access'] as String?;
  @override
  Future<String?> readRefreshToken() async =>
      (await _read())['refresh'] as String?;
  @override
  Future<void> writeTokens({
    required String accessToken,
    required String? refreshToken,
  }) async {
    await _prepare();
    if (accessToken.isEmpty || refreshToken == null || refreshToken.isEmpty) {
      throw StateError('A complete session token pair is required');
    }
    await storage.write(
      key: key,
      value: jsonEncode({
        'version': 1,
        'access': accessToken,
        'refresh': refreshToken,
      }),
    );
  }

  @override
  Future<String?> readInstitutionCode() async =>
      (await SharedPreferences.getInstance()).getString(
        'auth.institution_code',
      );
  @override
  Future<void> writeInstitutionCode(String institutionCode) async {
    await (await SharedPreferences.getInstance()).setString(
      'auth.institution_code',
      institutionCode,
    );
  }

  @override
  Future<void> clear() async {
    await _prepare();
    await storage.delete(key: key);
    await (await SharedPreferences.getInstance()).remove(
      'auth.institution_code',
    );
  }
}
