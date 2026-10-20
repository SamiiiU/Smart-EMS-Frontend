import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:drift/native.dart';
import 'package:smartems/features/attendance/data/secure_attendance_queue.dart';
import 'package:smartems/features/attendance/domain/attendance_models.dart';

// Synthetic, explicitly opted-in two-process persistence test. Never uses HTTP
// or the normal application's auth/storage namespace. Run write then read with
// the same nonce; force-stop between runs. Keep the namespace for audit on failure.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const nonce = String.fromEnvironment('ADR_VAULT_TEST_NONCE');
  const phase = String.fromEnvironment('ADR_VAULT_TEST_PHASE');
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,
      storageNamespace: 'ems_adr_vault_test',
    ),
  );
  testWidgets('real platform secure queue persists across process restart', (
    tester,
  ) async {
    expect(
      RegExp(r'^[a-f0-9]{12}$').hasMatch(nonce),
      true,
      reason: 'Explicit synthetic nonce required',
    );
    expect(['write', 'read'].contains(phase), true);
    String? owner = 'adr-tenant:$nonce';
    final db = NativeDatabase.memory();
    final queue = SecureAttendanceQueue(
      db,
      owner: () => owner,
      storage: storage,
    );
    if (phase == 'write') {
      expect(
        await queue.pendingCount(),
        0,
        reason: 'Fresh test owner required',
      );
      await queue.enqueue([
        const AttendanceMark(
          clientUuid: 'adr-operation-$nonce',
          sectionId: 'adr-section',
          studentId: 'adr-synthetic-student',
          attendanceDate: '2026-10-13',
          status: AttendanceStatus.present,
        ),
      ]);
    }
    expect((await queue.pending()).single.clientUuid, 'adr-operation-$nonce');
    owner = 'adr-other:$nonce';
    expect(await queue.pendingCount(), 0);
    owner = null;
    expect(await queue.pendingCount(), 0);
    owner = 'adr-tenant:$nonce';
    expect((await queue.pending()).single.studentId, 'adr-synthetic-student');
    if (phase == 'read') {
      await queue.remove(['adr-operation-$nonce']);
      expect(await queue.pendingCount(), 0);
    }
    await db.close();
  });
}
