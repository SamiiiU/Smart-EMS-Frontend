import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/token_store.dart';
import 'package:smartems/core/router/app_router.dart';
import 'package:smartems/core/router/auth_state.dart';
import 'package:smartems/core/shell/identity_resolver.dart';
import 'package:smartems/core/shell/nav_destination.dart';
import 'package:smartems/core/shell/sync_status.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/features/auth/data/auth_repository.dart';

/// Hard-QA BUG-QA-21: a role restored mid-session must take effect on
/// "Check again" without an app restart. Drives the REAL router.
class _MutableResolver implements IdentityResolver {
  IdentityResult result;
  int calls = 0;
  _MutableResolver(this.result);

  @override
  Future<IdentityResult> resolveIdentity() async {
    calls++;
    return result;
  }
}

const _noRole = IdentityResult(
  IdentityResultKind.linked,
  roles: [],
  userId: 'u',
  tenantId: 't',
  permissions: [],
  permissionsKnown: true,
);
const _finance = IdentityResult(
  IdentityResultKind.linked,
  roles: ['finance_staff'],
  userId: 'u',
  tenantId: 't',
  permissions: ['fee.view', 'fee.manage'],
  grants: [
    GrantScope(
      role: 'finance_staff',
      campusId: 'B',
      permissions: ['fee.view', 'fee.manage'],
    ),
  ],
  permissionsKnown: true,
);

NavDestination _d(String id, String label) => NavDestination(
  id: id,
  label: label,
  icon: Icons.circle,
  route: '/$id',
  builder: (_) => Center(child: Text('$label screen')),
);

Future<(AuthState, _MutableResolver)> _app(
  WidgetTester tester,
  IdentityResult first,
) async {
  final store = InMemoryTokenStore(
    accessToken: 'a',
    refreshToken: 'r',
    institutionCode: 'north',
  );
  final resolver = _MutableResolver(first);
  final auth = AuthState(tokenStore: store, identityResolver: resolver);
  final router = buildRouter(
    authState: auth,
    repository: AuthRepository(dio: Dio(), tokenStore: store),
    adminDestinations: (_) => [
      _d('dashboard', 'Dashboard'),
      _d('fees', 'Fees'),
      _d('more', 'More'),
    ],
    syncStatusSource: const StaticSyncStatusSource(),
  );
  await tester.pumpWidget(
    MaterialApp.router(
      theme: AppTheme.light(role: AppRole.admin),
      routerConfig: router,
    ),
  );
  await auth.restore();
  await tester.pumpAndSettle();
  return (auth, resolver);
}

void main() {
  testWidgets(
    'no role → No access; Check again with still no role stays there',
    (tester) async {
      final (_, resolver) = await _app(tester, _noRole);
      expect(find.text('Your account has no access here yet'), findsOneWidget);
      final before = resolver.calls;
      await tester.tap(find.byKey(const Key('no-access-check')));
      await tester.pumpAndSettle();
      expect(resolver.calls, before + 1, reason: 'Check again asks the server');
      expect(find.text('Your account has no access here yet'), findsOneWidget);
    },
  );

  testWidgets(
    'role restored → Check again shows the authorized workspace, no restart',
    (tester) async {
      final (_, resolver) = await _app(tester, _noRole);
      expect(find.text('Your account has no access here yet'), findsOneWidget);
      resolver.result = _finance;
      await tester.tap(find.byKey(const Key('no-access-check')));
      await tester.pumpAndSettle();
      expect(find.text('Your account has no access here yet'), findsNothing);
      expect(
        find.text('Fees screen'),
        findsOneWidget,
        reason: 'lands on the first authorized destination',
      );
      expect(
        find.text('Dashboard screen'),
        findsNothing,
        reason: 'fee.* alone does not unlock the dashboard',
      );
    },
  );

  testWidgets('repeated taps do not loop or stack screens', (tester) async {
    final (_, resolver) = await _app(tester, _noRole);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('no-access-check')));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('Your account has no access here yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(resolver.calls, lessThanOrEqualTo(5));
  });

  testWidgets(
    'server unavailable (503) keeps the session and the screen; it is not a sign-out',
    (tester) async {
      final (auth, resolver) = await _app(tester, _noRole);
      resolver.result = const IdentityResult(
        IdentityResultKind.error,
        message: 'down',
        temporary: true,
      );
      await tester.tap(find.byKey(const Key('no-access-check')));
      await tester.pumpAndSettle();
      expect(
        auth.isSignedIn,
        isTrue,
        reason: 'a temporary outage never signs the user out',
      );
      expect(find.text('Your account has no access here yet'), findsOneWidget);
    },
  );

  testWidgets('revoked session → sign-in, no cached permissions kept', (
    tester,
  ) async {
    final (auth, resolver) = await _app(tester, _noRole);
    resolver.result = const IdentityResult(
      IdentityResultKind.error,
      message: 'expired',
    );
    await tester.tap(find.byKey(const Key('no-access-check')));
    await tester.pumpAndSettle();
    expect(auth.isSignedIn, isFalse);
    expect(auth.identity, isNull);
    expect(find.text('Your account has no access here yet'), findsNothing);
  });
}
