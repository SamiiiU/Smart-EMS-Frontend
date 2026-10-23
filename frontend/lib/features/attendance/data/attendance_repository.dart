import 'package:smartems/core/network/paged_get.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../../core/network/api_config.dart';
import '../../../core/network/api_error_mapper.dart';
import '../domain/attendance_models.dart';
import 'attendance_queue.dart';

/// Outcome of submitting a register.
sealed class SubmitOutcome {
  const SubmitOutcome();
}

/// Reached the server. [conflicts] is non-empty when the server already held
/// a different status for a student — resolved in the server's favour.
class SubmitSynced extends SubmitOutcome {
  const SubmitSynced({this.conflicts = const []});

  final List<AttendanceConflict> conflicts;
}

/// Could not reach the server; the marks are safely queued on disk and will
/// go out when connectivity returns. NOT an error state — this is the
/// designed offline path.
class SubmitQueued extends SubmitOutcome {
  const SubmitQueued(this.pendingCount);

  final int pendingCount;
}

class AttendanceRepository {
  const AttendanceRepository({
    required this.dio,
    required this.queue,
    this.onlineOnly = kIsWeb,
  });

  final Dio dio;
  final AttendanceQueue queue;
  final bool onlineOnly;

  /// The roster. Assembled from TWO calls because no single endpoint
  /// provides it: `/api/enrollments/section/{id}` gives the enrolled
  /// student ids and roll numbers but **no names**, so names come from
  /// `/api/students`. Verified live 2026-08-05 — see BACKEND_CONTRACT.md.
  /// Registers this teacher may open, from the server's teaching-assignment
  /// rules (hard-QA BUG-QA-11). An older server without the endpoint (404)
  /// yields an empty list, so the timetable path keeps working.
  Future<List<MyRegister>> mySections() async {
    try {
      final res = await dio.get<List<dynamic>>('/api/attendance/my-sections');
      return [
        for (final r in (res.data ?? const []).whereType<Map<dynamic, dynamic>>())
          if (r['sectionId'] is String)
            MyRegister(
              sectionId: r['sectionId'] as String,
              label: [r['className'], r['sectionName']].whereType<String>().join(' · '),
            ),
      ];
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return const [];
      rethrow;
    }
  }

  Future<List<RosterStudent>> loadRoster(String sectionId) async {
    final enrollments = await dio.get<Map<String, dynamic>>(
      '${ApiConfig.enrollmentsSectionPath}/$sectionId',
    );
    final rows = (enrollments.data?['content'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .where((e) => e['status'] == 'enrolled')
        .toList();
    if (rows.isEmpty) return const [];

    final students = await dio.getAllPages(ApiConfig.studentsPath);
    final byId = {for (final s in students) s['id'] as String: s};

    final roster = <RosterStudent>[];
    for (final e in rows) {
      final id = e['studentId'] as String;
      final s = byId[id];
      roster.add(
        RosterStudent(
          studentId: id,
          fullName: s == null
              ? 'Unknown student'
              : '${s['firstName'] ?? ''} ${s['lastName'] ?? ''}'.trim(),
          rollNumber: e['rollNumber'] as String?,
        ),
      );
    }
    roster.sort((a, b) => a.fullName.compareTo(b.fullName));
    return roster;
  }

  /// Server-held statuses for a section on a date, keyed by student id.
  /// Empty before anything is marked — the endpoint is a SUMMARY, not a
  /// roster (verified live).
  Future<Map<String, AttendanceStatus>> serverStatuses({
    required String sectionId,
    required String date,
    String? expectedOwner,
  }) async {
    final res = await dio.get<Map<String, dynamic>>(
      '${ApiConfig.attendanceSectionPath}/$sectionId',
      queryParameters: {'date': date},
      options: Options(extra: {'attendanceOwner': expectedOwner}),
    );
    final records = (res.data?['records'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final out = <String, AttendanceStatus>{};
    for (final r in records) {
      final id = (r['studentId'] ?? r['student_id']) as String?;
      final status = (r['status']) as String?;
      if (id != null && status != null) {
        out[id] = AttendanceStatus.fromWire(status);
      }
    }
    return out;
  }

  /// Submits a whole register. Queues first, then attempts to sync, so a
  /// crash between the two loses nothing.
  Future<SubmitOutcome> submitRegister(List<AttendanceMark> marks) async {
    if (onlineOnly) return _submitOnline(marks);
    await queue.enqueue(marks);
    return syncPending();
  }

  // Web has no durable offline database. Only an explicit server
  // acknowledgement can report success; network failures remain errors.
  Future<SubmitOutcome> _submitOnline(List<AttendanceMark> marks) async {
    final groups = <String, List<AttendanceMark>>{};
    for (final mark in marks) {
      if (mark.isCorrection) {
        await dio.post<Map<String, dynamic>>(
          ApiConfig.attendancePath,
          data: {
            'clientUuid': mark.clientUuid,
            'studentId': mark.studentId,
            'sectionId': mark.sectionId,
            'attendanceDate': mark.attendanceDate,
            'status': mark.status.wire,
          },
        );
      } else {
        groups
            .putIfAbsent('${mark.sectionId}|${mark.attendanceDate}', () => [])
            .add(mark);
      }
    }
    for (final group in groups.values) {
      final response = await dio.post<Map<String, dynamic>>(
        ApiConfig.attendanceBulkPath,
        data: {
          'sectionId': group.first.sectionId,
          'attendanceDate': group.first.attendanceDate,
          'rows': [
            for (final mark in group)
              {
                'clientUuid': mark.clientUuid,
                'studentId': mark.studentId,
                'status': mark.status.wire,
              },
          ],
        },
      );
      if (_acknowledgedIds(response.data, group).length != group.length) {
        throw StateError(
          'Attendance was not fully acknowledged. Keep this page open and retry.',
        );
      }
    }
    return const SubmitSynced();
  }

  /// A single post-submission correction. Same queue-then-sync path, so a
  /// correction made offline is as durable as the original register.
  Future<SubmitOutcome> correct(AttendanceMark mark) {
    return submitRegister([
      AttendanceMark(
        clientUuid: mark.clientUuid,
        sectionId: mark.sectionId,
        studentId: mark.studentId,
        attendanceDate: mark.attendanceDate,
        status: mark.status,
        isCorrection: true,
      ),
    ]);
  }

  /// Drains the queue.
  ///
  /// Conflict rule (ADR-010, supersedes D-T8-03's client-side check): the server
  /// decides atomically. A queued mark that disagrees with server state is held
  /// there as a durable review case (`review_required`) for a campus reviewer;
  /// it is removed from the device only once the server acknowledged it, and
  /// recorded locally so the teacher sees it is awaiting review.
  Future<SubmitOutcome> syncPending() async {
    if (onlineOnly) return const SubmitSynced();
    final scope = queue.scopeIdentity;
    final pending = await queue.pending();
    _assertScope(scope);
    if (pending.isEmpty) return const SubmitSynced();

    final conflicts = <AttendanceConflict>[];
    final sent = <String>[];
    var incomplete = false;

    // Group by section+date: one bulk call per register.
    final groups = <String, List<AttendanceMark>>{};
    for (final m in pending.where((m) => !m.isCorrection)) {
      groups.putIfAbsent('${m.sectionId}|${m.attendanceDate}', () => []).add(m);
    }

    try {
      for (final entry in groups.entries) {
        final parts = entry.key.split('|');
        final sectionId = parts[0];
        final date = parts[1];
        final marks = entry.value;

        final before = await serverStatuses(
          sectionId: sectionId,
          date: date,
          expectedOwner: scope,
        );
        // ADR-010: the SERVER decides conflicts atomically. Every queued mark is
        // sent as `offline`; one that differs from server state (or arrives
        // after closing time + 72h) is held there as a durable review case and
        // acknowledged with a reviewId, never applied over the current record.
        // `before` is read only to show the teacher what the server holds.
        final toSend = marks;

        if (toSend.isNotEmpty) {
          final response = await dio.post<Map<String, dynamic>>(
            ApiConfig.attendanceBulkPath,
            options: Options(extra: {'attendanceOwner': scope}),
            data: {
              'sectionId': sectionId,
              'attendanceDate': date,
              'source': 'offline',
              'rows': [
                for (final m in toSend)
                  {
                    'studentId': m.studentId,
                    'status': m.status.wire,
                    'clientUuid': m.clientUuid,
                  },
              ],
            },
          );
          final held = <String>{};
          final accepted = _acknowledgedIds(response.data, toSend, held: held);
          sent.addAll(accepted);
          // BUG-QA-15: a row the server refused while ALREADY holding exactly
          // this status (e.g. an unchanged mark past the 15-minute lock) is
          // satisfied: nothing is lost by dropping it, and keeping it would
          // retry forever. A row that genuinely differs stays queued.
          for (final m in toSend) {
            if (!accepted.contains(m.clientUuid) && before[m.studentId] == m.status) {
              sent.add(m.clientUuid);
              accepted.add(m.clientUuid);
            }
          }
          for (final m in toSend.where((m) => held.contains(m.clientUuid))) {
            final serverHeld = before[m.studentId];
            if (serverHeld != null && serverHeld != m.status) {
              conflicts.add(AttendanceConflict(
                studentId: m.studentId,
                attendanceDate: date,
                localStatus: m.status,
                serverStatus: serverHeld,
              ));
            }
          }
          incomplete = incomplete || accepted.length != toSend.length;
        }
      }

      // Corrections go one at a time through the single endpoint (D-T8-02).
      for (final m in pending.where((m) => m.isCorrection)) {
        await dio.post<Map<String, dynamic>>(
          ApiConfig.attendancePath,
          options: Options(extra: {'attendanceOwner': scope}),
          data: {
            'clientUuid': m.clientUuid,
            'studentId': m.studentId,
            'sectionId': m.sectionId,
            'attendanceDate': m.attendanceDate,
            'status': m.status.wire,
            'source': 'offline',
          },
        );
        // 201/200 applied, or 202 held for review on the server: both durable.
        sent.add(m.clientUuid);
      }
    } on DioException catch (err) {
      final failure = mapDioError(err);
      // Offline or server unreachable is the designed path, not a failure:
      // the queue is intact on disk and will drain later.
      if (_isOffline(err)) {
        _assertScope(scope);
        if (conflicts.isNotEmpty) await queue.recordConflicts(conflicts);
        _assertScope(scope);
        await queue.remove(sent);
        return SubmitQueued(await queue.pendingCount());
      }
      _assertScope(scope);
      if (conflicts.isNotEmpty) await queue.recordConflicts(conflicts);
      _assertScope(scope);
      await queue.remove(sent);
      throw failure;
    }

    _assertScope(scope);
    if (conflicts.isNotEmpty) await queue.recordConflicts(conflicts);
    _assertScope(scope);
    await queue.remove(sent);
    if (incomplete) {
      throw StateError(
        'Attendance was not fully acknowledged. Unaccepted marks remain queued for retry.',
      );
    }
    return SubmitSynced(conflicts: conflicts);
  }

  /// Operations the server acknowledged durably: applied (`accepted` with an
  /// eventId) or held for review (`review_required` with a reviewId, also
  /// collected into [held]). Anything else stays queued.
  Set<String> _acknowledgedIds(
    Map<String, dynamic>? result,
    List<AttendanceMark> marks, {
    Set<String>? held,
  }) {
    if (result == null) return {};
    final expected = {
      for (final mark in marks) mark.clientUuid: mark.studentId,
    };
    if (expected.length != marks.length) return {};
    final operations = result['operations'];
    // Compatibility with older servers: counts can only acknowledge a whole group.
    if (operations == null) {
      return result['errorCount'] == 0 && result['successCount'] == marks.length
          ? expected.keys.toSet()
          : {};
    }
    if (operations is! List || operations.length != marks.length) return {};
    final seen = <String>{};
    final accepted = <String>{};
    for (final item in operations) {
      if (item is! Map) return {};
      final id = item['clientUuid'];
      if (id is! String ||
          !expected.containsKey(id) ||
          !seen.add(id) ||
          expected[id] != item['studentId']) {
        return {};
      }
      if (item['outcome'] == 'accepted') {
        if (item['eventId'] is! String || (item['eventId'] as String).isEmpty) {
          return {};
        }
        accepted.add(id);
      } else if (item['outcome'] == 'review_required') {
        if (item['reviewId'] is! String || (item['reviewId'] as String).isEmpty) {
          return {};
        }
        accepted.add(id);
        held?.add(id);
      } else if (item['outcome'] != 'rejected' ||
          item['errorCode'] is! String) {
        return {};
      }
    }
    if (result['successCount'] != accepted.length ||
        result['errorCount'] != marks.length - accepted.length) {
      return {};
    }
    return accepted;
  }

  void _assertScope(String? expected) {
    if (queue.scopeIdentity != expected) {
      throw StateError(
        'Account changed. Pending attendance remains with its original account.',
      );
    }
  }

  /// F16 (physical device): a connection dropped by a tunnel/proxy surfaces as
  /// a transport failure with NO response, and a proxy in front of a down API
  /// answers 502/503/504. Both are "queued, will retry" — not a hard error.
  static bool _isOffline(DioException err) {
    final status = err.response?.statusCode;
    return err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        (err.type == DioExceptionType.unknown && err.response == null) ||
        status == 502 ||
        status == 503 ||
        status == 504;
  }
}

/// One register a teacher may open (see [AttendanceRepository.mySections]).
class MyRegister {
  const MyRegister({required this.sectionId, required this.label});
  final String sectionId;
  final String label;
}
