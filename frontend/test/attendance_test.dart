import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/api_config.dart';
import 'package:smartems/core/shell/sync_status.dart';
import 'package:smartems/features/attendance/data/attendance_queue.dart';
import 'package:smartems/features/attendance/data/attendance_repository.dart';
import 'package:smartems/features/attendance/data/queue_sync_status_source.dart';
import 'package:smartems/features/attendance/domain/attendance_models.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.responder);

  final ResponseBody Function(RequestOptions o) responder;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<List<int>>? s,
    Future<void>? c,
  ) async {
    requests.add(o);
    return responder(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromBytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Dio _dio(_Adapter a) =>
    Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))..httpClientAdapter = a;

AttendanceQueue _queue() => AttendanceQueue(NativeDatabase.memory());

AttendanceMark _mark(
  String studentId,
  AttendanceStatus status, {
  String uuid = '',
  bool isCorrection = false,
}) => AttendanceMark(
  clientUuid: uuid.isEmpty ? 'uuid-$studentId' : uuid,
  sectionId: 'sec-1',
  studentId: studentId,
  attendanceDate: '2026-08-05',
  status: status,
  isCorrection: isCorrection,
);

class _FakeConnectivity implements SyncStatusSource {
  _FakeConnectivity(this._status);

  SyncStatus _status;

  void set(SyncStatus s) => _status = s;

  @override
  SyncStatus get current => _status;

  @override
  Stream<SyncStatus> get statusStream => const Stream.empty();
}

void main() {
  test(
    'per-operation receipts remove only committed marks from a partial batch',
    () async {
      final adapter = _Adapter((o) {
        if (o.path.contains(ApiConfig.attendanceSectionPath)) {
          return _json(200, {'records': []});
        }
        return _json(200, {
          'successCount': 1,
          'errorCount': 1,
          'operations': [
            {
              'clientUuid': 'uuid-s1',
              'studentId': 's1',
              'outcome': 'accepted',
              'eventId': 'durable-event',
            },
            {
              'clientUuid': 'uuid-s2',
              'studentId': 's2',
              'outcome': 'rejected',
              'errorCode': 'INVALID_REQUEST',
            },
          ],
        });
      });
      final q = _queue();
      final repo = AttendanceRepository(dio: _dio(adapter), queue: q);
      await expectLater(
        repo.submitRegister([
          _mark('s1', AttendanceStatus.present),
          _mark('s2', AttendanceStatus.late),
        ]),
        throwsStateError,
      );
      expect((await q.pending()).single.clientUuid, 'uuid-s2');
    },
  );

  test(
    'BUG-QA-15: a refused row the server ALREADY holds identically leaves the queue; a differing one stays',
    () async {
      // Pixel finding: unchanged Present rows past the 15-minute lock were refused
      // and retried forever, leaving "Syncing…" / "Submitting…" on screen.
      final adapter = _Adapter((o) {
        if (o.path.contains(ApiConfig.attendanceSectionPath)) {
          return _json(200, {
            'records': [
              {'studentId': 's1', 'status': 'present'},
              {'studentId': 's2', 'status': 'present'},
            ],
          });
        }
        return _json(200, {
          'successCount': 0,
          'errorCount': 2,
          'operations': [
            {
              'clientUuid': 'uuid-s1',
              'studentId': 's1',
              'outcome': 'rejected',
              'errorCode': 'FORBIDDEN',
            },
            {
              'clientUuid': 'uuid-s2',
              'studentId': 's2',
              'outcome': 'rejected',
              'errorCode': 'FORBIDDEN',
            },
          ],
        });
      });
      final q = _queue();
      final repo = AttendanceRepository(dio: _dio(adapter), queue: q);
      await expectLater(
        repo.submitRegister([
          _mark(
            's1',
            AttendanceStatus.present,
          ), // server already holds present: satisfied
          _mark(
            's2',
            AttendanceStatus.absent,
          ), // genuinely different: must stay and be reported
        ]),
        throwsStateError,
      );
      expect((await q.pending()).map((m) => m.clientUuid), ['uuid-s2']);
    },
  );

  test('unknown receipt ID never acknowledges another pending mark', () async {
    final adapter = _Adapter((o) {
      if (o.path.contains(ApiConfig.attendanceSectionPath)) {
        return _json(200, {'records': []});
      }
      return _json(200, {
        'successCount': 1,
        'errorCount': 0,
        'operations': [
          {
            'clientUuid': 'other-operation',
            'studentId': 's1',
            'outcome': 'accepted',
            'eventId': 'event',
          },
        ],
      });
    });
    final q = _queue();
    final repo = AttendanceRepository(dio: _dio(adapter), queue: q);
    await expectLater(
      repo.submitRegister([_mark('s1', AttendanceStatus.present)]),
      throwsStateError,
    );
    expect((await q.pending()).single.clientUuid, 'uuid-s1');
  });

  test(
    'failed enqueue batch rolls back deletion and all preceding inserts',
    () async {
      final q = _queue();
      await q.enqueue([
        _mark('s1', AttendanceStatus.present, uuid: 'original'),
      ]);
      await expectLater(
        q.enqueue([
          _mark('s1', AttendanceStatus.absent, uuid: 'duplicate'),
          _mark('s2', AttendanceStatus.late, uuid: 'duplicate'),
        ]),
        throwsA(anything),
      );
      final remaining = await q.pending();
      expect(remaining.single.clientUuid, 'original');
      expect(remaining.single.status, AttendanceStatus.present);
    },
  );

  group('Web online-only submission', () {
    test(
      'posts to backend without queueing and acknowledges success',
      () async {
        final adapter = _Adapter(
          (o) => _json(200, {'successCount': 1, 'errorCount': 0}),
        );
        final q = _queue();
        final repo = AttendanceRepository(
          dio: _dio(adapter),
          queue: q,
          onlineOnly: true,
        );
        expect(
          await repo.submitRegister([_mark('s1', AttendanceStatus.present)]),
          isA<SubmitSynced>(),
        );
        expect(adapter.requests.single.path, ApiConfig.attendanceBulkPath);
        expect(await q.pendingCount(), 0);
      },
    );
    test('partial acknowledgement is an error, never queued success', () async {
      final adapter = _Adapter(
        (o) => _json(200, {'successCount': 0, 'errorCount': 1}),
      );
      final q = _queue();
      final repo = AttendanceRepository(
        dio: _dio(adapter),
        queue: q,
        onlineOnly: true,
      );
      await expectLater(
        repo.submitRegister([_mark('s1', AttendanceStatus.present)]),
        throwsStateError,
      );
      expect(await q.pendingCount(), 0);
    });
    test(
      'offline Web submission fails without pretending it is durable',
      () async {
        final adapter = _Adapter(
          (o) => throw DioException(
            requestOptions: o,
            type: DioExceptionType.connectionError,
          ),
        );
        final q = _queue();
        final repo = AttendanceRepository(
          dio: _dio(adapter),
          queue: q,
          onlineOnly: true,
        );
        await expectLater(
          repo.submitRegister([_mark('s1', AttendanceStatus.present)]),
          throwsA(isA<DioException>()),
        );
        expect(await q.pendingCount(), 0);
      },
    );
  });

  for (final reply in [
    {'successCount': 1, 'errorCount': 1},
    <String, Object>{},
    {'successCount': 3, 'errorCount': 0},
  ]) {
    test(
      'incomplete bulk acknowledgement preserves original operation IDs: $reply',
      () async {
        final adapter = _Adapter((o) {
          if (o.path.contains(ApiConfig.attendanceSectionPath)) {
            return _json(200, {'records': <Object>[]});
          }
          return _json(200, reply);
        });
        final q = _queue();
        final repo = AttendanceRepository(dio: _dio(adapter), queue: q);
        final marks = [
          _mark('s1', AttendanceStatus.present),
          _mark('s2', AttendanceStatus.late),
        ];
        await expectLater(repo.submitRegister(marks), throwsStateError);
        expect(
          (await q.pending()).map((m) => m.clientUuid).toSet(),
          marks.map((m) => m.clientUuid).toSet(),
        );
      },
    );
  }

  group('AttendanceQueue — persistence', () {
    test('enqueued marks survive and are counted', () async {
      final q = _queue();
      await q.enqueue([
        _mark('s1', AttendanceStatus.present),
        _mark('s2', AttendanceStatus.absent),
      ]);

      expect(await q.pendingCount(), 2);
      final pending = await q.pending();
      expect(pending.map((m) => m.studentId), ['s1', 's2']);
      expect(pending.first.status, AttendanceStatus.present);
    });

    test('re-marking the same student REPLACES the queued row rather than '
        'adding a second one', () async {
      // The queue holds intent, not a keystroke log. Two contradictory rows
      // would make the final state depend on send order.
      final q = _queue();
      await q.enqueue([_mark('s1', AttendanceStatus.present)]);
      await q.enqueue([_mark('s1', AttendanceStatus.absent, uuid: 'uuid-2')]);

      expect(await q.pendingCount(), 1);
      expect((await q.pending()).single.status, AttendanceStatus.absent);
    });

    test('conflicts are recorded and readable back', () async {
      final q = _queue();
      await q.recordConflicts([
        const AttendanceConflict(
          studentId: 's1',
          attendanceDate: '2026-08-05',
          localStatus: AttendanceStatus.present,
          serverStatus: AttendanceStatus.absent,
        ),
      ]);

      final read = await q.conflicts();
      expect(read.single.localStatus, AttendanceStatus.present);
      expect(read.single.serverStatus, AttendanceStatus.absent);
    });
  });

  group('Conflict rule — the server decides, never silently', () {
    test('every queued mark is sent as offline; a server-held review is '
        'acknowledged, surfaced AND recorded', () async {
      // ADR-010 (supersedes the client-side D-T8-03 check): only the server
      // can compare atomically. It keeps its record and holds the differing
      // offline intent as a durable review case, returning a reviewId.
      final adapter = _Adapter((o) {
        if (o.path.contains(ApiConfig.attendanceSectionPath)) {
          return _json(200, {
            'sectionId': 'sec-1',
            'date': '2026-08-05',
            'records': [
              {'studentId': 's1', 'status': 'absent'},
            ],
          });
        }
        final rows = ((o.data as Map)['rows'] as List).cast<Map>();
        return _json(200, {
          'successCount': rows.length,
          'errorCount': 0,
          'operations': [
            for (final r in rows)
              r['studentId'] == 's1'
                  ? {
                      'clientUuid': r['clientUuid'],
                      'studentId': 's1',
                      'outcome': 'review_required',
                      'reviewId': 'rev-1',
                    }
                  : {
                      'clientUuid': r['clientUuid'],
                      'studentId': r['studentId'],
                      'outcome': 'accepted',
                      'eventId': 'ev-${r['studentId']}',
                    },
          ],
        });
      });

      final q = _queue();
      final repo = AttendanceRepository(dio: _dio(adapter), queue: q);

      // Teacher marked s1 present offline; the office has since recorded absent.
      final outcome = await repo.submitRegister([
        _mark('s1', AttendanceStatus.present),
        _mark('s2', AttendanceStatus.late),
      ]);

      expect(outcome, isA<SubmitSynced>());
      final conflicts = (outcome as SubmitSynced).conflicts;
      expect(conflicts.single.studentId, 's1');
      expect(conflicts.single.localStatus, AttendanceStatus.present);
      expect(conflicts.single.serverStatus, AttendanceStatus.absent);

      // Both marks reach the server, flagged as queued offline operations.
      final bulk = adapter.requests.firstWhere(
        (r) => r.path == ApiConfig.attendanceBulkPath,
      );
      expect((bulk.data as Map)['source'], 'offline');
      final rows = (bulk.data as Map)['rows'] as List;
      expect(rows.map((r) => (r as Map)['studentId']), ['s1', 's2']);

      // Recorded, not just returned — a teacher who missed the notice can
      // still find out what is awaiting review.
      expect((await q.conflicts()).single.studentId, 's1');

      // The server holds the reviewed intent durably, so the device may let go.
      expect(await q.pendingCount(), 0);
    });

    test(
      'a review_required outcome without a reviewId is NOT acknowledged',
      () async {
        final adapter = _Adapter((o) {
          if (o.path.contains(ApiConfig.attendanceSectionPath)) {
            return _json(200, {'records': <Object>[]});
          }
          final r = (((o.data as Map)['rows'] as List).single as Map);
          return _json(200, {
            'successCount': 1,
            'errorCount': 0,
            'operations': [
              {
                'clientUuid': r['clientUuid'],
                'studentId': r['studentId'],
                'outcome': 'review_required',
              },
            ],
          });
        });
        final q = _queue();
        final repo = AttendanceRepository(dio: _dio(adapter), queue: q);
        await expectLater(
          repo.submitRegister([_mark('s1', AttendanceStatus.present)]),
          throwsA(isA<StateError>()),
        );
        expect(await q.pendingCount(), 1, reason: 'no silent deletion');
      },
    );

    test('no conflict when the server agrees — the mark IS sent', () async {
      // Positive case pairing the assertion above: the guard is not simply
      // suppressing every send.
      final adapter = _Adapter((o) {
        if (o.path.contains(ApiConfig.attendanceSectionPath)) {
          return _json(200, {'records': <Object>[]});
        }
        return _json(200, {'successCount': 1, 'errorCount': 0});
      });
      final q = _queue();
      final repo = AttendanceRepository(dio: _dio(adapter), queue: q);

      final outcome = await repo.submitRegister([
        _mark('s1', AttendanceStatus.present),
      ]);

      expect((outcome as SubmitSynced).conflicts, isEmpty);
      final bulk = adapter.requests.firstWhere(
        (r) => r.path == ApiConfig.attendanceBulkPath,
      );
      expect(((bulk.data as Map)['rows'] as List).length, 1);
      expect(await q.pendingCount(), 0);
    });
  });

  group('Offline lifecycle', () {
    test('offline submit QUEUES and keeps every mark on disk', () async {
      final adapter = _Adapter((o) {
        throw DioException(
          requestOptions: o,
          type: DioExceptionType.connectionError,
        );
      });
      final q = _queue();
      final repo = AttendanceRepository(dio: _dio(adapter), queue: q);

      final outcome = await repo.submitRegister([
        _mark('s1', AttendanceStatus.present),
        _mark('s2', AttendanceStatus.absent),
      ]);

      expect(outcome, isA<SubmitQueued>());
      expect((outcome as SubmitQueued).pendingCount, 2);
      expect(
        await q.pendingCount(),
        2,
        reason:
            'a failed sync must leave the register intact — losing it is '
            'exactly the failure the offline queue exists to prevent',
      );
    });

    test('reconnecting drains the queue', () async {
      var online = false;
      final adapter = _Adapter((o) {
        if (!online) {
          throw DioException(
            requestOptions: o,
            type: DioExceptionType.connectionError,
          );
        }
        if (o.path.contains(ApiConfig.attendanceSectionPath)) {
          return _json(200, {'records': <Object>[]});
        }
        return _json(200, {'successCount': 2, 'errorCount': 0});
      });
      final q = _queue();
      final repo = AttendanceRepository(dio: _dio(adapter), queue: q);

      await repo.submitRegister([
        _mark('s1', AttendanceStatus.present),
        _mark('s2', AttendanceStatus.absent),
      ]);
      expect(await q.pendingCount(), 2);

      online = true;
      final outcome = await repo.syncPending();

      expect(outcome, isA<SubmitSynced>());
      expect(await q.pendingCount(), 0);
    });

    test('a correction goes through the SINGLE endpoint, not a second bulk '
        'call', () async {
      final adapter = _Adapter((o) {
        if (o.path.contains(ApiConfig.attendanceSectionPath)) {
          return _json(200, {'records': <Object>[]});
        }
        return _json(200, {'eventId': 'e1', 'idempotentReplay': false});
      });
      final repo = AttendanceRepository(dio: _dio(adapter), queue: _queue());

      await repo.correct(_mark('s1', AttendanceStatus.late));

      expect(
        adapter.requests.any((r) => r.path == ApiConfig.attendancePath),
        isTrue,
      );
      expect(
        adapter.requests.any((r) => r.path == ApiConfig.attendanceBulkPath),
        isFalse,
      );
    });
  });

  group('QueueSyncStatusSource — the count is real, not a stub', () {
    test(
      'offline with queued marks reports offline + the true count',
      () async {
        final q = _queue();
        await q.enqueue([
          _mark('s1', AttendanceStatus.present),
          _mark('s2', AttendanceStatus.absent),
        ]);

        final source = QueueSyncStatusSource(
          connectivity: _FakeConnectivity(const SyncStatus.offline()),
          queue: q,
        );
        await source.refresh();

        expect(source.current.state, SyncState.offline);
        expect(source.current.pendingCount, 2);
      },
    );

    test('online with an empty queue reports synced', () async {
      final source = QueueSyncStatusSource(
        connectivity: _FakeConnectivity(const SyncStatus.synced()),
        queue: _queue(),
      );
      await source.refresh();

      expect(source.current.state, SyncState.synced);
      expect(source.current.pendingCount, 0);
    });

    test(
      'online with a non-empty queue reports syncing — a drain is due',
      () async {
        final q = _queue();
        await q.enqueue([_mark('s1', AttendanceStatus.present)]);

        final source = QueueSyncStatusSource(
          connectivity: _FakeConnectivity(const SyncStatus.synced()),
          queue: q,
        );
        await source.refresh();

        expect(source.current.state, SyncState.syncing);
      },
    );
  });

  group('AttendanceStatus wire contract', () {
    test('wire values are the five the backend accepts, lowercase', () {
      expect(AttendanceStatus.values.map((s) => s.wire).toList(), [
        'present',
        'absent',
        'late',
        'leave',
        'excused',
      ]);
    });

    test('an unknown status THROWS rather than being silently mislabelled', () {
      // If the backend grows a sixth status, a silent fallback would show a
      // student the wrong attendance record.
      expect(() => AttendanceStatus.fromWire('detained'), throwsArgumentError);
      expect(AttendanceStatus.fromWire('PRESENT'), AttendanceStatus.present);
    });
  });
}
