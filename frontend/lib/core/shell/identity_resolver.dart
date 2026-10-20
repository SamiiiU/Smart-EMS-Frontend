import 'package:flutter/foundation.dart';

enum IdentityResultKind {
  /// `/me` resolved to a person record. The shell may render.
  linked,

  /// `/me` returned 404 — the login exists but was never linked to a person
  /// record (D-17's orphan case). Renders [UnlinkedProfileState], never a
  /// retry.
  notLinked,

  /// Anything else that failed — network, 5xx, timeout. Renders `ErrorState`
  /// with a working retry, unlike [notLinked].
  error,
}

@immutable
class IdentityResult {
  const IdentityResult(
    this.kind, {
    this.message,
    this.roles = const [],
    this.userId,
    this.tenantId,
    this.staffId,
    this.staffName,
    this.permissions = const [],
    this.grants = const [],
    this.permissionsKnown = false,
    this.temporary = false,
    this.serverBusy = false,
  });

  final IdentityResultKind kind;

  /// For [IdentityResultKind.error]: the server was unreachable or temporarily
  /// unavailable (no response, 502/503/504). The stored session is NOT known to
  /// be dead, so it must not be treated as signed out (F12).
  final bool temporary;

  /// A [temporary] failure caused by rate limiting (HTTP 429): the server is
  /// reachable but busy. Only changes the wording shown; handling is identical.
  final bool serverBusy;

  /// Backend message, verbatim, when [kind] is [IdentityResultKind.error].
  final String? message;

  /// Role claims for the signed-in user, e.g. `['admin']`, `['teacher']`.
  /// Populated by T6/T7's network resolver; empty for the static stand-in.
  /// The shell uses this to choose which ordered destination list to render
  /// (D-31) — it is the reason this type carries more than a [kind].
  final List<String> roles;

  /// `sub` claim — the user account id.
  final String? userId;

  /// `tid` claim — the institution/tenant id. Confirmed present in the real
  /// JWT (2026-08-03). Carried for display and diagnostics only: the
  /// backend derives the tenant from the token itself and it is NEVER sent
  /// back as a header or parameter.
  final String? tenantId;

  /// `id` from `GET /api/staff/me`, captured when the person-record check
  /// (D-17) resolves it for a teacher/staff role. Null for every other
  /// role, and null for a teacher/staff role that turned out `notLinked` —
  /// there is no staff row to have an id.
  ///
  /// This is what `TodayScreen` needs to ask `/api/timetable/teacher/
  /// {staffId}/today` for the signed-in teacher's own schedule; before this
  /// field existed the resolver already fetched `/api/staff/me` for the
  /// orphan check and simply discarded the id it returned.
  final String? staffId;

  /// "First Last" from the same `/api/staff/me` response. Used by the diary
  /// to recognise the teacher's own entries, since diary entries carry only
  /// an author NAME.
  final String? staffName;

  /// Current permissions from `/auth/me` (database-authoritative, ADR-011).
  /// Navigation uses them only to hide what the server would refuse.
  final List<String> permissions;

  /// Each permission set stays bound to its own grant and campus; never
  /// cross-combine one grant's permissions with another grant's campus.
  final List<GrantScope> grants;

  /// False for stand-ins that never asked the server (tests, gallery).
  final bool permissionsKnown;

  bool can(String permission) => permissions.contains(permission);

  /// Campuses where [permission] is granted by the SAME grant. Null means
  /// institution-wide (any campus).
  Set<String>? campusesFor(String permission) {
    final campuses = <String>{};
    for (final g in grants.where((g) => g.permissions.contains(permission))) {
      if (g.campusId == null) return null;
      campuses.add(g.campusId!);
    }
    return campuses;
  }
}

class GrantScope {
  const GrantScope({required this.role, required this.campusId, required this.permissions});

  factory GrantScope.fromJson(Map json) => GrantScope(
    role: json['role'] as String? ?? '',
    campusId: json['campusId'] as String?,
    permissions: (json['permissions'] as List?)?.cast<String>() ?? const [],
  );

  final String role;
  final String? campusId;
  final List<String> permissions;
}

/// SEAM FOR T6. T6 owns the network layer and will supply the real `/me` (or
/// `/staff/me` / `/students/me`) call. T5 only defines the contract the shell
/// gates on and provides a stand-in for its own tests and the gallery.
abstract interface class IdentityResolver {
  Future<IdentityResult> resolveIdentity();
}

/// The T5 stand-in. Always reports linked, so the shell renders immediately
/// in the gallery and in tests that are not specifically exercising the gate.
class StaticIdentityResolver implements IdentityResolver {
  const StaticIdentityResolver([
    this._result = const IdentityResult(IdentityResultKind.linked),
  ]);

  final IdentityResult _result;

  @override
  Future<IdentityResult> resolveIdentity() async => _result;
}
