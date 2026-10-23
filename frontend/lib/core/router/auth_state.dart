import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../network/api_config.dart';
import '../network/token_store.dart';
import '../shell/identity_resolver.dart';
import '../shell/role_destinations.dart';
import '../shell/campus_context.dart';
import '../../features/auth/data/mfa_repository.dart';

/// ADR-011 workspace: school operations vs. personal (parent/student) access.
enum Workspace { school, personal }

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
    this.mfa,
    this.campus,
  });

  final TokenStore tokenStore;
  final IdentityResolver identityResolver;

  /// Used only to fetch the institution's display name. Optional so tests
  /// that do not care about it need no HTTP stub.
  final Dio? dio;

  /// Two-factor status source (ADR-010). Null in tests that do not exercise
  /// MFA; the backend still enforces it on every request regardless.
  final MfaRepository? mfa;

  /// ADR-011 campus context, reloaded with every capability refresh.
  final CampusContext? campus;

  /// True while the server reports this session as restricted (pre-MFA).
  /// The router holds the user on the two-factor screen until it clears.
  bool get mfaPending => _mfaPending;
  bool _mfaPending = false;

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
  String get institutionLabel => _institutionName?.isNotEmpty == true
      ? _institutionName!
      : _institutionCode;
  String? _institutionName;

  /// Institution profile (Academy Phase B). Navigation only; the server
  /// authorises every request.
  ///
  /// Four distinct states, never conflated:
  /// - [ProfileLookup.loaded] + `SCHOOL` with [profileExplicit] false: no profile
  ///   row exists and the SERVER resolved the default (SCHOOL);
  /// - [ProfileLookup.loaded] + an explicit SCHOOL / PRE_UNIVERSITY_COLLEGE;
  /// - [ProfileLookup.loaded] + `ACADEMY`;
  /// - [ProfileLookup.failed]: the lookup failed. NOT treated as SCHOOL: no
  ///   Academy workflow is shown and the shell offers an explicit retry.
  /// School workflows stay available in every state — they exist for all profiles.
  ProfileLookup get profileLookup => _profileLookup;
  ProfileLookup _profileLookup = ProfileLookup.unknown;

  /// The server's profile value; null unless [ProfileLookup.loaded].
  String? get institutionProfile => _institutionProfile;
  String? _institutionProfile;

  /// True when an explicit profile row exists (the server sent `updatedAt`).
  bool get profileExplicit => _profileExplicit;
  bool _profileExplicit = false;

  bool get academyEnabled =>
      _profileLookup == ProfileLookup.loaded &&
      _institutionProfile == 'ACADEMY';

  /// Re-reads the profile (after an owner changes it, or on retry) and rebuilds the shell.
  Future<void> reloadInstitutionProfile() async {
    _profileLookup = ProfileLookup.loading;
    notifyListeners();
    await _loadInstitutionProfile();
    notifyListeners();
  }

  Future<void> _loadInstitutionProfile() async {
    final client = dio;
    if (client == null) return;
    _profileLookup = ProfileLookup.loading;
    try {
      final res = await client.get<Map<String, dynamic>>(
        '/api/institution/profile',
      );
      final profile = res.data?['profile'];
      if (profile is! String || profile.isEmpty) {
        throw const FormatException('profile missing');
      }
      _institutionProfile = profile;
      _profileExplicit = res.data?['updatedAt'] != null;
      _profileLookup = ProfileLookup.loaded;
    } on Object {
      // DioException (network, 4xx/5xx) or a malformed body: UNKNOWN, not SCHOOL.
      _institutionProfile = null;
      _profileExplicit = false;
      _profileLookup = ProfileLookup.failed;
    }
  }

  bool get isSignedIn => _identity != null;

  /// A stored session exists but the server could not be reached to resume it
  /// (F12). Credentials and the offline attendance queue are kept; the router
  /// shows an offline screen with retry instead of the login form.
  bool get offlineRestore => _offlineRestore;
  bool _offlineRestore = false;

  /// The last temporary restore failure was rate limiting (429), not lost
  /// connectivity. Wording only: the gate and its retries are the same.
  bool get restoreServerBusy => _restoreServerBusy;
  bool _restoreServerBusy = false;

  /// Retry resuming the stored session from the offline screen.
  Future<void> retryRestore() async {
    await completeSignIn();
  }

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
    try {
      final token = await tokenStore.readAccessToken();
      // Web keeps no access token across reloads: a cookie session is
      // resumed by the first request's 401 -> cookie refresh (ADR-010).
      if (token != null || await tokenStore.readRefreshToken() != null) {
        await completeSignIn();
      }
    } catch (_) {
      // Locked/corrupt storage must not leave an endless splash or erase
      // credentials/attendance. A fresh login may retry the credential write.
      _identity = null;
    } finally {
      _isRestored = true;
      notifyListeners();
    }
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
    if (result.kind == IdentityResultKind.error && result.temporary) {
      // F12: the server is unreachable or temporarily down. The stored session
      // is not known to be dead: never present that as "signed out". Keep the
      // current identity mid-session; on a cold start show the offline gate.
      if (_identity == null) _offlineRestore = true;
      _restoreServerBusy = result.serverBusy;
      notifyListeners();
      return;
    }
    _offlineRestore = false;
    _restoreServerBusy = false;
    if (result.kind == IdentityResultKind.error) {
      _identity = null;
      _institutionCode = '';
    } else {
      _identity = result;
      _institutionCode = await tokenStore.readInstitutionCode() ?? '';
      await campus?.load(tenantId: result.tenantId, userId: result.userId);
      await _loadInstitutionName();
      await _loadInstitutionProfile();
    }
    notifyListeners();
  }

  /// Best-effort: a failure here leaves [institutionLabel] on the code
  /// rather than blocking sign-in over a cosmetic field.
  Future<void> _loadInstitutionName() async {
    final client = dio;
    if (client == null) return;
    try {
      final res = await client.get<Map<String, dynamic>>(
        ApiConfig.institutionMePath,
      );
      _institutionName = res.data?['name'] as String?;
    } on DioException {
      _institutionName = null;
    }
  }

  /// After the password step (and on restore): two-factor first, identity
  /// only once the session may reach ordinary APIs.
  Future<void> completeSignIn() async {
    if (await checkMfa()) return;
    await refreshIdentity();
  }

  /// Asks the server whether this session is restricted. A failed check
  /// leaves the flag unchanged; the backend still answers 403 MFA_REQUIRED.
  Future<bool> checkMfa() async {
    final repo = mfa;
    if (repo == null) return false;
    final result = await repo.status();
    final pending = result.status?.pending ?? _mfaPending;
    if (pending != _mfaPending) {
      _mfaPending = pending;
      notifyListeners();
    }
    return pending;
  }

  /// Called by the two-factor screen once the server accepted a code.
  Future<void> mfaVerified() async {
    _mfaPending = false;
    await refreshIdentity();
  }

  /// A protected request answered 403 MFA_REQUIRED (e.g. the factor was
  /// reset elsewhere): return to the two-factor screen, keep the session.
  void markMfaRequired() {
    if (_mfaPending) return;
    _mfaPending = true;
    notifyListeners();
  }

  /// ADR-011: one login, two authorization contexts. Null = default (school
  /// when the account has it).
  Workspace? _preferredWorkspace;

  Workspace get workspace {
    final roles = _identity?.roles ?? const <String>[];
    final school = RoleDestinations.hasSchoolWorkspace(roles);
    final personal = RoleDestinations.hasPersonalWorkspace(roles);
    if (school && personal) return _preferredWorkspace ?? Workspace.school;
    return school || !personal ? Workspace.school : Workspace.personal;
  }

  bool get canSwitchWorkspace {
    final roles = _identity?.roles ?? const <String>[];
    return RoleDestinations.hasSchoolWorkspace(roles) &&
        RoleDestinations.hasPersonalWorkspace(roles);
  }

  /// Switching refreshes capabilities from the server (ADR-011), so a revoked
  /// grant or guardian link disappears instead of lingering in the shell.
  Future<void> switchWorkspace(Workspace target) async {
    _preferredWorkspace = target;
    await refreshIdentity();
  }

  void clear() {
    _identity = null;
    campus?.clear();
    _preferredWorkspace = null;
    _mfaPending = false;
    _offlineRestore = false;
    _institutionCode = '';
    _institutionName = null;
    _profileLookup = ProfileLookup.unknown;
    _institutionProfile = null;
    _profileExplicit = false;
    _mustChangePassword = false;
    notifyListeners();
  }
}

/// Institution-profile lookup state (Academy Phase B). See [AuthState.profileLookup].
enum ProfileLookup { unknown, loading, loaded, failed }
