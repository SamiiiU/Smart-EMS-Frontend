import 'package:smartems/core/network/paged_get.dart';
import 'package:dio/dio.dart';

import '../../../core/network/api_config.dart';
import '../../../core/network/api_error_mapper.dart';
import '../domain/admin_models.dart';

/// CSV upload returns a durable pending job (202); poll before showing final counts.
class ImportRepository {
  const ImportRepository(this.dio);

  final Dio dio;

  /// The header row the backend expects — **snake_case**, not camelCase.
  ///
  /// This is not cosmetic: a camelCase file parses with every row rejected
  /// as `"first_name missing"`. Shown in the UI so the first attempt can
  /// succeed rather than teaching the admin by failure.
  static const List<String> studentHeaders = [
    'first_name',
    'last_name',
    'admission_number',
  ];

  Future<T> _mapped<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (err) {
      throw mapDioError(err);
    }
  }

  /// Uploads CSV content.
  ///
  /// Sent as `multipart/form-data` with the field name `file`, which is what
  /// the endpoint requires — posting JSON returns a 500, not a 400, so a
  /// wrong content type fails confusingly rather than cleanly.
  Future<ImportResult> importStudents(String csv) => _mapped(() async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromString(csv, filename: 'students.csv'),
    });
    final res = await dio.post<Map<String, dynamic>>(
      ApiConfig.importStudentsPath,
      data: form,
    );
    return ImportResult.fromJson(res.data ?? const {});
  });

  Future<Map<String, dynamic>> loadStatus(String jobId, CancelToken token) =>
      _mapped(() async {
        final response = await dio.get<Map<String, dynamic>>(
          '/api/import/$jobId',
          cancelToken: token,
        );
        return response.data!;
      });

  /// Per-row rejections, so the admin can fix and re-import. A count alone
  /// is not actionable — which row, and why, is the whole point.
  Future<List<ImportRowError>> loadErrors(String jobId) => _mapped(() async {
    final rows = await dio.getAllPages(ApiConfig.importErrorsPath(jobId));
    return rows.map(ImportRowError.fromJson).toList();
  });
}
