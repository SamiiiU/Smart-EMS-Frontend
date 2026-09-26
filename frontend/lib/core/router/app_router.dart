import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/change_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../network/connectivity_sync_status_source.dart';
import '../shell/app_shell.dart';
import '../shell/identity_resolver.dart';
import '../shell/nav_destination.dart';
import '../shell/role_destinations.dart';
import '../shell/sync_status.dart';
import '../theme/sizing.dart';
import '../widgets/states/loading_skeleton.dart';
import 'auth_state.dart';

abstract final class AppRoutes {
  static const String splash = '/splash';
  static const String login = '/login';
  static const String changePassword = '/change-password';
  static const String home = '/';
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
  )? attendanceDestinations,
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
  /// Queue-backed sync status, so `SyncIndicator` reports the real pending
  /// count. Falls back to connectivity-only when absent.
  SyncStatusSource? syncStatusSource,
}) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    // Every change to auth state re-runs `redirect`, so signing in or out
    // moves the user without any screen calling go() itself.
    refreshListenable: authState,
    redirect: (context, state) {
      final location = state.matchedLocation;

      if (!authState.isRestored) {
        return location == AppRoutes.splash ? null : AppRoutes.splash;
      }

      // Checked BEFORE `isSignedIn`, deliberately. A forced change happens
      // straight after login: the tokens are stored and valid, but identity
      // was never resolved (there is no point loading a dashboard the user
      // cannot reach). `isSignedIn` is therefore false, and testing it
      // first would bounce the user back to login and make this gate
      // unreachable.
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
          location == AppRoutes.changePassword) {
        return AppRoutes.home;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) =>
            const Scaffold(body: LoadingSkeleton.cards(count: 3)),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => LoginScreen(
          repository: repository,
          // No navigation here — publishing identity flips `isSignedIn`,
          // and the redirect above does the rest.
          onSignedIn: authState.refreshIdentity,
          onForcePasswordChange: () =>
              authState.mustChangePassword = true,
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
        builder: (context, state) {
          final identity =
              authState.identity ?? const IdentityResult(IdentityResultKind.linked);

          Future<void> signOut() async {
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
          final destinations = switch (identity.roles) {
            // Student first, exactly as `forRoles` orders it (T11). Before
            // this branch a student fell through to the TEACHER list.
            final roles when roles.contains('student') =>
              studentDestinations?.call(signOut) ??
                  RoleDestinations.forRoles(roles),
            final roles when roles.contains('parent') =>
              parentDestinations?.call(signOut) ??
                  RoleDestinations.forRoles(roles),
            final roles when RoleDestinations.isAdminShell(roles) =>
              adminDestinations?.call(signOut) ??
                  RoleDestinations.forRoles(roles),
            final roles =>
              attendanceDestinations?.call(
                    signOut,
                    identity.staffId,
                    identity.staffName,
                  ) ??
                  RoleDestinations.forRoles(roles),
          };

          return AppShell(
            // D-27 amendment (T16): admin alone gets a drawer on a phone.
            // Nine destinations turned More into a second nav surface,
            // which is what D-27 exists to prevent. The other three roles
            // are unchanged.
            usePhoneDrawer: RoleDestinations.isAdminShell(identity.roles),
            // The institution's real display name from /api/institution/me,
            // falling back to the code until it loads (T5 cosmetic gap closed).
            institutionName: authState.institutionLabel,
            destinations: destinations,
            entitledIds: RoleDestinations.allIdsFor(destinations),
            // Already resolved by AuthState — passing it in avoids making
            // the same /auth/me call twice on every launch.
            identityResolver: StaticIdentityResolver(identity),
            // Queue-backed when attendance is wired, so the indicator shows
            // the REAL pending count (T6's stub is gone); connectivity-only
            // otherwise.
            syncStatusSource: syncStatusSource ?? ConnectivitySyncStatusSource(),
            // Desktop keeps sign-out in the sidebar; mobile gets it from the
            // More tab, which is the gap T8 closed.
            sidebarFooter: _SignOutButton(onSignOut: signOut),
            onSignOut: signOut,
          );
        },
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
