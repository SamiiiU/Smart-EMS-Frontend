import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:smartems/features/attendance/data/attendance_queue.dart';
import 'package:smartems/features/attendance/data/secure_attendance_queue.dart';
import 'package:smartems/features/attendance/domain/attendance_models.dart';
import 'package:smartems/core/network/auth_interceptor.dart';
import 'package:smartems/core/network/token_store.dart';

class NoRefresh implements TokenRefresher {
  @override
  Future<String?> refresh(String token) async => null;
}

AttendanceMark mark(
  String id, {
  AttendanceStatus status = AttendanceStatus.present,
}) => AttendanceMark(
  clientUuid: id,
  sectionId: 'section',
  studentId: 'student',
  attendanceDate: '2026-10-13',
  status: status,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'account switch while a write is queued cannot adopt the operation',
    () async {
      String? owner = 'tenant:a';
      final q = SecureAttendanceQueue(
        NativeDatabase.memory(),
        owner: () => owner,
      );
      final write = q.enqueue([mark('original-account')]);
      owner = 'tenant:b';
      await expectLater(write, throwsStateError);
      expect(await q.pendingCount(), 0);
      owner = 'tenant:a';
      expect(await q.pendingCount(), 0);
    },
  );

  test(
    'stored ownership mismatch fails closed and retains the original value',
    () async {
      final key = [
        'attendance.v2.',
        base64Url.encode(utf8.encode('tenant:a')),
      ].join();
      final raw = jsonEncode({
        'version': 2,
        'owner': 'tenant:b',
        'marks': [],
        'conflicts': [],
      });
      FlutterSecureStorage.setMockInitialValues({key: raw});
      final q = SecureAttendanceQueue(
        NativeDatabase.memory(),
        owner: () => 'tenant:a',
      );
      await expectLater(q.pending(), throwsStateError);
      expect(await const FlutterSecureStorage().read(key: key), raw);
    },
  );

  test(
    'account switching isolates marks and returning restores original IDs',
    () async {
      String? owner = 'tenant:a';
      final q = SecureAttendanceQueue(
        NativeDatabase.memory(),
        owner: () => owner,
      );
      await q.enqueue([mark('a')]);
      owner = 'tenant:b';
      expect(await q.pendingCount(), 0);
      await q.enqueue([mark('b')]);
      owner = 'other-tenant:a';
      expect(await q.pendingCount(), 0);
      owner = null;
      expect(await q.pendingCount(), 0);
      await expectLater(q.enqueue([mark('no-owner')]), throwsStateError);
      owner = 'tenant:a';
      expect((await q.pending()).single.clientUuid, 'a');
      final reopened = SecureAttendanceQueue(
        NativeDatabase.memory(),
        owner: () => owner,
      );
      expect((await reopened.pending()).single.clientUuid, 'a');
    },
  );

  test(
    'parallel writes do not overwrite each other, replay cannot change intent',
    () async {
      final q = SecureAttendanceQueue(
        NativeDatabase.memory(),
        owner: () => 'tenant:a',
      );
      await Future.wait([
        q.enqueue([mark('one')]),
        q.enqueue([mark('two')]),
      ]);
      expect(await q.pendingCount(), 2);
      await q.enqueue([mark('one')]);
      expect(await q.pendingCount(), 2);
      await expectLater(
        q.enqueue([mark('one', status: AttendanceStatus.absent)]),
        throwsStateError,
      );
      expect((await q.pending()).first.status, AttendanceStatus.present);
    },
  );

  test(
    'unowned legacy marks are preserved but never adopted into a login',
    () async {
      final db = NativeDatabase.memory();
      final legacy = AttendanceQueue(db);
      await legacy.enqueue([mark('legacy')]);
      final secure = SecureAttendanceQueue(db, owner: () => 'tenant:a');
      expect(await secure.pendingCount(), 0);
      expect((await legacy.pending()).single.clientUuid, 'legacy');
      await db.close();
    },
  );

  test(
    'signed-in token from another account cannot transmit queued data',
    () async {
      final claims = base64Url.encode(
        utf8.encode(jsonEncode({'tid': 'tenant', 'sub': 'b'})),
      );
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
      dio.interceptors.add(
        AuthInterceptor(
          tokenStore: InMemoryTokenStore(accessToken: 'x.$claims.x'),
          refresher: NoRefresh(),
          retryDio: Dio(),
        ),
      );
      await expectLater(
        dio.post(
          '/api/attendance/bulk',
          options: Options(extra: {'attendanceOwner': 'tenant:a'}),
        ),
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );
      dio.close();
    },
  );
}
