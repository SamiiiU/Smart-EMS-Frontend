import 'package:dio/dio.dart';

import '../../../core/network/api_error_mapper.dart';
import '../domain/complaint_models.dart';

/// Every complaints call the app makes (T16 Batch D).
///
/// No raw-text decoding door here, unlike finance and academics: complaints
/// carry no decimal money or marks, so the ordinary JSON path is safe. The
/// one numeric field, `satisfaction_rating`, is an integer.
class ComplaintsRepository {
  const ComplaintsRepository(this.dio);

  final Dio dio;

  Future<T> _mapped<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (err) {
      throw mapDioError(err);
    }
  }

  static List<Map<String, dynamic>> _content(Map<String, dynamic>? body) =>
      (body?['content'] as List? ?? const []).cast<Map<String, dynamic>>();

  // --- Campus ----------------------------------------------------------------

  /// The campus a complaint will be filed against, or null if this account
  /// cannot discover one.
  ///
  /// 🔴 `POST /api/complaints` REQUIRES `campusId` and the server will not
  /// default it (`400 {"campusId":"must not be null"}`), but **non-admin
  /// roles get 403 on `/api/campuses`**. So each role has to find it on the
  /// one endpoint it is allowed to read:
  ///
  /// | Role | Source | Works? |
  /// |---|---|---|
  /// | teacher | `/api/staff/me` | ✅ carries `campusId` |
  /// | student | `/api/students/me` | ✅ carries `campusId` |
  /// | admin | `/api/campuses` | ✅ |
  /// | **parent** | — | 🔴 **nothing carries it** |
  ///
  /// `/api/guardians/me` has no `campusId` and neither does
  /// `/api/institution/me`, so **a parent cannot raise a complaint at all**.
  /// Null is returned rather than guessed, and the screen explains it
  /// instead of offering a form that cannot submit (open item 39).
  Future<String?> resolveCampusId() async {
    for (final path in const ['/api/staff/me', '/api/students/me']) {
      try {
        final res = await dio.get<Map<String, dynamic>>(path);
        final campusId = res.data?['campusId'] as String?;
        if (campusId != null && campusId.isNotEmpty) return campusId;
      } on DioException {
        // 403 or 404 for this role — try the next.
        continue;
      }
    }
    return null;
  }

  // --- Raising ---------------------------------------------------------------

  /// Raises a complaint.
  ///
  /// `isAnonymous` is honoured properly: the backend stores no
  /// `raised_by_user_id` at all, so an anonymous complaint cannot be traced
  /// back even by an administrator. That is also why it cannot be replied
  /// to personally — the screen says so BEFORE the choice is made.
  Future<Complaint> raise({
    required String campusId,
    required ComplaintCategory category,
    required String subject,
    required String description,
    ComplaintPriority priority = ComplaintPriority.medium,
    bool isAnonymous = false,
    String? aboutStudentId,
  }) =>
      _mapped(() async {
        final res = await dio.post<Map<String, dynamic>>(
          '/api/complaints',
          data: {
            'campusId': campusId,
            'category': category.wire,
            'subject': subject,
            'description': description,
            'priority': priority.wire,
            'isAnonymous': isAnonymous,
            'aboutStudentId': ?aboutStudentId,
          },
        );
        return Complaint.fromJson(res.data!);
      });

  // --- Reading ---------------------------------------------------------------

  /// The caller's OWN complaints. Available to every role.
  Future<List<Complaint>> loadMine() => _mapped(() async {
        final res = await dio.get<Map<String, dynamic>>(
          '/api/complaints/my',
          queryParameters: const {'size': 100},
        );
        return _content(res.data).map(Complaint.fromJson).toList();
      });

  /// Every complaint. **Admin only** — other roles get a 403, which is the
  /// correct answer and the reason this is not offered elsewhere.
  ///
  /// Only `status` and `category` are sent. `?status=` with an unknown value
  /// answers 200 rather than filtering, so only real values are ever passed.
  Future<List<Complaint>> loadAll({
    ComplaintStatus? status,
    ComplaintCategory? category,
  }) =>
      _mapped(() async {
        final res = await dio.get<Map<String, dynamic>>(
          '/api/complaints',
          queryParameters: {
            'size': 200,
            'status': ?status?.wire,
            'category': ?category?.wire,
          },
        );
        return _content(res.data).map(Complaint.fromJson).toList();
      });

  Future<Complaint> load(String id) => _mapped(() async {
        final res = await dio.get<Map<String, dynamic>>('/api/complaints/$id');
        return Complaint.fromJson(res.data!);
      });

  /// The thread.
  ///
  /// What comes back depends on WHO asks — the backend filters
  /// `is_internal` comments out for a complainant. The app does not filter
  /// and must not: doing so would hide whether the guarantee still holds.
  Future<List<ComplaintComment>> loadComments(String id) =>
      _mapped(() async {
        final res =
            await dio.get<List<dynamic>>('/api/complaints/$id/comments');
        return (res.data ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ComplaintComment.fromJson)
            .toList();
      });

  // --- Acting ----------------------------------------------------------------

  Future<void> comment({
    required String id,
    required String body,
    bool isInternal = false,
  }) =>
      _mapped(() async {
        await dio.post<dynamic>(
          '/api/complaints/$id/comments',
          data: {'body': body, 'isInternal': isInternal},
        );
      });

  Future<void> assign({required String id, required String staffId}) =>
      _mapped(() async {
        await dio.put<dynamic>(
          '/api/complaints/$id/assign',
          data: {'staffId': staffId},
        );
      });

  /// Moves a complaint on. `open` is not settable — the backend rejects it,
  /// so [ComplaintStatus.settable] is what the screen offers.
  Future<void> setStatus({
    required String id,
    required ComplaintStatus status,
    String? resolutionNote,
  }) =>
      _mapped(() async {
        await dio.put<dynamic>(
          '/api/complaints/$id/status',
          data: {
            'status': status.wire,
            'resolutionNote': ?resolutionNote,
          },
        );
      });
}
