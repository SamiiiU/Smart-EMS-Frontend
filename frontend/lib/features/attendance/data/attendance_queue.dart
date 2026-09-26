import 'package:drift/drift.dart';

import '../domain/attendance_models.dart';

/// Minimal [QueryExecutorUser] so a raw [QueryExecutor] can be opened
/// without generated drift code.
///
/// Deliberately codegen-free: `drift_dev` and `riverpod_generator` cannot
/// currently resolve together in this project (CLAUDE.md), and a two-table
/// queue does not justify reopening that fight. Raw SQL through the
/// executor is the whole dependency.
class _QueueUser implements QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

/// The offline attendance queue, PERSISTED.
///
/// This is the reason the native DB seam stopped being `NativeDatabase
/// .memory()` in T8. A teacher marks a register in a classroom with no
/// signal and closes the app; if the queue lived in memory the register
/// would be gone. Everything here survives process death.
class AttendanceQueue {
  AttendanceQueue(this._executor);

  final QueryExecutor _executor;
  bool _opened = false;

  Future<void> _ensureOpen() async {
    if (_opened) return;
    await _executor.ensureOpen(_QueueUser());
    await _executor.runCustom(
      'CREATE TABLE IF NOT EXISTS attendance_queue ('
      'client_uuid TEXT NOT NULL PRIMARY KEY, '
      'section_id TEXT NOT NULL, '
      'student_id TEXT NOT NULL, '
      'attendance_date TEXT NOT NULL, '
      'status TEXT NOT NULL, '
      'is_correction INTEGER NOT NULL DEFAULT 0, '
      'created_at INTEGER NOT NULL)',
    );
    await _executor.runCustom(
      'CREATE TABLE IF NOT EXISTS attendance_conflict ('
      'student_id TEXT NOT NULL, '
      'attendance_date TEXT NOT NULL, '
      'local_status TEXT NOT NULL, '
      'server_status TEXT NOT NULL, '
      'resolved_at INTEGER NOT NULL, '
      'PRIMARY KEY (student_id, attendance_date))',
    );
    _opened = true;
  }

  /// Enqueues marks. Re-marking the same student for the same day REPLACES
  /// the queued row rather than adding a second one — the queue holds
  /// intent ("this student is absent today"), not a keystroke log, and
  /// replaying two contradictory marks would make the final state depend on
  /// send order.
  Future<void> enqueue(List<AttendanceMark> marks) async {
    await _ensureOpen();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final m in marks) {
      await _executor.runCustom(
        'DELETE FROM attendance_queue '
        'WHERE student_id = ? AND attendance_date = ?',
        [m.studentId, m.attendanceDate],
      );
      await _executor.runInsert(
        'INSERT INTO attendance_queue (client_uuid, section_id, student_id, '
        'attendance_date, status, is_correction, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          m.clientUuid,
          m.sectionId,
          m.studentId,
          m.attendanceDate,
          m.status.wire,
          m.isCorrection ? 1 : 0,
          now,
        ],
      );
    }
  }

  Future<List<AttendanceMark>> pending() async {
    await _ensureOpen();
    final rows = await _executor.runSelect(
      'SELECT * FROM attendance_queue ORDER BY created_at ASC',
      const [],
    );
    return rows.map(_toMark).toList(growable: false);
  }

  Future<int> pendingCount() async {
    await _ensureOpen();
    final rows = await _executor.runSelect(
      'SELECT COUNT(*) AS c FROM attendance_queue',
      const [],
    );
    return rows.isEmpty ? 0 : (rows.first['c'] as int? ?? 0);
  }

  /// Removes marks that the server has accepted. Called only AFTER a
  /// successful response — a failed sync must leave the queue intact, or
  /// the register is lost with no trace.
  Future<void> remove(Iterable<String> clientUuids) async {
    await _ensureOpen();
    for (final id in clientUuids) {
      await _executor.runCustom(
        'DELETE FROM attendance_queue WHERE client_uuid = ?',
        [id],
      );
    }
  }

  Future<void> recordConflicts(List<AttendanceConflict> conflicts) async {
    await _ensureOpen();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final c in conflicts) {
      await _executor.runCustom(
        'INSERT OR REPLACE INTO attendance_conflict (student_id, '
        'attendance_date, local_status, server_status, resolved_at) '
        'VALUES (?, ?, ?, ?, ?)',
        [
          c.studentId,
          c.attendanceDate,
          c.localStatus.wire,
          c.serverStatus.wire,
          now,
        ],
      );
    }
  }

  Future<List<AttendanceConflict>> conflicts() async {
    await _ensureOpen();
    final rows = await _executor.runSelect(
      'SELECT * FROM attendance_conflict ORDER BY resolved_at DESC',
      const [],
    );
    return rows
        .map((r) => AttendanceConflict(
              studentId: r['student_id'] as String,
              attendanceDate: r['attendance_date'] as String,
              localStatus: AttendanceStatus.fromWire(r['local_status'] as String),
              serverStatus:
                  AttendanceStatus.fromWire(r['server_status'] as String),
            ))
        .toList(growable: false);
  }

  Future<void> clearConflicts() async {
    await _ensureOpen();
    await _executor.runCustom('DELETE FROM attendance_conflict');
  }

  AttendanceMark _toMark(Map<String, Object?> r) => AttendanceMark(
        clientUuid: r['client_uuid'] as String,
        sectionId: r['section_id'] as String,
        studentId: r['student_id'] as String,
        attendanceDate: r['attendance_date'] as String,
        status: AttendanceStatus.fromWire(r['status'] as String),
        isCorrection: (r['is_correction'] as int? ?? 0) == 1,
      );
}
