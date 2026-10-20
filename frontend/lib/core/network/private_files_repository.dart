import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'api_error_mapper.dart';

/// Uses the application's authenticated Dio. Never follows a provider URL.
class PrivateFilesRepository {
  const PrivateFilesRepository(this.dio);
  final Dio dio;
  String _id(String value) {
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value)) {
      throw ArgumentError('Invalid file/resource ID');
    }
    return value;
  }

  Future<T> _mapped<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (error) {
      throw mapDioError(error);
    }
  }

  /// Keep requestKey stable across retries of the same payload; do not auto-retry ambiguous failures.
  Future<Map<String, dynamic>> upload({
    required Uint8List bytes,
    required String filename,
    required String scope,
    required String resourceId,
    required String requestKey,
    String? studentId,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) => _mapped(() async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
      'scope': scope,
      'resourceId': _id(resourceId),
      if (studentId != null) 'studentId': _id(studentId),
    });
    final result = await dio.post<Map<String, dynamic>>(
      '/api/files',
      data: form,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      options: Options(
        headers: {'Idempotency-Key': _id(requestKey)},
        receiveTimeout: const Duration(seconds: 45),
        sendTimeout: const Duration(seconds: 45),
      ),
    );
    return result.data!;
  });
  Future<Uint8List> download(String fileId, {CancelToken? cancelToken}) =>
      _mapped(() async {
        final result = await dio.get<List<int>>(
          '/api/files/${_id(fileId)}/content',
          cancelToken: cancelToken,
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(seconds: 30),
          ),
        );
        return Uint8List.fromList(result.data!);
      });
  Future<Map<String, dynamic>> metadata(String fileId) => _mapped(
    () async => (await dio.get<Map<String, dynamic>>(
      '/api/files/${_id(fileId)}',
    )).data!,
  );
  Future<List<Map<String, dynamic>>> list({
    required String scope,
    required String resourceId,
    String? studentId,
  }) => _mapped(() async {
    final response = await dio.get<List<dynamic>>(
      '/api/files',
      queryParameters: {
        'scope': scope,
        'resourceId': _id(resourceId),
        if (studentId != null) 'studentId': _id(studentId),
      },
    );
    return response.data!
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList();
  });
  Future<void> link(String fileId) => _mapped(() async {
    await dio.put<dynamic>('/api/files/${_id(fileId)}/link');
  });
  Future<void> delete(String fileId) => _mapped(() async {
    await dio.delete<dynamic>('/api/files/${_id(fileId)}');
  });
}
