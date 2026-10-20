import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/api_config.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/app_button.dart';
import 'package:smartems/features/attendance/data/attendance_repository.dart';
import 'package:smartems/features/attendance/data/attendance_queue.dart';
import 'package:smartems/features/attendance/domain/attendance_models.dart';
import 'package:smartems/features/attendance/domain/lock_window.dart';
import 'package:smartems/features/attendance/presentation/attendance_marking_screen.dart';

/// RC finding (report 13 §11, Pixel): a reopened School register showed a
/// learner whose mark was still in the account's offline queue as UNMARKED,
/// inviting a second mark under a new operation id. The register now merges
/// the SIGNED-IN account's queued marks (same section and date) as Pending and
/// locks them until they sync; server state stays authoritative afterwards.
class _Server {
  final records = <String, String>{}; // studentId -> status held by the server
  bool online = true;
  final posts = <Map<dynamic, dynamic>>[];
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.server);
  final _Server server;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<List<int>>? s,
    Future<void>? c,
  ) async {
    ResponseBody json(int status, Object body) => ResponseBody.fromBytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
    if (o.path.contains(ApiConfig.enrollmentsSectionPath)) {
      return json(200, {
        'content': [
          {'studentId': 'st1', 'status': 'enrolled', 'rollNumber': '1'},
          {'studentId': 'st2', 'status': 'enrolled', 'rollNumber': '2'},
        ],
      });
    }
    if (o.path == ApiConfig.studentsPath) {
      return json(200, {
        'content': [
          {'id': 'st1', 'firstName': 'Bilal', 'lastName': 'Ahmed'},
          {'id': 'st2', 'firstName': 'Fatima', 'lastName': 'Noor'},
        ],
      });
    }
    if (o.path.contains(ApiConfig.attendanceSectionPath)) {
      return json(200, {
        'records': [
          for (final e in server.records.entries)
            {'studentId': e.key, 'status': e.value},
        ],
      });
    }
    if (o.path == ApiConfig.attendanceBulkPath) {
      if (!server.online) {
        throw DioException(
          requestOptions: o,
          type: DioExceptionType.connectionError,
        );
      }
      final body = o.data as Map;
      server.posts.add(body);
      final rows = (body['rows'] as List).cast<Map>();
      for (final r in rows) {
        server.records[r['studentId'] as String] = r['status'] as String;
      }
      return json(200, {
        'successCount': rows.length,
        'errorCount': 0,
        'operations': [
          for (final r in rows)
            {
              'clientUuid': r['clientUuid'],
              'studentId': r['studentId'],
              'outcome': 'accepted',
              'eventId': 'ev-${r['studentId']}',
            },
        ],
      });
    }
    return json(404, {'status': 404});
  }

  @override
  void close({bool force = false}) {}
}

AttendanceMark _mark(
  String id,
  String student,
  AttendanceStatus status, {
  String section = 'sec-1',
  String date = '2026-08-05',
}) => AttendanceMark(
  clientUuid: id,
  sectionId: section,
  studentId: student,
  attendanceDate: date,
  status: status,
);

String? owner = 'tenant:teacher1';

/// Same owner-scoping contract as SecureAttendanceQueue (whose real isolation
/// is proven in secure_attendance_queue_test.dart): one vault per account, no
/// account = fail closed, every write notifies. In-memory so it is
/// deterministic under the widget tester's fake async.
class _OwnerQueue extends AttendanceQueue {
  _OwnerQueue() : super(NativeDatabase.memory());
  final _vaults = <String, List<AttendanceMark>>{};
  List<AttendanceMark> _vault() {
    final o = owner;
    if (o == null) {
      throw StateError(
        'Sign in to the original account to access pending attendance.',
      );
    }
    return _vaults.putIfAbsent(o, () => []);
  }

  @override
  String? get scopeIdentity => owner;
  @override
  Future<void> enqueue(List<AttendanceMark> marks) async {
    final v = _vault();
    for (final m in marks) {
      if (!v.any((x) => x.clientUuid == m.clientUuid)) v.add(m);
    }
    notifyChanged();
  }

  @override
  Future<List<AttendanceMark>> pending() async => List.of(_vault());
  @override
  Future<int> pendingCount() async => _vault().length;
  @override
  Future<void> remove(Iterable<String> clientUuids) async {
    final ids = clientUuids.toSet();
    _vault().removeWhere((m) => ids.contains(m.clientUuid));
    notifyChanged();
  }

  @override
  Future<void> recordConflicts(List<AttendanceConflict> conflicts) async =>
      notifyChanged();
  @override
  Future<List<AttendanceConflict>> conflicts() async => const [];
  @override
  Future<void> clearConflicts() async {}
}

AttendanceRepository _repo(_Server server, AttendanceQueue q) =>
    AttendanceRepository(
      dio: Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))
        ..httpClientAdapter = _Adapter(server),
      queue: q,
    );

Future<void> _open(WidgetTester tester, AttendanceRepository repo) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(role: AppRole.teacher),
      home: AttendanceMarkingScreen(
        repository: repo,
        sectionId: 'sec-1',
        sectionLabel: 'Class 9-C',
        attendanceDate: DateTime(2026, 8, 5),
        lockWindow: const LockWindow.immediate(),
        now: () => DateTime(2026, 8, 5, 10),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle();

void main() {
  late _OwnerQueue queue;
  setUp(() {
    owner = 'tenant:teacher1';
    queue = _OwnerQueue();
  });

  testWidgets(
    'reopened register shows this account\'s queued mark as Pending, locked, and never resends it',
    (tester) async {
      await queue.enqueue([_mark('op-1', 'st1', AttendanceStatus.absent)]);
      final server = _Server()..online = false;
      final repo = _repo(server, queue);
      await _open(tester, repo);

      expect(
        find.byKey(const Key('pending-st1')),
        findsOneWidget,
        reason: 'queued, not Unmarked',
      );
      expect(find.byKey(const Key('unmarked-st1')), findsNothing);
      expect(find.byKey(const Key('queued-note-st1')), findsOneWidget);
      expect(
        find.byKey(const Key('unmarked-st2')),
        findsOneWidget,
        reason: 'others unaffected',
      );

      // Locked: a tap on another status changes nothing and creates no operation.
      await tester.tap(
        find.bySemanticsLabel('Present for Bilal Ahmed'),
        warnIfMissed: false,
      );
      await _settle(tester);
      expect((await queue.pending()).single.status, AttendanceStatus.absent);
      expect((await queue.pending()).single.clientUuid, 'op-1');

      // Submitting the rest never re-queues the pending learner under a new id.
      await tester.tap(find.bySemanticsLabel('Late for Fatima Noor'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Submit'));
      await _settle(tester);
      final pending = await queue.pending();
      expect(
        pending.where((m) => m.studentId == 'st1').map((m) => m.clientUuid),
        ['op-1'],
        reason: 'exactly one op for st1',
      );
      expect(pending.where((m) => m.studentId == 'st2'), hasLength(1));
    },
  );

  testWidgets('another account\'s queued mark is never shown or adopted', (
    tester,
  ) async {
    owner = 'tenant:teacher2';
    await queue.enqueue([_mark('op-other', 'st1', AttendanceStatus.absent)]);
    owner = 'tenant:teacher1';
    await _open(tester, _repo(_Server()..online = false, queue));
    expect(find.byKey(const Key('unmarked-st1')), findsOneWidget);
    expect(find.byKey(const Key('pending-st1')), findsNothing);
    expect(find.byKey(const Key('queued-note-st1')), findsNothing);
  });

  testWidgets(
    'queued marks for another section or date do not leak into this register',
    (tester) async {
      await queue.enqueue([
        _mark('op-sec', 'st1', AttendanceStatus.absent, section: 'sec-2'),
        _mark('op-date', 'st2', AttendanceStatus.late, date: '2026-08-04'),
      ]);
      await _open(tester, _repo(_Server()..online = false, queue));
      expect(find.byKey(const Key('unmarked-st1')), findsOneWidget);
      expect(find.byKey(const Key('unmarked-st2')), findsOneWidget);
      expect(find.byKey(const Key('pending-st1')), findsNothing);
    },
  );

  testWidgets(
    'after sync the row unlocks and shows the server-authoritative status',
    (tester) async {
      await queue.enqueue([_mark('op-1', 'st1', AttendanceStatus.absent)]);
      final server = _Server()..online = false;
      final repo = _repo(server, queue);
      await _open(tester, repo);
      expect(find.byKey(const Key('queued-note-st1')), findsOneWidget);

      server.online = true;
      (repo.syncPending());
      await _settle(tester);
      expect(server.posts, hasLength(1));
      expect(server.records['st1'], 'absent');
      expect(
        find.byKey(const Key('queued-note-st1')),
        findsNothing,
        reason: 'left the queue',
      );
      expect(
        find.byKey(const Key('pending-st1')),
        findsNothing,
        reason: 'server now holds it',
      );
      expect(await queue.pendingCount(), 0);
    },
  );

  testWidgets('a failed sync keeps the mark Pending and locked', (
    tester,
  ) async {
    await queue.enqueue([_mark('op-1', 'st1', AttendanceStatus.absent)]);
    final server = _Server()..online = false;
    final repo = _repo(server, queue);
    await _open(tester, repo);
    (repo.syncPending());
    await _settle(tester);
    expect(find.byKey(const Key('pending-st1')), findsOneWidget);
    expect(find.byKey(const Key('queued-note-st1')), findsOneWidget);
    expect(await queue.pendingCount(), 1);
  });

  testWidgets(
    'no signed-in account (logout): nothing is overlaid and nothing crashes',
    (tester) async {
      await queue.enqueue([_mark('op-1', 'st1', AttendanceStatus.absent)]);
      owner = null;
      await _open(tester, _repo(_Server()..online = false, queue));
      expect(find.byKey(const Key('unmarked-st1')), findsOneWidget);
      expect(find.byKey(const Key('pending-st1')), findsNothing);
      owner = 'tenant:teacher1';
      expect(
        await queue.pendingCount(),
        1,
        reason: 'the account\'s queue is untouched',
      );
    },
  );
}
