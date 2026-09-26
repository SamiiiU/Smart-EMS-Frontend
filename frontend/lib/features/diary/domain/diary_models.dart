import 'package:flutter/foundation.dart';

/// One diary entry, as `/api/diary` returns it (verified live 2026-09-18).
///
/// There is no author ID on the wire — only [authorName]. That matters: the
/// backend keys an entry by section + SUBJECT + date, not by teacher, so two
/// teachers of one subject in one section share a single entry, and the name
/// is the only way to tell whose words are already in it.
@immutable
class DiaryEntry {
  const DiaryEntry({
    required this.id,
    required this.sectionId,
    required this.diaryDate,
    this.subjectId,
    this.title,
    this.homework,
    this.classwork,
    this.note,
    this.authorName,
  });

  factory DiaryEntry.fromJson(Map<String, dynamic> json) => DiaryEntry(
        id: json['id'] as String,
        sectionId: json['sectionId'] as String? ?? '',
        diaryDate: json['diaryDate'] as String? ?? '',
        subjectId: json['subjectId'] as String?,
        title: json['title'] as String?,
        homework: json['homework'] as String?,
        classwork: json['classwork'] as String?,
        note: json['note'] as String?,
        authorName: json['authorName'] as String?,
      );

  final String id;
  final String sectionId;

  /// `YYYY-MM-DD`.
  final String diaryDate;
  final String? subjectId;
  final String? title;
  final String? homework;
  final String? classwork;
  final String? note;
  final String? authorName;
}

/// What the teacher is writing. Every field, always.
///
/// This is deliberately the ONLY thing a save is built from, and it has no
/// optional-omission path: `PUT /api/diary/{id}` is a full replace (verified
/// live — a PUT carrying only `homework` nulled `title`, `classwork` and
/// `note`). A form that ever submitted "just the changed field" would wipe
/// the rest silently.
@immutable
class DiaryDraft {
  const DiaryDraft({
    this.title = '',
    this.homework = '',
    this.classwork = '',
    this.note = '',
  });

  factory DiaryDraft.fromEntry(DiaryEntry e) => DiaryDraft(
        title: e.title ?? '',
        homework: e.homework ?? '',
        classwork: e.classwork ?? '',
        note: e.note ?? '',
      );

  final String title;
  final String homework;
  final String classwork;
  final String note;

  bool get isBlank =>
      title.trim().isEmpty &&
      homework.trim().isEmpty &&
      classwork.trim().isEmpty &&
      note.trim().isEmpty;

  DiaryDraft copyWith({
    String? title,
    String? homework,
    String? classwork,
    String? note,
  }) =>
      DiaryDraft(
        title: title ?? this.title,
        homework: homework ?? this.homework,
        classwork: classwork ?? this.classwork,
        note: note ?? this.note,
      );

  /// Blank → null on the wire, so an emptied field is an explicit clear, and
  /// every key is present on every request.
  Map<String, dynamic> toFields() => {
        'title': _orNull(title),
        'homework': _orNull(homework),
        'classwork': _orNull(classwork),
        'note': _orNull(note),
      };

  static String? _orNull(String s) => s.trim().isEmpty ? null : s.trim();
}

/// Section + subject + date: the backend's uniqueness key.
@immutable
class DiaryKey {
  const DiaryKey({
    required this.sectionId,
    required this.subjectId,
    required this.date,
  });

  final String sectionId;
  final String? subjectId;
  final DateTime date;

  String get dateParam =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
