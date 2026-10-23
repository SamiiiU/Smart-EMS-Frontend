import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/attendance_models.dart';
import 'attendance_queue.dart';

/// New account-scoped vault. Legacy unowned SQLite rows are deliberately not
/// imported: a login does not prove who authored an old pending operation.
/// One instance owns writes within this application isolate.
class SecureAttendanceQueue extends AttendanceQueue {
  // ignore: use_super_parameters
  SecureAttendanceQueue(
    QueryExecutor legacyExecutor, {
    required this.owner,
    FlutterSecureStorage? storage,
  }) : storage =
           storage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(resetOnError: false),
           ),
       super(legacyExecutor);

  /// Opaque stable tenant/user identity, never a role or display name.
  final String? Function() owner;
  final FlutterSecureStorage storage;
  Future<void> _tail = Future<void>.value();

  @override
  String? get scopeIdentity => owner();

  Future<T> _access<T>(
    T Function(Map<String, dynamic>) action, {
    bool write = false,
  }) {
    final captured = owner();
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        if (captured == null || captured.isEmpty || owner() != captured) {
          throw StateError(
            'Sign in to the original account to access pending attendance.',
          );
        }
        final key = 'attendance.v2.${base64Url.encode(utf8.encode(captured))}';
        final raw = await storage.read(key: key);
        if (owner() != captured) {
          throw StateError('Account changed during attendance access.');
        }
        final data = raw == null
            ? <String, dynamic>{
                'version': 2,
                'owner': captured,
                'marks': <dynamic>[],
                'conflicts': <dynamic>[],
              }
            : jsonDecode(raw) as Map<String, dynamic>;
        if (data['version'] != 2 || data['owner'] != captured) {
          throw StateError('Attendance vault ownership or version mismatch.');
        }
        final value = action(data);
        if (write) {
          final encoded = jsonEncode(data);
          if (utf8.encode(encoded).length > 2 * 1024 * 1024) {
            throw StateError(
              'Pending attendance storage is full. Sync existing marks before adding more.',
            );
          }
          if (owner() != captured) {
            throw StateError('Account changed during attendance access.');
          }
          await storage.write(key: key, value: encoded);
        }
        if (owner() != captured) {
          throw StateError('Account changed during attendance access.');
        }
        result.complete(value);
      } catch (e, stack) {
        result.completeError(e, stack);
      }
    });
    return result.future;
  }

  @override
  Future<void> enqueue(List<AttendanceMark> marks) => _access((data) {
    final rows = data['marks'] as List;
    for (final mark in marks) {
      // Do not replace a prior unknown-outcome operation with a new ID.
      final encoded = <String, dynamic>{
        'id': mark.clientUuid,
        'section': mark.sectionId,
        'student': mark.studentId,
        'date': mark.attendanceDate,
        'status': mark.status.wire,
        'correction': mark.isCorrection,
      };
      final existing = rows.where((r) => r['id'] == mark.clientUuid);
      if (existing.isNotEmpty) {
        if (jsonEncode(existing.first) != jsonEncode(encoded)) {
          throw StateError(
            'Attendance operation ID cannot be reused for different data.',
          );
        }
        continue;
      }
      rows.add(encoded);
    }
  }, write: true).then((_) => notifyChanged());

  @override
  Future<List<AttendanceMark>> pending() {
    if (owner() == null) return Future.value(const []);
    return _access(
      (data) => (data['marks'] as List)
          .map(
            (r) => AttendanceMark(
              clientUuid: r['id'] as String,
              sectionId: r['section'] as String,
              studentId: r['student'] as String,
              attendanceDate: r['date'] as String,
              status: AttendanceStatus.fromWire(r['status'] as String),
              isCorrection: r['correction'] as bool,
            ),
          )
          .toList(),
    );
  }

  @override
  Future<int> pendingCount() async => (await pending()).length;

  @override
  Future<void> remove(Iterable<String> clientUuids) => _access((data) {
    final ids = clientUuids.toSet();
    (data['marks'] as List).removeWhere((r) => ids.contains(r['id']));
  }, write: true).then((_) => notifyChanged());

  @override
  Future<void> recordConflicts(List<AttendanceConflict> conflicts) =>
      _access((data) {
        final rows = data['conflicts'] as List;
        for (final c in conflicts) {
          rows.add({
            'student': c.studentId,
            'date': c.attendanceDate,
            'local': c.localStatus.wire,
            'server': c.serverStatus.wire,
          });
        }
      }, write: true).then((_) => notifyChanged());

  @override
  Future<List<AttendanceConflict>> conflicts() {
    if (owner() == null) return Future.value(const []);
    return _access(
      (data) => (data['conflicts'] as List)
          .map(
            (r) => AttendanceConflict(
              studentId: r['student'] as String,
              attendanceDate: r['date'] as String,
              localStatus: AttendanceStatus.fromWire(r['local'] as String),
              serverStatus: AttendanceStatus.fromWire(r['server'] as String),
            ),
          )
          .toList(),
    );
  }

  @override
  Future<void> clearConflicts() => _access((data) {
    (data['conflicts'] as List).clear();
  }, write: true).then((_) => notifyChanged());
}
