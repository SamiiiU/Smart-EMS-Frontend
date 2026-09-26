import 'package:dio/dio.dart';

import '../../../core/network/api_error_mapper.dart';
import '../domain/notification_models.dart';

/// Notifications (T16 Batch D).
///
/// ⚠️ This module is **camelCase** while complaints and staff attendance
/// next to it are snake_case. Three conventions now coexist in one API
/// (open item 36).
class NotificationsRepository {
  const NotificationsRepository(this.dio);

  final Dio dio;

  Future<T> _mapped<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (err) {
      throw mapDioError(err);
    }
  }

  Future<List<AppNotification>> load({bool unreadOnly = false}) =>
      _mapped(() async {
        final res = await dio.get<Map<String, dynamic>>(
          '/api/notifications',
          queryParameters: {'size': 100, if (unreadOnly) 'unreadOnly': true},
        );
        return (res.data?['content'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(AppNotification.fromJson)
            .toList();
      });

  Future<int> unreadCount() => _mapped(() async {
        final res = await dio.get<Map<String, dynamic>>(
          '/api/notifications/unread-count',
        );
        return res.data?['unreadCount'] as int? ?? 0;
      });

  /// Read state persists server-side — `readAt` is stamped and survives a
  /// reload, so nothing is tracked locally.
  Future<void> markRead(String id) => _mapped(() async {
        await dio.put<dynamic>('/api/notifications/$id/read');
      });

  /// Returns how many were actually marked, which is what the screen
  /// reports back rather than asserting a number of its own.
  Future<int> markAllRead() => _mapped(() async {
        final res = await dio.put<Map<String, dynamic>>(
          '/api/notifications/read-all',
        );
        return res.data?['marked'] as int? ?? 0;
      });
}
