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
  final message = withoutInternalIds(body is Map ? body['message'] as String? : null);
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

  if (status == 403) {
    return LoadFailure(message: message, kind: LoadFailureKind.forbidden);
  }

  return LoadFailure(
    message: message ?? _fallbackMessage(err, status),
    kind: LoadFailureKind.transient,
    unreachable: response == null &&
        (_unreachableTypes.contains(err.type) || _isTransportFailure(err)),
  );
}

/// DEF-26: on Android a refused/reset connection arrives as
/// [DioExceptionType.unknown] wrapping a socket/TLS error, with no response.
/// It must read as "could not reach the server", never fall through to a
/// screen's own fallback such as "That code was not accepted".
bool _isTransportFailure(DioException err) =>
    err.response == null &&
    err.type == DioExceptionType.unknown &&
    err.error != null;

/// Server messages are shown verbatim (they name the real problem), but some
/// end with an internal record id, e.g. "Campus not found: 23d08841-…" (hard-QA
/// BUG-QA-13, seen on the Pixel after a mid-session grant revocation). An id
/// means nothing to staff and exposes internals, so UUIDs are removed and the
/// rest of the message is kept.
String? withoutInternalIds(String? message) {
  if (message == null) return null;
  final cleaned = message
      .replaceAll(RegExp(r':?\s*\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b'), '')
      .trim();
  return cleaned.isEmpty ? null : cleaned;
}

/// No response at all, for a network reason — the offline state, not an
/// error the server reported.
const _unreachableTypes = {
  DioExceptionType.connectionError,
  DioExceptionType.connectionTimeout,
  DioExceptionType.sendTimeout,
  DioExceptionType.receiveTimeout,
};

String? _fallbackMessage(DioException err, int? status) {
  // Gateway/outage answers (often an HTML body from the proxy) are temporary:
  // never present them as a credentials problem.
  if (status == 502 || status == 503 || status == 504) {
    return 'The service is temporarily unavailable. Please try again shortly.';
  }
  switch (err.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return 'The request timed out.';
    case DioExceptionType.connectionError:
      return 'Could not reach the server.';
    default:
      return _isTransportFailure(err) ? 'Could not reach the server.' : null;
  }
}
