import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/network/api_error_mapper.dart';
import '../../../core/network/private_files_repository.dart';

/// One subject resource (D-21) as the list endpoint returns it.
class SubjectResource {
  const SubjectResource({
    required this.id,
    required this.title,
    required this.kind,
    required this.status,
    required this.canDelete,
    this.url,
    this.createdAt,
    this.fileId,
    this.filename,
    this.contentType,
    this.sizeBytes,
    this.subjectName,
  });

  factory SubjectResource.fromJson(Map<String, dynamic> json) {
    final path = json['contentPath'] as String?;
    final match = path == null
        ? null
        : RegExp(r'^/api/files/([0-9a-fA-F-]{36})/content$').firstMatch(path);
    return SubjectResource(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      kind: json['kind'] as String? ?? 'file',
      status: json['status'] as String? ?? 'active',
      url: json['url'] as String?,
      createdAt: json['createdAt']?.toString(),
      fileId: match?.group(1),
      filename: json['filename'] as String?,
      contentType: json['contentType'] as String?,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      subjectName: json['subjectName'] as String?,
      canDelete: json['canDelete'] == true,
    );
  }

  final String id;
  final String title;

  /// 'file' or 'link'.
  final String kind;

  /// 'active', or 'pending' for the uploader's own unfinished upload.
  final String status;
  final String? url;
  final String? createdAt;
  final String? fileId;
  final String? filename;
  final String? contentType;
  final int? sizeBytes;

  /// Learner view only: which subject the resource belongs to.
  final String? subjectName;
  final bool canDelete;

  bool get isLink => kind == 'link';
  bool get isPending => status == 'pending';
}

/// D-21 client. Bytes travel through the private-file gateway only
/// (POST /api/files, GET /api/files/{id}/content); no provider URL is ever used.
class SubjectResourcesRepository {
  const SubjectResourcesRepository(this.dio);

  final Dio dio;

  /// The approved file types (D-21). The server validates the actual content.
  static const allowedExtensions = [
    'pdf',
    'png',
    'jpg',
    'jpeg',
    'docx',
    'xlsx',
    'pptx',
    'txt',
  ];

  /// 8 MiB, the platform's per-file limit.
  static const maxBytes = 8 * 1024 * 1024;

  PrivateFilesRepository get files => PrivateFilesRepository(dio);

  Future<T> _mapped<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (error) {
      throw mapDioError(error);
    }
  }

  Future<List<SubjectResource>> list({
    required String subjectId,
    required String classId,
    required String academicYearId,
  }) => _mapped(() async {
    final res = await dio.get<List<dynamic>>(
      '/api/subjects/$subjectId/resources',
      queryParameters: {'classId': classId, 'academicYearId': academicYearId},
    );
    return (res.data ?? const [])
        .whereType<Map>()
        .map((m) => SubjectResource.fromJson(m.cast<String, dynamic>()))
        .toList();
  });

  /// Creates a resource; [requestKey] must stay the same across retries.
  Future<String> create({
    required String subjectId,
    required String classId,
    required String academicYearId,
    required String title,
    required String requestKey,
    String kind = 'file',
    String? url,
  }) => _mapped(() async {
    final res = await dio.post<Map<String, dynamic>>(
      '/api/subjects/$subjectId/resources',
      data: {
        'title': title,
        'academicYearId': academicYearId,
        'classId': classId,
        'kind': kind,
        'url': ?url,
      },
      options: Options(headers: {'Idempotency-Key': requestKey}),
    );
    return res.data!['id'] as String;
  });

  /// Uploads the bytes for a pending file resource and attaches them.
  Future<void> uploadAndAttach({
    required String resourceId,
    required Uint8List bytes,
    required String filename,
    required String uploadKey,
    ProgressCallback? onProgress,
  }) async {
    final file = await files.upload(
      bytes: bytes,
      filename: filename,
      scope: 'SUBJECT_RESOURCE',
      resourceId: resourceId,
      requestKey: uploadKey,
      onSendProgress: onProgress,
    );
    await _mapped(() async {
      await dio.post<dynamic>(
        '/api/subject-resources/$resourceId/file',
        data: {'fileId': file['id']},
      );
    });
  }

  /// Read-only learner view (student self or an approved guardian). The
  /// server derives the class and year from the learner's own current
  /// enrollment; nothing about another class can be requested.
  Future<LearnerResources> listForLearner(String studentId) =>
      _mapped(() async {
        final res = await dio.get<Map<String, dynamic>>(
          '/api/students/$studentId/subject-resources',
        );
        return LearnerResources.fromJson(res.data ?? const {});
      });

  Future<Uint8List> download(String fileId) => files.download(fileId);

  Future<void> delete(String resourceId) => _mapped(() async {
    await dio.delete<dynamic>('/api/subject-resources/$resourceId');
  });
}

/// The learner view: the learner's current class (null when not placed in a
/// class this year) and its active resources across subjects.
class LearnerResources {
  const LearnerResources({
    required this.resources,
    this.className,
    this.academicYearName,
  });

  factory LearnerResources.fromJson(Map<String, dynamic> json) {
    final e = json['enrollment'];
    return LearnerResources(
      className: e is Map ? e['className'] as String? : null,
      academicYearName: e is Map ? e['academicYearName'] as String? : null,
      resources: (json['resources'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => SubjectResource.fromJson(m.cast<String, dynamic>()))
          .toList(),
    );
  }

  final String? className;
  final String? academicYearName;
  final List<SubjectResource> resources;

  bool get notPlaced => className == null;
}
