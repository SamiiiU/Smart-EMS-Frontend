import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/shell/sync_status.dart';
import 'package:smartems/features/attendance/data/attendance_queue.dart';
import 'package:smartems/features/attendance/data/attendance_repository.dart';
import 'package:smartems/features/attendance/data/attendance_sync_coordinator.dart';
import 'package:smartems/features/attendance/domain/attendance_models.dart';

/// F13 (physical Pixel 7 Pro): offline marks must drain without a new submit.
class _Connectivity implements SyncStatusSource {
  final controller = StreamController<SyncStatus>.broadcast();
  @override
  SyncStatus current = const SyncStatus.offline();
  @override
  Stream<SyncStatus> get statusStream => controller.stream;
  void emit(SyncStatus s) {
    current = s;
    controller.add(s);
  }
}

/// Server unreachable until [online]; acknowledges (removes) only what it received.
class _Repo extends AttendanceRepository {
  _Repo(AttendanceQueue queue) : super(dio: Dio(), queue: queue, onlineOnly: false);
  bool online = false;
  int calls = 0, concurrent = 0, maxConcurrent = 0;
  final sent = <String>[];
  @override
  Future<SubmitOutcome> syncPending() async {
    calls++;
    concurrent++;
    if (concurrent > maxConcurrent) maxConcurrent = concurrent;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (!online) throw DioException(requestOptions: RequestOptions(path: '/api/attendance/bulk'));
      final pending = await queue.pending();
      sent.addAll(pending.map((m) => m.clientUuid));
      await queue.remove(pending.map((m) => m.clientUuid));
      return const SubmitSynced();
    } finally {
      concurrent--;
    }
  }
}

AttendanceMark _mark(String id) => AttendanceMark(
    clientUuid: id, sectionId: 's', studentId: 'st-$id', attendanceDate: '2026-10-13', status: AttendanceStatus.absent);

void main() {
  f16();
  TestWidgetsFlutterBinding.ensureInitialized();

  test('queued marks drain on reconnect with the same operation IDs, no duplicate sends', () async {
    final queue = AttendanceQueue(NativeDatabase.memory());
    await queue.enqueue([_mark('op-1'), _mark('op-2')]);
    final net = _Connectivity();
    final repo = _Repo(queue);
    final c = AttendanceSyncCoordinator(repository: repo, queue: queue, connectivity: net,
        minBackoff: const Duration(milliseconds: 50), maxBackoff: const Duration(milliseconds: 200));
    c.start();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(await queue.pendingCount(), 2, reason: 'unknown outcome keeps every operation');
    expect(repo.sent, isEmpty);

    repo.online = true;
    net.emit(const SyncStatus.synced());
    // Several triggers at once must coalesce into one drain.
    unawaited(c.trigger());
    unawaited(c.trigger());
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(await queue.pendingCount(), 0);
    expect(repo.sent, ['op-1', 'op-2'], reason: 'same IDs, sent once');
    expect(repo.maxConcurrent, 1);
    c.dispose();
  });

  test('without any connectivity event, the backoff timer still retries', () async {
    final queue = AttendanceQueue(NativeDatabase.memory());
    await queue.enqueue([_mark('op-9')]);
    final repo = _Repo(queue);
    final c = AttendanceSyncCoordinator(repository: repo, queue: queue, connectivity: _Connectivity(),
        minBackoff: const Duration(milliseconds: 40), maxBackoff: const Duration(milliseconds: 80));
    c.start();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    repo.online = true; // server came back; the phone's network state never changed
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(await queue.pendingCount(), 0);
    expect(repo.calls, greaterThanOrEqualTo(2));
    c.dispose();
  });
}

/// F16 (physical device): a transport failure with no response, or a gateway
/// outage, is "queued for retry", never a hard "could not submit" error.
class _FailingAdapter implements HttpClientAdapter {
  _FailingAdapter(this.fail);
  final DioException Function(RequestOptions) fail;
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async => throw fail(o);
  @override
  void close({bool force = false}) {}
}

void f16() {
  for (final entry in <String, DioException Function(RequestOptions)>{
    'connection dropped (no response)': (o) => DioException(requestOptions: o, type: DioExceptionType.unknown, error: 'Connection closed'),
    'proxy 502': (o) => DioException(requestOptions: o, type: DioExceptionType.badResponse,
        response: Response(requestOptions: o, statusCode: 502)),
    'API 503': (o) => DioException(requestOptions: o, type: DioExceptionType.badResponse,
        response: Response(requestOptions: o, statusCode: 503)),
  }.entries) {
    test('F16: ${entry.key} keeps marks queued and reports SubmitQueued', () async {
      final queue = AttendanceQueue(NativeDatabase.memory());
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))..httpClientAdapter = _FailingAdapter(entry.value);
      final repo = AttendanceRepository(dio: dio, queue: queue, onlineOnly: false);
      final outcome = await repo.submitRegister([_mark('op-a'), _mark('op-b')]);
      expect(outcome, isA<SubmitQueued>());
      expect(await queue.pendingCount(), 2);
    });
  }
}
