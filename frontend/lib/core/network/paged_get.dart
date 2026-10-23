import 'package:dio/dio.dart';

/// Reads every page of a Spring `Page<T>` endpoint.
///
/// The backend caps `size` at 100 (`Pagination.MAX_SIZE`) and clamps larger
/// values silently, so a single `?size=500` request returns at most 100 rows
/// with no error. Anything that needs "all rows" must walk the pages.
extension PagedGet on Dio {
  static const int pageSize = 100;

  /// Hard stop so a misbehaving server can never loop us forever.
  static const int _maxPages = 200;

  /// Requests currently on the wire, keyed by path + query. The shell's
  /// IndexedStack builds every tab at once (D-30), so several screens ask
  /// for the same list in the same instant; they now share one request.
  /// Only IN-FLIGHT calls are shared — nothing is cached once it settles,
  /// so a reload after a create always hits the server.
  static final Map<String, Future<List<Map<String, dynamic>>>> _inFlight = {};

  Future<List<Map<String, dynamic>>> getAllPages(
    String path, {
    Map<String, dynamic> queryParameters = const {},
  }) {
    final key =
        '${identityHashCode(this)} $path ${Uri(queryParameters: {for (final e in queryParameters.entries)
          if (e.value != null) e.key: '${e.value}'}).query}';
    final existing = _inFlight[key];
    if (existing != null) return existing;
    // Block body on purpose: `=> _inFlight.remove(key)` would return the
    // removed Future, and whenComplete waits on a returned Future — i.e. this
    // future would wait on itself and never complete.
    final future = _fetchAll(path, queryParameters).whenComplete(() {
      _inFlight.remove(key);
    });
    return _inFlight[key] = future;
  }

  Future<List<Map<String, dynamic>>> _fetchAll(
    String path,
    Map<String, dynamic> queryParameters,
  ) async {
    final rows = <Map<String, dynamic>>[];
    for (var page = 0; page < _maxPages; page++) {
      final res = await get<Map<String, dynamic>>(
        path,
        queryParameters: {...queryParameters, 'page': page, 'size': pageSize},
      );
      final body = res.data;
      final content = (body?['content'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      rows.addAll(content);
      // Two envelopes exist: Spring's Page (has `last`) and a hand-built
      // {content, page, size, totalElements} with no `last`. Decide from
      // totalElements when present, else a short page means the end.
      final total = (body?['totalElements'] as num?)?.toInt();
      final done =
          body?['last'] == true ||
          (total != null && rows.length >= total) ||
          content.length < pageSize;
      if (content.isEmpty || done) break;
    }
    return rows;
  }
}
