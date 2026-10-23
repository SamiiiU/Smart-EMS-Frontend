import 'package:dio/dio.dart';

import '../../../core/network/api_error_mapper.dart';
import '../../../core/widgets/states/screen_state.dart';

/// Former owner's access after transfer (ADR-007 Option C). NONE is the default.
enum FormerOwnerAccess { none, institutionAdmin }

extension FormerOwnerAccessWire on FormerOwnerAccess {
  String get wire =>
      this == FormerOwnerAccess.none ? 'NONE' : 'INSTITUTION_ADMIN';
}

class PendingTransfer {
  const PendingTransfer({
    required this.id,
    required this.initiatedBy,
    required this.targetUserId,
  });
  final String id;
  final String initiatedBy;
  final String targetUserId;
}

class TransferCandidate {
  const TransferCandidate({required this.userId, required this.name});
  final String userId;
  final String name;
}

/// Two-party ownership transfer. Every step needs a fresh authenticator code,
/// sent first as a single-use `OWNERSHIP_TRANSFER` approval; the server decides.
class OwnershipRepository {
  const OwnershipRepository(this.dio);

  final Dio dio;
  static const _path = '/api/institution/ownership-transfer';

  /// The signed-in account id (to tell initiator from incoming owner).
  Future<String?> myUserId() async {
    try {
      return (await dio.get<Map<String, dynamic>>('/auth/me')).data?['userId']
          as String?;
    } on DioException {
      return null;
    }
  }

  Future<({PendingTransfer? transfer, LoadFailure? failure})> pending() async {
    try {
      final res = await dio.get<Map<String, dynamic>>(_path);
      final d = res.data ?? const {};
      if (d['id'] == null) return (transfer: null, failure: null);
      return (
        transfer: PendingTransfer(
          id: d['id'] as String,
          initiatedBy: d['initiatedBy'] as String,
          targetUserId: d['targetUserId'] as String,
        ),
        failure: null,
      );
    } on DioException catch (err) {
      return (transfer: null, failure: mapDioError(err));
    }
  }

  /// Staff accounts that can become owner (must already have a login).
  Future<({List<TransferCandidate>? candidates, LoadFailure? failure})>
  candidates() async {
    try {
      final res = await dio.get<Map<String, dynamic>>(
        '/api/staff',
        queryParameters: {'size': 100},
      );
      final list = [
        for (final s
            in (res.data?['content'] as List? ?? const [])
                .cast<Map<String, dynamic>>())
          if (s['userId'] != null)
            TransferCandidate(
              userId: s['userId'] as String,
              name: '${s['firstName'] ?? ''} ${s['lastName'] ?? ''}'.trim(),
            ),
      ];
      return (candidates: list, failure: null);
    } on DioException catch (err) {
      return (candidates: null, failure: mapDioError(err));
    }
  }

  Future<LoadFailure?> _approve(String targetId, String code) async {
    try {
      await dio.post<dynamic>(
        '/auth/mfa/approvals',
        data: {
          'action': 'OWNERSHIP_TRANSFER',
          'targetId': targetId,
          'code': code.trim(),
        },
      );
      return null;
    } on DioException catch (err) {
      return mapDioError(err);
    }
  }

  Future<LoadFailure?> initiate({
    required String targetUserId,
    required String code,
  }) async {
    final denied = await _approve(targetUserId, code);
    if (denied != null) return denied;
    try {
      await dio.post<dynamic>(_path, data: {'targetUserId': targetUserId});
      return null;
    } on DioException catch (err) {
      return mapDioError(err);
    }
  }

  Future<LoadFailure?> accept({
    required String transferId,
    required FormerOwnerAccess access,
    required String code,
  }) async {
    final denied = await _approve(transferId, code);
    if (denied != null) return denied;
    try {
      await dio.post<dynamic>(
        '$_path/$transferId/accept',
        data: {'formerOwnerAccess': access.wire},
      );
      return null;
    } on DioException catch (err) {
      return mapDioError(err);
    }
  }

  Future<LoadFailure?> cancel(String transferId) async {
    try {
      await dio.delete<dynamic>('$_path/$transferId');
      return null;
    } on DioException catch (err) {
      return mapDioError(err);
    }
  }
}
