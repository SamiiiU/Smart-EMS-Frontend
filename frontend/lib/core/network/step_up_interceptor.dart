import 'dart:convert';

import 'package:dio/dio.dart';

/// Asks the user for a fresh authenticator code. Returns true only after the
/// server accepted it (`POST /auth/mfa/step-up`); false when cancelled.
typedef StepUpPrompt = Future<bool> Function(String reasonCode);

/// ADR-010 finance step-up. Approvals, rejections, discounts and fee-setting
/// changes answer 403 with `details.code == STEP_UP_REQUIRED` until this
/// session confirmed a TOTP within five minutes. This interceptor prompts once
/// and replays the original request exactly once.
///
/// Replay is safe: the server rejects before any mutation, so the first
/// attempt changed nothing. The backend still decides; nothing here grants
/// access, and a cancelled prompt surfaces the original 403 unchanged.
class StepUpInterceptor extends Interceptor {
  StepUpInterceptor({this.retryDio, this.prompt});

  /// The same client (so auth headers are attached again on replay); set once
  /// the client exists, since the interceptor is installed on it.
  Dio? retryDio;

  /// Late-bound by the app once a navigator exists; null means no UI yet.
  StepUpPrompt? prompt;

  /// A protected request found this session restricted (403 MFA_REQUIRED),
  /// e.g. after a factor reset on another device. Sends the user back to
  /// the two-factor screen instead of treating it as a sign-out.
  void Function()? onMfaRequired;

  static const _replayed = 'stepUpReplayed';

  static String? reasonOf(DioException err) {
    var body = err.response?.data;
    // Repositories that read raw text (money-safe decoding: Finance, Academy)
    // receive the error body as a String; decode it so the prompt still appears.
    if (err.response?.statusCode == 403 && body is String && body.isNotEmpty) {
      try {
        body = jsonDecode(body);
      } on FormatException {
        return null;
      }
    }
    if (err.response?.statusCode != 403 || body is! Map) return null;
    final details = body['details'];
    return details is Map ? details['code'] as String? : null;
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final reason = reasonOf(err);
    if (reason == 'MFA_REQUIRED') onMfaRequired?.call();
    final ask = prompt;
    if ((reason != 'STEP_UP_REQUIRED' && reason != 'MFA_ENROLLMENT_REQUIRED') ||
        ask == null ||
        retryDio == null ||
        err.requestOptions.extra[_replayed] == true) {
      return handler.next(err);
    }
    final confirmed = await ask(reason!);
    if (!confirmed || reason != 'STEP_UP_REQUIRED') return handler.next(err);
    try {
      final options = err.requestOptions..extra[_replayed] = true;
      return handler.resolve(await retryDio!.fetch<dynamic>(options));
    } on DioException catch (retryError) {
      return handler.next(retryError);
    }
  }
}
