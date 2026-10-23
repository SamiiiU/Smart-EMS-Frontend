import 'package:flutter/material.dart';

import '../../../core/shell/identity_resolver.dart';
import '../../../core/shell/nav_destination.dart';
import '../data/academy_repository.dart';
import 'academy_finance_screen.dart';
import 'academy_home_screen.dart';
import 'institution_profile_screen.dart';
import 'learner_academy_screen.dart';

/// Academy and institution-profile destinations for the CURRENT shell.
///
/// - Nothing Academy-related appears unless the server reported the ACADEMY
///   profile ([academyEnabled]); School/college navigation is unchanged.
/// - Institution profile: admin shell, institution-wide campus.manage only.
/// - Academy hub: admin shell with academy.manage; teacher shell (their own
///   batches); personal workspace gets "Courses" (own/linked learners).
///
/// These checks only shape navigation. Every request is authorised by the
/// server against the campus grant, instructor assignment or learner link.
List<NavDestination> academyDestinations({
  required AcademyRepository repository,
  required IdentityResult identity,
  required bool academyEnabled,
  required bool personal,
  required bool adminShell,
  required bool teacherShell,
  Future<void> Function()? onProfileChanged,

  /// The profile lookup failed: offer an explicit retry, show no Academy workflow.
  bool profileFailed = false,
  bool profileLoading = false,
}) {
  final known = identity.permissionsKnown;
  final institutionWide = {
    for (final g in identity.grants.where((g) => g.campusId == null))
      ...g.permissions,
  };
  final fees = identity.can('fee.manage');
  final out = <NavDestination>[];
  if (adminShell && known && institutionWide.contains('campus.manage')) {
    out.add(
      NavDestination(
        id: 'institution_profile',
        group: 'Institution',
        label: 'Institution profile',
        icon: Icons.domain_outlined,
        route: '/institution-profile',
        builder: (_) => InstitutionProfileScreen(
          repository: repository,
          canChange: true,
          onChanged: onProfileChanged,
        ),
      ),
    );
  }
  if (profileFailed || profileLoading) {
    final retry = onProfileChanged;
    if (profileFailed && retry != null) {
      out.add(
        NavDestination(
          id: 'institution_status',
          group: adminShell ? 'Institution' : null,
          label: 'Institution status',
          icon: Icons.sync_problem_outlined,
          route: '/institution-status',
          builder: (_) =>
              ProfileUnavailableScreen(onRetry: retry, loading: profileLoading),
        ),
      );
    }
    return out;
  }
  if (!academyEnabled) return out;
  // Finance staff: read-only batch discovery, billing and collection (fee.manage).
  if (!personal && known && fees) {
    out.add(
      NavDestination(
        id: 'academy_fees',
        group: adminShell ? 'Institution' : null,
        label: 'Academy fees',
        icon: Icons.request_quote_outlined,
        route: '/academy-fees',
        builder: (_) => AcademyFinanceScreen(repository: repository),
      ),
    );
  }
  if (personal) {
    out.add(
      NavDestination(
        id: 'courses',
        label: 'Courses',
        icon: Icons.auto_stories_outlined,
        route: '/courses',
        builder: (_) => LearnerAcademyScreen(
          repository: repository,
          isStudent: identity.roles.contains('student'),
        ),
      ),
    );
  } else if ((adminShell && known && identity.can('academy.manage')) ||
      teacherShell) {
    out.add(
      NavDestination(
        id: 'academy',
        group: adminShell ? 'Institution' : null,
        label: 'Academy',
        icon: Icons.auto_stories_outlined,
        route: '/academy',
        builder: (_) =>
            AcademyHomeScreen(repository: repository, feesAvailable: fees),
      ),
    );
  }
  return out;
}

/// Inserts [extras] before "More" (or at the end), skipping ids already present.
List<NavDestination> withDestinations(
  List<NavDestination> base,
  List<NavDestination> extras,
) {
  final fresh = [
    for (final e in extras)
      if (!base.any((d) => d.id == e.id)) e,
  ];
  if (fresh.isEmpty) return base;
  final more = base.indexWhere((d) => d.id == 'more');
  return more < 0
      ? [...base, ...fresh]
      : [...base.sublist(0, more), ...fresh, ...base.sublist(more)];
}
