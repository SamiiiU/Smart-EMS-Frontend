import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_config.dart';

/// One period from the teacher's day.
///
/// Carries `sectionId` as of Ali's 2026-08-10 change, which unblocked
/// navigation from Today into attendance marking. Verified live against the
/// real response, which turned out to carry MORE than announced — `slotId`,
/// `periodId`, `subjectId`, `teacherStaffId`, `roomId`/`roomName` are all
/// present. Only the fields this app uses are modelled; the rest are
/// recorded in BACKEND_CONTRACT.md so a future task need not re-probe.
@immutable
class TimetablePeriod {
  const TimetablePeriod({
    required this.periodName,
    required this.startTime,
    required this.endTime,
    required this.sortOrder,
    this.sectionId,
    this.sectionName,
    this.subjectId,
    this.subjectName,
  });

  /// camelCase as of Ali's 2026-08-10 change. These endpoints previously
  /// returned raw snake_case DB columns; they now match the rest of the API.
  factory TimetablePeriod.fromJson(Map<String, dynamic> json) {
    return TimetablePeriod(
      periodName: json['periodName'] as String? ?? '',
      startTime: json['startTime'] as String? ?? '',
      endTime: json['endTime'] as String? ?? '',
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      sectionId: json['sectionId'] as String?,
      sectionName: json['sectionName'] as String?,
      subjectId: json['subjectId'] as String?,
      subjectName: json['subjectName'] as String?,
    );
  }

  final String periodName;

  /// `HH:mm:ss` as returned by the API.
  final String startTime;
  final String endTime;
  final int sortOrder;

  /// The section this period teaches. Nullable because a free period or a
  /// break has none — and because a null must NOT silently produce a
  /// register for the wrong class, [TodayScreen] only makes a row tappable
  /// when this is present.
  final String? sectionId;

  /// Already formatted as `{class}-{section}`, e.g. `Class 9-C` — verified
  /// live, so the app does not compose this label itself.
  final String? sectionName;

  /// Needed by the diary (T11): a diary entry is keyed by section + SUBJECT
  /// + date (verified live), so the period is the one place that already
  /// knows both halves of the key.
  final String? subjectId;
  final String? subjectName;

  String get timeLabel =>
      '${_hhmm(startTime)}–${_hhmm(endTime)}';

  static String _hhmm(String t) =>
      t.length >= 5 ? t.substring(0, 5) : t;

  /// True when [now] falls inside this period.
  bool isCurrent(DateTime now) {
    final start = _minutes(startTime);
    final end = _minutes(endTime);
    if (start == null || end == null) return false;
    final mins = now.hour * 60 + now.minute;
    return mins >= start && mins < end;
  }

  static int? _minutes(String t) {
    final parts = t.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }
}

class TimetableRepository {
  const TimetableRepository(this.dio);

  final Dio dio;

  Future<List<TimetablePeriod>> todayFor(String staffId) async {
    final res = await dio.get<List<dynamic>>(
      '${ApiConfig.teacherTimetablePath}/$staffId/today',
    );
    return (res.data ?? const [])
        .cast<Map<String, dynamic>>()
        .map(TimetablePeriod.fromJson)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }
}
