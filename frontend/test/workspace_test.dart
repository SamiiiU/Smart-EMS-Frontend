import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/token_store.dart';
import 'package:smartems/core/router/auth_state.dart';
import 'package:smartems/core/shell/identity_resolver.dart';
import 'package:smartems/core/shell/nav_destination.dart';
import 'package:smartems/core/shell/role_destinations.dart';

class _Resolver implements IdentityResolver {
  _Resolver(this.result);
  IdentityResult result;
  int calls = 0;
  @override
  Future<IdentityResult> resolveIdentity() async {
    calls++;
    return result;
  }
}

Future<AuthState> _signedIn(_Resolver resolver) async {
  final store = InMemoryTokenStore();
  await store.writeTokens(accessToken: 'a', refreshToken: 'r');
  final auth = AuthState(tokenStore: store, identityResolver: resolver);
  await auth.restore();
  return auth;
}

void main() {
  group('ADR-011 role → workspace', () {
    test('unknown or empty roles never get the admin shell', () {
      expect(RoleDestinations.forRoles(const []), same(RoleDestinations.none));
      expect(
        RoleDestinations.forRoles(const ['librarian']),
        same(RoleDestinations.none),
      );
      expect(RoleDestinations.isAdminShell(const ['librarian']), isFalse);
    });

    test('department roles map to their own shells', () {
      expect(
        RoleDestinations.forRoles(const ['attendance_staff']),
        same(RoleDestinations.teacher),
      );
      expect(
        RoleDestinations.forRoles(const ['finance_staff']),
        same(RoleDestinations.admin),
      );
      expect(
        RoleDestinations.forRoles(const ['campus_admin']),
        same(RoleDestinations.admin),
      );
    });

    test('admin navigation is filtered by current permissions', () {
      final finance = RoleDestinations.visibleFor(
        [
          for (final id in [
            'dashboard',
            'students',
            'fees',
            'people',
            'attendance_reviews',
            'more',
          ])
            NavDestination(
              id: id,
              label: id,
              icon: Icons.circle,
              route: '/',
              builder: (_) => const SizedBox(),
            ),
        ],
        {'fee.view', 'fee.manage'},
      ).map((d) => d.id);
      // Dashboard reads learner counts (student.view/report.view); fee.view alone used to unlock it and showed a permission error (overhaul crawl finding).
      expect(finance, ['fees', 'more']);
    });

    test('a teacher who is also a parent can reach both workspaces', () async {
      final resolver = _Resolver(
        const IdentityResult(
          IdentityResultKind.linked,
          roles: ['teacher', 'parent'],
        ),
      );
      final auth = await _signedIn(resolver);
      expect(auth.canSwitchWorkspace, isTrue);
      expect(auth.workspace, Workspace.school, reason: 'school is the default');
      final before = resolver.calls;
      await auth.switchWorkspace(Workspace.personal);
      expect(auth.workspace, Workspace.personal);
      expect(
        resolver.calls,
        before + 1,
        reason: 'switching refreshes capabilities',
      );
      auth.clear();
      expect(auth.workspace, Workspace.school);
    });

    test('a revoked role on refresh removes the stale workspace', () async {
      final resolver = _Resolver(
        const IdentityResult(
          IdentityResultKind.linked,
          roles: ['teacher', 'parent'],
        ),
      );
      final auth = await _signedIn(resolver);
      await auth.switchWorkspace(Workspace.personal);
      resolver.result = const IdentityResult(
        IdentityResultKind.linked,
        roles: ['teacher'],
      );
      await auth.refreshIdentity();
      expect(auth.canSwitchWorkspace, isFalse);
      expect(auth.workspace, Workspace.school);
    });

    test('grant scopes are never cross-combined', () {
      const identity = IdentityResult(
        IdentityResultKind.linked,
        grants: [
          GrantScope(
            role: 'finance_staff',
            campusId: 'A',
            permissions: ['fee.manage'],
          ),
          GrantScope(
            role: 'attendance_staff',
            campusId: 'B',
            permissions: ['attendance.mark'],
          ),
        ],
      );
      expect(identity.campusesFor('fee.manage'), {'A'});
      expect(identity.campusesFor('attendance.mark'), {'B'});
      const owner = IdentityResult(
        IdentityResultKind.linked,
        grants: [
          GrantScope(
            role: 'owner',
            campusId: null,
            permissions: ['fee.manage'],
          ),
        ],
      );
      expect(
        owner.campusesFor('fee.manage'),
        isNull,
        reason: 'institution-wide',
      );
    });
  });
}
