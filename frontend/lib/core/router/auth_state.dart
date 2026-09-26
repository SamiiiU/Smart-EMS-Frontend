import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../network/api_config.dart';
import '../network/token_store.dart';
import '../shell/identity_resolver.dart';

/// The single source of truth for "is someone signed in, and who".
///
/// A [ChangeNotifier] so `GoRouter` can listen to it: every change
/// re-evaluates the redirect, which is what makes sign-in and sign-out move
/// the user between routes without any screen calling `go()` itself.
class AuthState extends ChangeNotifier {
  AuthState({
    required this.tokenStore,
    required this.identityResolver,
    this.dio,
  });

  final TokenStore tokenStore;
  final IdentityResolver identityResolver;

  /// Used only to fetch the institution's display name. Optional so tests
  /// that do not care about it need no HTTP stub.
  final Dio? dio;

  /// False until the stored session has been checked. The router shows a
  /// neutral splash while this is false rather than flashing the login
  /// screen at a user who is already signed in.
  bool get isRestored => _isRestored;
  bool _isRestored = false;

  IdentityResult? get identity => _identity;
  IdentityResult? _identity;

  String get institutionCode => _institutionCode;
  String _institutionCode = '';

  /// The institution's real display name from `/api/institution/me`, e.g.
  /// "Test School". Falls back to the code until it loads, or if the call
  /// fails — a slightly ugly label beats an empty app bar.
  String get institutionLabel =>
      _institutionName?.isNotEmpty == true ? _institutionName! : _institutionCode;
  String? _institutionName;

  bool get isSignedIn => _identity != null;

  /// True when the backend demanded a password change at login. The router
  /// holds the user on the change-password route until it clears.
  bool get mustChangePassword => _mustChangePassword;
  bool _mustChangePassword = false;

  set mustChangePassword(bool value) {
    if (_mustChangePassword == value) return;
    _mustChangePassword = value;
    notifyListeners();
  }

  /// Called once at startup.
  Future<void> restore() async {
    final token = await tokenStore.readAccessToken();
    if (token == null) {
      _isRestored = true;
      notifyListeners();
      return;
    }
    await refreshIdentity();
    _isRestored = true;
    notifyListeners();
  }

  /// Resolves identity and publishes it. Called after a successful login and
  /// on restore.
  ///
  /// An `error` result means the stored session is dead (expired refresh
  /// token, revoked account) — treated as signed out. `notLinked` is NOT
  /// that case: it is a real authenticated user whose person record is
  /// missing, and the shell owns showing them `UnlinkedProfileState`.
  Future<void> refreshIdentity() async {
    final result = await identityResolver.resolveIdentity();
    if (result.kind == IdentityResultKind.error) {
      _identity = null;
      _institutionCode = '';
    } else {
      _identity = result;
      _institutionCode = await tokenStore.readInstitutionCode() ?? '';
      await _loadInstitutionName();
    }
    notifyListeners();
  }

  /// Best-effort: a failure here leaves [institutionLabel] on the code
  /// rather than blocking sign-in over a cosmetic field.
  Future<void> _loadInstitutionName() async {
    final client = dio;
    if (client == null) return;
    try {
      final res =
          await client.get<Map<String, dynamic>>(ApiConfig.institutionMePath);
      _institutionName = res.data?['name'] as String?;
    } on DioException {
      _institutionName = null;
    }
  }

  void clear() {
    _identity = null;
    _institutionCode = '';
    _institutionName = null;
    _mustChangePassword = false;
    notifyListeners();
  }
}
