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
  });

  final IdentityResultKind kind;

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
