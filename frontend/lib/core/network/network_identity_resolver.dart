import 'package:dio/dio.dart';

import '../shell/identity_resolver.dart';
import 'api_config.dart';
import 'api_error_mapper.dart';

/// Real implementation of T5's [IdentityResolver] seam.
///
/// Resolves in TWO steps, because no single endpoint answers both questions
/// (verified live 2026-08-03):
///
/// 1. `GET /auth/me` — "is this token valid, and who is it?" Returns
///    `{roles, userId, tenantId}` and is 200 for any valid token. A failure
///    here is an ordinary error (or an expired session).
/// 2. `GET /api/staff/me` or `/api/students/me` — "does a person record
///    exist?" This is the only thing that can 404 into the D-17 orphan
///    case. Skipped entirely for roles that legitimately have no person
///    record (admin, owner, parent) — see [ApiConfig.personRecordPathFor].
///
/// Step 2 exists because D-17 requires the orphan user to be told at the
/// gate, before any tab renders — not after they tap into a screen and hit
/// a confusing empty list.
class NetworkIdentityResolver implements IdentityResolver {
  NetworkIdentityResolver(this._dio);

  final Dio _dio;

  @override
  Future<IdentityResult> resolveIdentity() async {
    final Response<dynamic> accountResponse;
    try {
      accountResponse = await _dio.get<dynamic>(ApiConfig.mePath);
    } on DioException catch (err) {
      return IdentityResult(
        IdentityResultKind.error,
        message: mapDioError(err).message,
      );
    }

    final body = accountResponse.data;
    final account = body is Map ? body : const {};
    final roles = (account['roles'] as List?)?.cast<String>() ?? const [];
    final userId = account['userId'] as String?;
    final tenantId = account['tenantId'] as String?;

    final personPath = ApiConfig.personRecordPathFor(roles);
    if (personPath != null) {
      try {
        final personResponse = await _dio.get<dynamic>(personPath);
        // Only /api/staff/me carries an id TodayScreen needs (its own
        // teaching timetable). /api/students/me and /api/guardians/me are
        // fetched for the SAME orphan check but have no equivalent use yet,
        // so nothing is extracted from them here.
        final staff = personPath == ApiConfig.staffMePath &&
                personResponse.data is Map
            ? personResponse.data as Map
            : null;
        final staffId = staff?['id'] as String?;
        // The diary (T11) carries only `authorName`, no author id, so the
        // teacher's own display name is what tells "my entry" from a shared
        // one. Composed the way the backend composes authorName
        // ("Ayesha Khan" = firstName + lastName, verified live).
        final staffName = staff == null
            ? null
            : '${staff['firstName'] ?? ''} ${staff['lastName'] ?? ''}'.trim();
        return IdentityResult(
          IdentityResultKind.linked,
          roles: roles,
          userId: userId,
          tenantId: tenantId,
          staffId: staffId,
          staffName: (staffName?.isEmpty ?? true) ? null : staffName,
        );
      } on DioException catch (err) {
        final failure = mapDioError(err);
        if (failure.isNotLinked) {
          // D-17 orphan case: the login is real, the person record is not.
          // No retry — the user cannot fix this themselves.
          return IdentityResult(
            IdentityResultKind.notLinked,
            message: failure.message,
            roles: roles,
            userId: userId,
            tenantId: tenantId,
          );
        }
        return IdentityResult(
          IdentityResultKind.error,
          message: failure.message,
          roles: roles,
          userId: userId,
          tenantId: tenantId,
        );
      }
    }

    return IdentityResult(
      IdentityResultKind.linked,
      roles: roles,
      userId: userId,
      tenantId: tenantId,
    );
  }
}
