import 'package:shared_preferences/shared_preferences.dart';

/// Login convenience (overhaul M2): the last institution this device signed in to,
/// so returning users are not asked to recall an institution code every time.
///
/// This is NOT a credential and NOT a session: it holds only the public
/// institution code, survives sign-out on purpose, and can be changed or
/// forgotten from the login screen. Signing in still requires the password and
/// any MFA the account's role demands.
abstract interface class RememberedInstitutionStore {
  Future<String?> read();
  Future<void> write(String code);
  Future<void> forget();
}

class SharedPreferencesRememberedInstitution
    implements RememberedInstitutionStore {
  const SharedPreferencesRememberedInstitution();

  static const _key = 'login.remembered_institution';

  @override
  Future<String?> read() async {
    final value = (await SharedPreferences.getInstance()).getString(_key);
    return value == null || value.trim().isEmpty ? null : value;
  }

  @override
  Future<void> write(String code) async =>
      (await SharedPreferences.getInstance()).setString(_key, code.trim());

  @override
  Future<void> forget() async =>
      (await SharedPreferences.getInstance()).remove(_key);
}

class InMemoryRememberedInstitution implements RememberedInstitutionStore {
  InMemoryRememberedInstitution([this.code]);
  String? code;
  @override
  Future<String?> read() async => code;
  @override
  Future<void> write(String value) async => code = value.trim();
  @override
  Future<void> forget() async => code = null;
}

/// `?institution=<code>` on the Web URL (an institution-issued link or QR code).
/// Only a hint for which institution to sign in to — never an authentication.
String? institutionFromLink(Uri uri) {
  final raw = uri.queryParameters['institution'] ?? uri.queryParameters['i'];
  if (raw == null) return null;
  final code = raw.trim().toLowerCase();
  // Institution codes are slugs; reject anything else rather than echoing it.
  return RegExp(r'^[a-z0-9][a-z0-9-]{1,62}$').hasMatch(code) ? code : null;
}
