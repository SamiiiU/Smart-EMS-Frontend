import '../../features/academy/data/academy_repository.dart';
import '../../features/academy/presentation/academy_navigation.dart';
import '../../features/attendance/data/attendance_queue.dart';
import '../../features/attendance/presentation/attendance_sign_out.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/data/remembered_institution.dart';
import '../../features/auth/presentation/change_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/mfa_screen.dart';
import '../network/connectivity_sync_status_source.dart';
import '../shell/app_shell.dart';
import '../shell/identity_resolver.dart';
import '../shell/nav_destination.dart';
import '../shell/no_access_screen.dart';
import '../shell/role_destinations.dart';
import '../shell/sync_status.dart';
import '../shell/workspace_scope.dart';
import '../theme/sizing.dart';
import '../widgets/states/loading_skeleton.dart';
import 'auth_state.dart';
import 'offline_restore_screen.dart';

abstract final class AppRoutes {
  static const String splash = '/splash';
  static const String login = '/login';
  static const String changePassword = '/change-password';
  static const String twoFactor = '/two-factor';
  static const String home = '/';
  static const String offline = '/offline';
}

/// Routing, replacing T7's `AuthGate` stopgap.
///
/// SCOPE: this wires the auth boundary — splash → login → shell — and route
/// guarding. It deliberately does NOT make the shell's tabs route-driven.
/// `AppShell` owns an `IndexedStack` so tab state survives switching (D-30),
/// and converting that to `StatefulShellRoute` is a change to T5's shell,
/// not to this task. Consequence to be aware of: tabs are not deep-linkable
/// and do not appear in browser history yet.
GoRouter buildRouter({
  required AuthState authState,
  required AuthRepository repository,
  AttendanceQueue? attendanceQueue,

  /// Supplies the live, screen-backed destination list. Takes the sign-out
  /// callback because the More tab owns sign-out (the mobile gap T8 closed),
  /// and the signed-in teacher's `staffId` (resolved by
  /// `NetworkIdentityResolver` from `GET /api/staff/me`, the SAME call it
  /// already made for the D-17 orphan check — this is not an extra round
  /// trip). Null falls back to the placeholder-only lists, which is what
  /// tests that do not care about attendance want.
  List<NavDestination> Function(
    Future<void> Function() onSignOut,
    String? staffId,
    String? staffName,
  )?
  attendanceDestinations,

  /// The parent role's live screens (T9). Same shape and the same
  /// null-means-placeholders rule as [attendanceDestinations].
  List<NavDestination> Function(Future<void> Function() onSignOut)?
  parentDestinations,

  /// The admin role's live screens (T10). Same shape and the same
  /// null-means-placeholders rule as [attendanceDestinations].
  List<NavDestination> Function(Future<void> Function() onSignOut)?
  adminDestinations,

  /// The student role's screens (T11). Same null-means-placeholders rule.
  List<NavDestination> Function(Future<void> Function() onSignOut)?
  studentDestinations,
  /// Academy (Phase B). Null in tests and builds without it: no Academy or
  /// institution-profile destinations are added.
  AcademyRepository? academy,

  /// Queue-backed sync status, so `SyncIndicator` reports the real pending
  /// count. Falls back to connectivity-only when absent.
  SyncStatusSource? syncStatusSource,
  RememberedInstitutionStore? rememberedInstitution,

  /// Lets app-wide prompts (finance step-up) open dialogs above any route.
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: AppRoutes.splash,
    // Every change to auth state re-runs `redirect`, so signing in or out
    // moves the user without any screen calling go() itself.
    refreshListenable: authState,
    redirect: (context, state) {
      final location = state.matchedLocation;

      if (!authState.isRestored) {
        return location == AppRoutes.splash ? null : AppRoutes.splash;
      }

      // F12: a stored session that could not reach the server is NOT a sign-out.
      if (authState.offlineRestore) {
        return location == AppRoutes.offline ? null : AppRoutes.offline;
      }
      if (location == AppRoutes.offline) {
        return authState.isSignedIn ? AppRoutes.home : AppRoutes.login;
      }

      // Checked BEFORE `isSignedIn`, deliberately. A forced change happens
      // straight after login: the tokens are stored and valid, but identity
      // was never resolved (there is no point loading a dashboard the user
      // cannot reach). `isSignedIn` is therefore false, and testing it
      // first would bounce the user back to login and make this gate
      // unreachable.
      // Two-factor comes first: until the server lifts the pre-MFA restriction,
      // even the password-change call would be refused with 403 MFA_REQUIRED.
      if (authState.mfaPending) {
        return location == AppRoutes.twoFactor ? null : AppRoutes.twoFactor;
      }

      if (authState.mustChangePassword) {
        return location == AppRoutes.changePassword
            ? null
            : AppRoutes.changePassword;
      }

      if (!authState.isSignedIn) {
        return location == AppRoutes.login ? null : AppRoutes.login;
      }

      // Signed in: splash, login and change-password are no longer reachable.
      if (location == AppRoutes.login ||
          location == AppRoutes.splash ||
          location == AppRoutes.changePassword ||
          location == AppRoutes.twoFactor) {
        return AppRoutes.home;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.offline,
        // ListenableBuilder: the wording follows the latest failure (busy vs
        // offline) while the screen, and its retry timer, stay mounted.
        builder: (context, state) => ListenableBuilder(
          listenable: authState,
          builder: (context, _) => OfflineRestoreScreen(
            onRetry: authState.retryRestore,
            serverBusy: authState.restoreServerBusy,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) =>
            const Scaffold(body: LoadingSkeleton.cards(count: 3)),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => LoginScreen(
          repository: repository,
          rememberedInstitution: rememberedInstitution,
          // No navigation here — publishing identity flips `isSignedIn`,
          // and the redirect above does the rest.
          onSignedIn: authState.completeSignIn,
          onForcePasswordChange: () {
            authState.mustChangePassword = true;
            authState.checkMfa();
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.twoFactor,
        builder: (context, state) => MfaScreen(
          // Non-null whenever mfaPending can be true: only a configured
          // repository ever reports a restricted session.
          repository: authState.mfa!,
          onVerified: authState.mfaVerified,
          onSignOut: () async {
            await repository.logout();
            authState.clear();
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.changePassword,
        builder: (context, state) => ChangePasswordScreen(
          repository: repository,
          // The change revoked every session, so there is nothing to
          // continue with: drop the identity and let the redirect land on
          // login. `clear()` also resets mustChangePassword.
          onChanged: authState.clear,
        ),
      ),
      GoRoute(
        path: AppRoutes.home,
        // BUG-QA-21 root cause: this page's destinations were computed in the
        // GoRoute builder, which go_router does not re-run when authState
        // notifies without a location change. A role restored mid-session
        // (No access -> Check again) therefore kept the stale "No access"
        // shell until an app restart. Listening here rebuilds the shell from
        // the CURRENT identity whenever authState changes.
        builder: (context, state) => ListenableBuilder(
          listenable: authState,
          builder: (context, _) {
          final identity =
              authState.identity ??
              const IdentityResult(IdentityResultKind.linked);

          Future<void> signOut() async {
            if (attendanceQueue != null &&
                !await confirmAttendanceSignOut(context, attendanceQueue)) {
              return;
            }
            await repository.logout();
            authState.clear();
          }

          // Role decides which real screens are wired.
          //
          // The ORDER here deliberately mirrors `RoleDestinations.forRoles`
          // (D-41): most task-oriented shell first. So a user holding both a
          // staff role and an admin role keeps the teacher shell, exactly as
          // the placeholder mapping already decided — this switch must not
          // quietly disagree with it. `isAdminShell` is that mapping's own
          // admin case, asked directly rather than re-guessed here.
          //
          // The placeholder data lists are used only when no live builder is
          // supplied, which is what tests that do not care about screens
          // want.
          // ADR-011: the active WORKSPACE decides first (one login, separate
          // school and personal authorization contexts), then the role. An
          // unknown role set gets no data screens — never the admin shell.
          final roles = identity.roles;
          final personal = authState.workspace == Workspace.personal;
          final adminShell = !personal &&
              !roles.any(RoleDestinations.teacherRoles.contains) &&
              roles.any(RoleDestinations.adminRoles.contains);
          final List<NavDestination> destinations;
          if (personal) {
            destinations = roles.contains('student')
                ? studentDestinations?.call(signOut) ?? RoleDestinations.student
                : parentDestinations?.call(signOut) ?? RoleDestinations.parent;
          } else if (roles.any(RoleDestinations.teacherRoles.contains)) {
            final teaching = attendanceDestinations?.call(
                  signOut,
                  identity.staffId,
                  identity.staffName,
                ) ??
                RoleDestinations.teacher;
            // BUG-QA-08: a teacher who ALSO holds finance on some campus
            // (e.g. Teacher@A + Finance@B) reaches the same Fees hub the admin
            // shell uses, inserted before More. The hub scopes itself to
            // campuses where this account holds fee.manage; the server
            // still authorizes every request per grant.
            final fees = identity.permissionsKnown &&
                    (identity.can('fee.view') || identity.can('fee.manage'))
                ? adminDestinations?.call(signOut).where((d) => d.id == 'fees').firstOrNull
                : null;
            destinations = fees == null || teaching.any((d) => d.id == 'fees')
                ? teaching
                : [
                    for (final d in teaching)
                      if (d.id == 'more') ...[fees, d] else d,
                    if (!teaching.any((d) => d.id == 'more')) fees,
                  ];
          } else if (adminShell) {
            final all = adminDestinations?.call(signOut) ?? RoleDestinations.admin;
            // Capability-driven: hide what current server permissions refuse.
            destinations = identity.permissionsKnown
                ? RoleDestinations.visibleFor(all, identity.permissions.toSet(),
                    institutionWide: identity.grants.isEmpty
                        ? null
                        : {for (final g in identity.grants.where((g) => g.campusId == null)) ...g.permissions})
                : all;
          } else {
            // BUG-QA-21: a real screen (explain, check again, sign out), not the
            // placeholder. Same id/label as RoleDestinations.none.
            destinations = [
              NavDestination(
                id: 'no_access',
                label: 'No access',
                icon: Icons.lock_outline,
                route: '/no_access',
                builder: (ctx) => NoAccessScreen(
                  onSignOut: signOut,
                  // Re-resolve from the server, then restart at the root so the
                  // router lands on the first destination the account now has
                  // (staying on /no_access would keep showing this screen).
                  // The home page listens to authState (see above), so a
                  // restored role rebuilds the shell with no navigation trick.
                  onCheckAgain: authState.refreshIdentity,
                ),
              ),
            ];
          }

          // Academy Phase B: added only for an ACADEMY-profile institution (plus the
          // institution-profile screen for institution-wide structure admins).
          final academyRepository = academy;
          final shellDestinations = academyRepository == null
              ? destinations
              : withDestinations(destinations, academyDestinations(
                  repository: academyRepository,
                  identity: identity,
                  academyEnabled: authState.academyEnabled,
                  personal: personal,
                  adminShell: adminShell,
                  teacherShell: !personal && roles.any(RoleDestinations.teacherRoles.contains),
                  onProfileChanged: authState.reloadInstitutionProfile,
                  profileFailed: authState.profileLookup == ProfileLookup.failed,
                  profileLoading: authState.profileLookup == ProfileLookup.loading,
                ));

          final shell = AppShell(
            key: ValueKey('shell:${authState.workspace.name}:${identity.roles.join(',')}:'
            'academy=${authState.academyEnabled}:${authState.profileLookup.name}:'
                '${identity.grants.map((g) => '${g.role}@${g.campusId}').join(',')}'),
            // D-27 amendment (T16): admin alone gets a drawer on a phone.
            // Nine destinations turned More into a second nav surface,
            // which is what D-27 exists to prevent. The other three roles
            // are unchanged.
            usePhoneDrawer: adminShell,
            // The institution's real display name from /api/institution/me,
            // falling back to the code until it loads (T5 cosmetic gap closed).
            institutionName: authState.institutionLabel,
            destinations: shellDestinations,
            entitledIds: RoleDestinations.allIdsFor(shellDestinations),
            // Already resolved by AuthState — passing it in avoids making
            // the same /auth/me call twice on every launch.
            identityResolver: StaticIdentityResolver(identity),
            // Queue-backed when attendance is wired, so the indicator shows
            // the REAL pending count (T6's stub is gone); connectivity-only
            // otherwise.
            syncStatusSource:
                syncStatusSource ?? ConnectivitySyncStatusSource(),
            // Desktop keeps sign-out in the sidebar; mobile gets it from the
            // More tab, which is the gap T8 closed.
            sidebarFooter: _SignOutButton(onSignOut: signOut),
            onSignOut: signOut,
          );
          if (!authState.canSwitchWorkspace) return shell;
          return WorkspaceScope(
            switchLabel: personal
                ? 'Switch to institution workspace'
                : 'Switch to personal workspace',
            onSwitch: () => authState.switchWorkspace(
              personal ? Workspace.school : Workspace.personal,
            ),
            child: shell,
          );
          },
        ),
      ),
    ],
  );
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.onSignOut});

  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    // The compact rail (600–1024px) is too narrow for icon + label: the
    // label wrapped one letter per line ("S/i/g/n/o/u/t"), found in manual
    // testing 2026-09-19. There, show the icon alone, labelled for screen
    // readers and hover via its tooltip.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= AppSizing.sidebarCompactWidth) {
          return IconButton(
            onPressed: onSignOut,
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_outlined),
          );
        }
        return TextButton.icon(
          onPressed: onSignOut,
          icon: const Icon(Icons.logout_outlined),
          label: const Text('Sign out'),
        );
      },
    );
  }
}
