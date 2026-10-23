import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/token_store.dart';
import 'package:smartems/core/router/auth_state.dart';
import 'package:smartems/core/shell/identity_resolver.dart';
import 'package:smartems/core/shell/sync_status.dart';
import 'package:smartems/features/attendance/data/attendance_queue.dart';
import 'package:smartems/features/attendance/data/queue_sync_status_source.dart';
import 'package:smartems/features/attendance/domain/attendance_models.dart';

/// Found on a physical Pixel 7 Pro (F11/F12).
class _Resolver implements IdentityResolver {
  _Resolver(this.results);
  final List<IdentityResult> results;
  @override
  Future<IdentityResult> resolveIdentity() async => results.removeAt(0);
}

const _linked = IdentityResult(
  IdentityResultKind.linked,
  roles: ['teacher'],
  userId: 'u',
  tenantId: 't',
);

AttendanceMark _mark(String id) => AttendanceMark(
  clientUuid: id,
  sectionId: 's',
  studentId: 'st-$id',
  attendanceDate: '2026-10-13',
  status: AttendanceStatus.absent,
);

void main() {
  group('F12 cold start while the server is unreachable', () {
    test(
      'is an offline gate, not a sign-out, and credentials are kept',
      () async {
        final store = InMemoryTokenStore(accessToken: 'a', refreshToken: 'r');
        final auth = AuthState(
          tokenStore: store,
          identityResolver: _Resolver([
            const IdentityResult(
              IdentityResultKind.error,
              temporary: true,
              message: 'Could not reach the server.',
            ),
            _linked,
          ]),
        );
        await auth.restore();
        expect(auth.isRestored, isTrue);
        expect(auth.offlineRestore, isTrue);
        expect(auth.isSignedIn, isFalse);
        expect(store.refreshToken, 'r');
        expect(store.accessToken, 'a');
        // Connection returns: Retry resumes the same session.
        await auth.retryRestore();
        expect(auth.offlineRestore, isFalse);
        expect(auth.isSignedIn, isTrue);
      },
    );

    test('a definitive failure (dead session) still signs out', () async {
      final auth = AuthState(
        tokenStore: InMemoryTokenStore(accessToken: 'a', refreshToken: 'r'),
        identityResolver: _Resolver([
          const IdentityResult(
            IdentityResultKind.error,
            message: 'Access token missing or invalid',
          ),
        ]),
      );
      await auth.restore();
      expect(auth.offlineRestore, isFalse);
      expect(auth.isSignedIn, isFalse);
    });

    test(
      'a temporary failure mid-session keeps the signed-in identity',
      () async {
        final auth = AuthState(
          tokenStore: InMemoryTokenStore(accessToken: 'a', refreshToken: 'r'),
          identityResolver: _Resolver([
            _linked,
            const IdentityResult(IdentityResultKind.error, temporary: true),
          ]),
        );
        await auth.restore();
        expect(auth.isSignedIn, isTrue);
        await auth.refreshIdentity();
        expect(auth.isSignedIn, isTrue, reason: 'an outage is not a sign-out');
        expect(auth.offlineRestore, isFalse);
      },
    );
  });

  group('F11 sync badge follows the real queue', () {
    test(
      'enqueue and drain update the badge without any manual refresh',
      () async {
        final queue = AttendanceQueue(NativeDatabase.memory());
        final source = QueueSyncStatusSource(
          connectivity: const StaticSyncStatusSource(),
          queue: queue,
        );
        final seen = <SyncState>[];
        source.statusStream.listen((s) => seen.add(s.state));
        await Future<void>.delayed(Duration.zero);
        await queue.enqueue([_mark('1'), _mark('2')]);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          source.current.state,
          SyncState.syncing,
          reason: 'pending marks must never show as synced',
        );
        await queue.remove(['1', '2']);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(source.current.state, SyncState.synced);
        expect(seen, containsAllInOrder([SyncState.syncing, SyncState.synced]));
        source.dispose();
      },
    );
  });
}
