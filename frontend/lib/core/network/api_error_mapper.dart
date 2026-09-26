import 'package:dio/dio.dart';

import '../widgets/states/screen_state.dart';
import 'api_config.dart';

/// Maps a [DioException] to [LoadFailure], so every T7+ screen gets an
/// already-classified failure rather than a raw HTTP exception.
///
/// The backend's error body shape below is VERIFIED — observed directly
/// against the live Railway instance (see `BACKEND_CONTRACT.md`):
/// ```json
/// {"status":401,"error":"Unauthorized","message":"Access token missing or
/// invalid","path":"/","timestamp":"2026-08-03T07:05:09.85Z"}
/// ```
/// `message` is taken verbatim, per [LoadFailure]'s own contract — it names
/// the actual problem, and replacing it with a generic string discards that.
LoadFailure mapDioError(DioException err) {
  final response = err.response;
  final status = response?.statusCode;
  final body = response?.data;
  final message = body is Map ? body['message'] as String? : null;
  final requestedPath = err.requestOptions.uri.path;

  // A 404 from a PERSON-RECORD endpoint is the D-17 orphan case (row 9 of
  // the precedence rule), not an ordinary error.
  //
  // Keyed off `/api/staff/me` and `/api/students/me`, NOT `/auth/me`.
  // Verified live 2026-08-03: `/auth/me` returns 200 for any valid token,
  // so it cannot express "no person record"; both person endpoints return
  // 404 "… record linked to this login not found" when the row is missing.
  // T6 had this keyed to its guessed `/me` path, which was wrong twice
  // over — wrong path, and wrong semantics.
  //
  // Matched on the REQUESTED path rather than the body's `path` field so a
  // response without a body still classifies correctly.
  if (status == 404 && ApiConfig.personRecordPaths.contains(requestedPath)) {
    return LoadFailure(message: message, kind: LoadFailureKind.notLinked);
  }

  return LoadFailure(
    message: message ?? _fallbackMessage(err),
    kind: LoadFailureKind.transient,
    unreachable: response == null && _unreachableTypes.contains(err.type),
  );
}

/// No response at all, for a network reason — the offline state, not an
/// error the server reported.
const _unreachableTypes = {
  DioExceptionType.connectionError,
  DioExceptionType.connectionTimeout,
  DioExceptionType.sendTimeout,
  DioExceptionType.receiveTimeout,
};

String? _fallbackMessage(DioException err) {
  switch (err.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return 'The request timed out.';
    case DioExceptionType.connectionError:
      return 'Could not reach the server.';
    default:
      return null;
  }
}
