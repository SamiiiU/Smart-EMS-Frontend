import 'package:dio/dio.dart';

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
  const AttendanceRepository({required this.dio, required this.queue});

  final Dio dio;
  final AttendanceQueue queue;

  /// The roster. Assembled from TWO calls because no single endpoint
  /// provides it: `/api/enrollments/section/{id}` gives the enrolled
  /// student ids and roll numbers but **no names**, so names come from
  /// `/api/students`. Verified live 2026-08-05 — see BACKEND_CONTRACT.md.
  Future<List<RosterStudent>> loadRoster(String sectionId) async {
    final enrollments = await dio.get<Map<String, dynamic>>(
      '${ApiConfig.enrollmentsSectionPath}/$sectionId',
    );
    final rows = (enrollments.data?['content'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .where((e) => e['status'] == 'enrolled')
        .toList();
    if (rows.isEmpty) return const [];

    final students = await dio.get<Map<String, dynamic>>(
      ApiConfig.studentsPath,
      queryParameters: const {'size': 500},
    );
    final byId = {
      for (final s in (students.data?['content'] as List? ?? const [])
          .cast<Map<String, dynamic>>())
        s['id'] as String: s,
    };

    final roster = <RosterStudent>[];
    for (final e in rows) {
      final id = e['studentId'] as String;
      final s = byId[id];
      roster.add(RosterStudent(
        studentId: id,
        fullName: s == null
            ? 'Unknown student'
            : '${s['firstName'] ?? ''} ${s['lastName'] ?? ''}'.trim(),
        rollNumber: e['rollNumber'] as String?,
      ));
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
  }) async {
    final res = await dio.get<Map<String, dynamic>>(
      '${ApiConfig.attendanceSectionPath}/$sectionId',
      queryParameters: {'date': date},
    );
    final records =
        (res.data?['records'] as List? ?? const []).cast<Map<String, dynamic>>();
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
    await queue.enqueue(marks);
    return syncPending();
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
  /// Conflict rule (D-T8-03): the server's record is authoritative. Where a
  /// queued mark disagrees with what the server already holds, the server
  /// value stands and the disagreement is RECORDED — never silently
  /// dropped. Server state is read BEFORE sending, because the bulk
  /// endpoint's response reports only counts and would erase the evidence.
  Future<SubmitOutcome> syncPending() async {
    final pending = await queue.pending();
    if (pending.isEmpty) return const SubmitSynced();

    final conflicts = <AttendanceConflict>[];
    final sent = <String>[];

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

        final before = await serverStatuses(sectionId: sectionId, date: date);
        final toSend = <AttendanceMark>[];
        for (final m in marks) {
          final serverHeld = before[m.studentId];
          if (serverHeld != null && serverHeld != m.status) {
            // Server wins. Do not send our value at all — sending it would
            // overwrite the authoritative record, which is the opposite of
            // the rule.
            conflicts.add(AttendanceConflict(
              studentId: m.studentId,
              attendanceDate: date,
              localStatus: m.status,
              serverStatus: serverHeld,
            ));
          } else {
            toSend.add(m);
          }
        }

        if (toSend.isNotEmpty) {
          await dio.post<Map<String, dynamic>>(
            ApiConfig.attendanceBulkPath,
            data: {
              'sectionId': sectionId,
              'attendanceDate': date,
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
        }
        // Conflicted marks are resolved too — they leave the queue, since
        // retrying them forever would never succeed.
        sent.addAll(marks.map((m) => m.clientUuid));
      }

      // Corrections go one at a time through the single endpoint (D-T8-02).
      for (final m in pending.where((m) => m.isCorrection)) {
        await dio.post<Map<String, dynamic>>(
          ApiConfig.attendancePath,
          data: {
            'clientUuid': m.clientUuid,
            'studentId': m.studentId,
            'sectionId': m.sectionId,
            'attendanceDate': m.attendanceDate,
            'status': m.status.wire,
          },
        );
        sent.add(m.clientUuid);
      }
    } on DioException catch (err) {
      final failure = mapDioError(err);
      // Offline or server unreachable is the designed path, not a failure:
      // the queue is intact on disk and will drain later.
      if (_isOffline(err)) {
        await queue.remove(sent);
        if (conflicts.isNotEmpty) await queue.recordConflicts(conflicts);
        return SubmitQueued(await queue.pendingCount());
      }
      await queue.remove(sent);
      if (conflicts.isNotEmpty) await queue.recordConflicts(conflicts);
      throw failure;
    }

    await queue.remove(sent);
    if (conflicts.isNotEmpty) await queue.recordConflicts(conflicts);
    return SubmitSynced(conflicts: conflicts);
  }

  static bool _isOffline(DioException err) =>
      err.type == DioExceptionType.connectionError ||
      err.type == DioExceptionType.connectionTimeout ||
      err.type == DioExceptionType.sendTimeout ||
      err.type == DioExceptionType.receiveTimeout;
}
