import 'package:dio/dio.dart';

import '../../../core/network/api_config.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/widgets/states/screen_state.dart';

/// Server-reported two-factor state of THIS device session (ADR-010).
///
/// The backend is authoritative: while [pending] is true every ordinary API
/// returns 403 `MFA_REQUIRED`, whatever this client shows.
class MfaStatus {
  const MfaStatus({
    required this.required,
    required this.enrolled,
    required this.sessionVerified,
    required this.stepUpActive,
    required this.recoveryCodesRemaining,
  });

  factory MfaStatus.fromJson(Map<String, dynamic> json) => MfaStatus(
    required: json['required'] as bool? ?? false,
    enrolled: json['enrolled'] as bool? ?? false,
    sessionVerified: json['sessionVerified'] as bool? ?? false,
    stepUpActive: json['stepUpActive'] as bool? ?? false,
    recoveryCodesRemaining: json['recoveryCodesRemaining'] as int? ?? 0,
  );

  final bool required;
  final bool enrolled;
  final bool sessionVerified;
  final bool stepUpActive;
  final int recoveryCodesRemaining;

  bool get pending => required && (!enrolled || !sessionVerified);
}

class MfaEnrollment {
  const MfaEnrollment({required this.secret, required this.otpauthUrl});
  final String secret;
  final String otpauthUrl;
}

/// `/auth/mfa/*`. Every method returns a [LoadFailure] instead of throwing so
/// screens can show the server's own message ("Invalid verification code").
class MfaRepository {
  const MfaRepository(this.dio);

  final Dio dio;

  Future<({MfaStatus? status, LoadFailure? failure})> status() async {
    try {
      final res = await dio.get<Map<String, dynamic>>(ApiConfig.mfaPath);
      return (status: MfaStatus.fromJson(res.data ?? const {}), failure: null);
    } on DioException catch (err) {
      return (status: null, failure: mapDioError(err));
    }
  }

  Future<({MfaEnrollment? enrollment, LoadFailure? failure})>
  beginEnrollment() async {
    try {
      final res = await dio.post<Map<String, dynamic>>(
        ApiConfig.mfaEnrollmentPath,
      );
      final secret = res.data?['secret'] as String?;
      final url = res.data?['otpauthUrl'] as String?;
      if (secret == null || url == null) {
        return (
          enrollment: null,
          failure: const LoadFailure(
            message: 'The server did not return a setup key.',
          ),
        );
      }
      return (
        enrollment: MfaEnrollment(secret: secret, otpauthUrl: url),
        failure: null,
      );
    } on DioException catch (err) {
      return (enrollment: null, failure: mapDioError(err));
    }
  }

  /// Returns the one-time recovery codes. They are never retrievable again.
  Future<({List<String>? recoveryCodes, LoadFailure? failure})>
  confirmEnrollment(String code) async {
    try {
      final res = await dio.post<Map<String, dynamic>>(
        ApiConfig.mfaEnrollmentConfirmPath,
        data: {'code': code.trim()},
      );
      final codes = (res.data?['recoveryCodes'] as List?)?.cast<String>();
      return (recoveryCodes: codes ?? const <String>[], failure: null);
    } on DioException catch (err) {
      return (recoveryCodes: null, failure: mapDioError(err));
    }
  }

  /// Completes sign-in on this device with an authenticator code or a
  /// single-use recovery code.
  Future<LoadFailure?> verify({String? code, String? recoveryCode}) async {
    try {
      await dio.post<dynamic>(
        ApiConfig.mfaVerifyPath,
        data: {
          if (code != null && code.trim().isNotEmpty) 'code': code.trim(),
          if (recoveryCode != null && recoveryCode.trim().isNotEmpty)
            'recoveryCode': recoveryCode.trim(),
        },
      );
      return null;
    } on DioException catch (err) {
      return mapDioError(err);
    }
  }

  /// Five-minute, session-bound confirmation for sensitive finance actions.
  Future<LoadFailure?> stepUp(String code) async {
    try {
      await dio.post<dynamic>(
        ApiConfig.mfaStepUpPath,
        data: {'code': code.trim()},
      );
      return null;
    } on DioException catch (err) {
      return mapDioError(err);
    }
  }
}
