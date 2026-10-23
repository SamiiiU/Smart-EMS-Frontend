import 'package:dio/dio.dart';

import '../../../core/network/api_error_mapper.dart';
import '../../../core/widgets/states/screen_state.dart';

/// A current Institution Admin (institution-wide `admin` grant).
class InstitutionAdmin {
  const InstitutionAdmin({required this.userId, required this.username, this.since});

  factory InstitutionAdmin.fromJson(Map<String, dynamic> json) => InstitutionAdmin(
    userId: json['userId'] as String,
    username: json['username'] as String? ?? '',
    since: json['since']?.toString(),
  );

  final String userId;
  final String username;
  final String? since;
}

/// A staff account that could be appointed (it must already have a login).
class AdminCandidate {
  const AdminCandidate({required this.userId, required this.name});

  final String userId;
  final String name;
}

/// ADR-007 / Doc 21: only the institution Owner appoints or removes Institution
/// Admins (`/api/institution/admins`). Every change first sends a fresh,
/// single-use, target-specific approval (`INSTITUTION_ADMIN_APPOINT` or
/// `INSTITUTION_ADMIN_REMOVE`) with an authenticator code. The server decides;
/// this client never assumes a role or a result.
class InstitutionAdminRepository {
  const InstitutionAdminRepository(this.dio);

  final Dio dio;
  static const _path = '/api/institution/admins';

  Future<({List<InstitutionAdmin>? admins, LoadFailure? failure})> list() async {
    try {
      final res = await dio.get<List<dynamic>>(_path);
      return (
        admins: [
          for (final a in (res.data ?? const []).cast<Map<String, dynamic>>()) InstitutionAdmin.fromJson(a),
        ],
        failure: null,
      );
    } on DioException catch (err) {
      return (admins: null, failure: mapDioError(err));
    }
  }

  /// Staff with a login; the server re-checks every eligibility rule.
  Future<({List<AdminCandidate>? candidates, LoadFailure? failure})> candidates() async {
    try {
      final res = await dio.get<Map<String, dynamic>>('/api/staff', queryParameters: {'size': 100});
      return (
        candidates: [
          for (final s in (res.data?['content'] as List? ?? const []).cast<Map<String, dynamic>>())
            if (s['userId'] != null)
              AdminCandidate(
                userId: s['userId'] as String,
                name: '${s['firstName'] ?? ''} ${s['lastName'] ?? ''}'.trim(),
              ),
        ],
        failure: null,
      );
    } on DioException catch (err) {
      return (candidates: null, failure: mapDioError(err));
    }
  }

  Future<LoadFailure?> _approve(String action, String targetId, String code) async {
    try {
      await dio.post<dynamic>('/auth/mfa/approvals',
          data: {'action': action, 'targetId': targetId, 'code': code.trim()});
      return null;
    } on DioException catch (err) {
      return mapDioError(err);
    }
  }

  /// Approval for this exact target, then the appointment.
  Future<LoadFailure?> appoint({required String userId, required String code}) async {
    final denied = await _approve('INSTITUTION_ADMIN_APPOINT', userId, code);
    if (denied != null) return denied;
    try {
      await dio.post<dynamic>(_path, data: {'userId': userId});
      return null;
    } on DioException catch (err) {
      return mapDioError(err);
    }
  }

  /// Approval for this exact target, then removal (the server also signs them out).
  Future<LoadFailure?> remove({required String userId, required String code}) async {
    final denied = await _approve('INSTITUTION_ADMIN_REMOVE', userId, code);
    if (denied != null) return denied;
    try {
      await dio.delete<dynamic>('$_path/$userId');
      return null;
    } on DioException catch (err) {
      return mapDioError(err);
    }
  }
}
