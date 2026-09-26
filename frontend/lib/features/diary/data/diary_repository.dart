import 'package:dio/dio.dart';

import '../../../core/network/api_config.dart';
import '../../../core/network/api_error_mapper.dart';
import '../domain/diary_models.dart';

/// Diary reads and writes, edit-first.
///
/// **The rule this exists for.** A teacher writing today's diary is not
/// "creating a resource that might conflict" — they are writing today's
/// diary. The backend rejects a second POST on the same section + subject +
/// date with a 409, so the screen asks [findExisting] BEFORE the teacher
/// types, and saves through [update] when an entry exists. The 409 is then
/// reachable only by a genuine race (two tabs), and it surfaces as a real
/// error — never swallowed, because swallowing it would tell the teacher an
/// edit was saved when it was discarded.
class DiaryRepository {
  const DiaryRepository(this.dio);

  final Dio dio;

  Future<T> _mapped<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (err) {
      throw mapDioError(err);
    }
  }

  /// The entry for this key, or null when none exists yet — a NORMAL state
  /// for edit-first, not an error.
  ///
  /// The section endpoint returns every subject's entry for the date; the
  /// match on `subjectId` (including null == null) picks this key's one.
  Future<DiaryEntry?> findExisting(DiaryKey key) => _mapped(() async {
        final res = await dio.get<List<dynamic>>(
          ApiConfig.diarySectionPath(key.sectionId),
          queryParameters: {'date': key.dateParam},
        );
        for (final row in (res.data ?? const []).cast<Map<String, dynamic>>()) {
          final entry = DiaryEntry.fromJson(row);
          if (entry.subjectId == key.subjectId) return entry;
        }
        return null;
      });

  Future<DiaryEntry> create(DiaryKey key, DiaryDraft draft) =>
      _mapped(() async {
        final res = await dio.post<Map<String, dynamic>>(
          ApiConfig.diaryPath,
          data: _body(key, draft),
        );
        return DiaryEntry.fromJson(res.data!);
      });

  /// Full replace — [_body] always carries every field, see [DiaryDraft].
  Future<DiaryEntry> update(String id, DiaryKey key, DiaryDraft draft) =>
      _mapped(() async {
        final res = await dio.put<Map<String, dynamic>>(
          ApiConfig.diaryEntryPath(id),
          data: _body(key, draft),
        );
        return DiaryEntry.fromJson(res.data!);
      });

  static Map<String, dynamic> _body(DiaryKey key, DiaryDraft draft) => {
        'sectionId': key.sectionId,
        'subjectId': key.subjectId,
        'diaryDate': key.dateParam,
        ...draft.toFields(),
      };
}
