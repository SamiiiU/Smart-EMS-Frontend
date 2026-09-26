import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/token_store.dart';
import 'package:smartems/core/router/auth_state.dart';
import 'package:smartems/core/shell/identity_resolver.dart';

class _FakeResolver implements IdentityResolver {
  _FakeResolver(this.result);

  final IdentityResult result;
  int calls = 0;

  @override
  Future<IdentityResult> resolveIdentity() async {
    calls++;
    return result;
  }
}

const _linkedAdmin = IdentityResult(
  IdentityResultKind.linked,
  roles: ['admin'],
  userId: 'u-1',
  tenantId: 't-1',
);

void main() {
  group('AuthState.restore', () {
    test('no stored token: restored, signed out, and the network is never '
        'touched', () async {
      final resolver = _FakeResolver(_linkedAdmin);
      final auth = AuthState(
        tokenStore: InMemoryTokenStore(),
        identityResolver: resolver,
      );

      await auth.restore();

      expect(auth.isRestored, isTrue);
      expect(auth.isSignedIn, isFalse);
      expect(
        resolver.calls,
        0,
        reason: 'resolving identity without a token would be a guaranteed '
            '401 on every cold start',
      );
    });

    test('stored token: resolves identity and publishes roles + institution '
        'code', () async {
      final auth = AuthState(
        tokenStore: InMemoryTokenStore(
          accessToken: 'a',
          refreshToken: 'r',
          institutionCode: 'test-school',
        ),
        identityResolver: _FakeResolver(_linkedAdmin),
      );

      await auth.restore();

      expect(auth.isSignedIn, isTrue);
      expect(auth.identity!.roles, ['admin']);
      expect(auth.institutionCode, 'test-school');
    });

    test('a dead session (error) is treated as signed out', () async {
      final auth = AuthState(
        tokenStore: InMemoryTokenStore(accessToken: 'stale'),
        identityResolver: _FakeResolver(
          const IdentityResult(IdentityResultKind.error, message: 'expired'),
        ),
      );

      await auth.restore();

      expect(auth.isRestored, isTrue);
      expect(auth.isSignedIn, isFalse);
    });

    test('notLinked stays SIGNED IN — it is a real user whose person record '
        'is missing, and the shell owns that state', () async {
      // The distinction that matters: an orphaned profile must reach the
      // shell to be shown UnlinkedProfileState (D-17). Bouncing them to the
      // login screen would trap them in a loop they cannot escape, since
      // their credentials are perfectly valid.
      final auth = AuthState(
        tokenStore: InMemoryTokenStore(accessToken: 'a'),
        identityResolver: _FakeResolver(
          const IdentityResult(
            IdentityResultKind.notLinked,
            roles: ['teacher'],
          ),
        ),
      );

      await auth.restore();

      expect(auth.isSignedIn, isTrue);
      expect(auth.identity!.kind, IdentityResultKind.notLinked);
    });
  });

  group('AuthState notifies listeners', () {
    test('restore and clear both notify, so the router re-evaluates its '
        'redirect', () async {
      var notifications = 0;
      final auth = AuthState(
        tokenStore: InMemoryTokenStore(accessToken: 'a'),
        identityResolver: _FakeResolver(_linkedAdmin),
      )..addListener(() => notifications++);

      await auth.restore();
      expect(notifications, greaterThan(0));
      expect(auth.isSignedIn, isTrue);

      final before = notifications;
      auth.clear();
      expect(auth.isSignedIn, isFalse);
      expect(
        notifications,
        greaterThan(before),
        reason: 'without this notification, signing out would leave the user '
            'sitting on the shell route',
      );
    });
  });
}
