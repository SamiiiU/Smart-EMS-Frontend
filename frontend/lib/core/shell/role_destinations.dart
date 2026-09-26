import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/typography.dart';
import 'nav_destination.dart';

/// Per-role ordered destination lists (D-31).
///
/// These are DATA, not widgets — the four roles supply different-length,
/// differently-ranked lists, and [BottomNav]/[DesktopSidebar] render
/// whatever they are given. Nothing role-specific lives in the shell
/// components themselves.
///
/// Placeholder builders only: no product screens exist before T7+. Each
/// destination's `builder` renders its own name so the gallery and tests can
/// tell tabs apart without depending on real screens.
abstract final class RoleDestinations {
  static Widget _placeholder(String label) {
    return Builder(
      builder: (context) {
        final t = context.tokens;
        return Center(
          child: Text(
            '$label — built in a later task',
            style: AppTypography.bodyAdminMeta.copyWith(
              color: t.textSecondary,
            ),
          ),
        );
      },
    );
  }

  static NavDestination _d(String id, String label, IconData icon) {
    return NavDestination(
      id: id,
      label: label,
      icon: icon,
      route: '/$id',
      builder: (_) => _placeholder(label),
    );
  }

  /// D-31's own worked example: My child · Attendance · Fees · Complaints ·
  /// Messages · Profile · Settings. With Finance entitled, the tabs are
  /// My child / Attendance / Fees / More. Without it, Fees drops and
  /// Complaints promotes into the third slot — no code change, only a
  /// smaller `entitledIds` set.
  static final List<NavDestination> parent = [
    _d('my_child', 'My child', Icons.child_care_outlined),
    _d('attendance', 'Attendance', Icons.event_available_outlined),
    _d('fees', 'Fees', Icons.payments_outlined),
    _d('complaints', 'Complaints', Icons.report_problem_outlined),
    _d('messages', 'Messages', Icons.mail_outline),
    _d('profile', 'Profile', Icons.person_outline),
    _d('settings', 'Settings', Icons.settings_outlined),
  ];

  /// D-27's example: Today, Attendance and Diary are daily tasks — they earn
  /// tab slots. Classes is a navigation HUB to periodic work, not a task, so
  /// it is ranked below the daily three and lands in More by default.
  static final List<NavDestination> teacher = [
    _d('today', 'Today', Icons.today_outlined),
    _d('attendance', 'Attendance', Icons.fact_check_outlined),
    _d('diary', 'Diary', Icons.menu_book_outlined),
    _d('classes', 'Classes', Icons.class_outlined),
    _d('profile', 'Profile', Icons.person_outline),
    _d('settings', 'Settings', Icons.settings_outlined),
  ];

  static final List<NavDestination> student = [
    _d('today', 'Today', Icons.today_outlined),
    _d('attendance', 'Attendance', Icons.event_available_outlined),
    _d('timetable', 'Timetable', Icons.schedule_outlined),
    _d('results', 'Results', Icons.grade_outlined),
    _d('profile', 'Profile', Icons.person_outline),
    _d('settings', 'Settings', Icons.settings_outlined),
  ];

  /// Admin runs dense on desktop (D-12) but the destination list itself is
  /// role data, not a density decision — the same list still needs a mobile
  /// truncation for an admin checking the app on a phone.
  static final List<NavDestination> admin = [
    _d('dashboard', 'Dashboard', Icons.dashboard_outlined),
    _d('students', 'Students', Icons.groups_outlined),
    _d('staff', 'Staff', Icons.badge_outlined),
    _d('fees', 'Fees', Icons.payments_outlined),
    _d('reports', 'Reports', Icons.bar_chart_outlined),
    _d('settings', 'Settings', Icons.settings_outlined),
  ];

  /// Every module id currently declared by any role — the "entitled by
  /// default" set T5 uses in the absence of a real entitlement endpoint.
  static Set<String> allIdsFor(List<NavDestination> destinations) =>
      destinations.map((d) => d.id).toSet();

  /// Maps the JWT's `roles` claim (D-41) onto one of the four shells.
  ///
  /// The token's role vocabulary is wider than the four shells: `staff` maps
  /// to the teacher shell, and `owner` / `super_admin` to the admin shell —
  /// they are seniority variants of the same job, not different navigation.
  /// Checked most-specific first, so a user holding several roles gets the
  /// most task-oriented shell rather than whichever happened to come first
  /// in the array.
  static List<NavDestination> forRoles(Iterable<String> roles) {
    if (roles.contains('student')) return student;
    if (roles.contains('teacher') || roles.contains('staff')) return teacher;
    if (roles.contains('parent')) return parent;
    return admin;
  }

  /// Whether [forRoles] would pick the admin shell.
  ///
  /// Exists so the router can wire the admin's live screens (T10) using this
  /// mapping's own decision instead of re-deriving it. Two copies of the
  /// precedence rule would drift, and the drift would be silent: a user
  /// would simply get the wrong shell.
  static bool isAdminShell(Iterable<String> roles) =>
      identical(forRoles(roles), admin);
}
