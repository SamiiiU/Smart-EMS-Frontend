import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

/// One destination in a role's navigation.
///
/// [id] doubles as the entitlement-module key — D-31 says entitlement is
/// institution-level and filters this list, so the id is what a future
/// entitlement source will match against. No entitlement endpoint exists yet
/// (T5 scope), so callers pass the full set of ids as "entitled by default".
///
/// [builder] is a placeholder content builder. No product screens exist yet
/// (T7+), so the shell needs *something* to put in the IndexedStack; each
/// destination supplies its own placeholder rather than the shell inventing
/// one, so a later task only has to replace this field, not the shell.
@immutable
class NavDestination {
  const NavDestination({
    required this.id,
    required this.label,
    required this.icon,
    required this.route,
    required this.builder,
    this.alwaysVisible = false,
    this.group,
  });

  /// Optional heading this destination sits under in the DESKTOP SIDEBAR.
  ///
  /// Nine flat admin destinations is a wall. The groups mirror the hubs the
  /// product already has — Setup, Finance, Academics, Operations — so the
  /// nav and the screens describe the same shape rather than two.
  ///
  /// Null everywhere else, and a list with no groups renders exactly as it
  /// did before: teacher, parent and student have few enough destinations
  /// that headings would be noise.
  ///
  /// ⚠️ Purely presentational. It does NOT reorder anything — the sidebar
  /// groups by first appearance, so `selectedIndex` still indexes into the
  /// caller's own list and cannot drift out of step with it.
  final String? group;

  /// Stable identity. Also the entitlement-module key (D-31).
  final String id;

  final String label;
  final IconData icon;

  /// Intended route path. Not wired to go_router in T5 — routing integration
  /// is out of scope until T7 — but the field is part of the model now so it
  /// does not need retrofitting later.
  final String route;

  final WidgetBuilder builder;

  /// True for destinations that must never be filtered or demoted — "More"
  /// itself, and any core-task destination a role cannot function without.
  /// Ignored by entitlement filtering; NOT a way to opt out of the
  /// three-plus-More truncation on [resolveBottomNavTabs].
  final bool alwaysVisible;
}

/// Filters a role's ordered destination list by entitlement (D-31).
///
/// Order is preserved — this is what makes promotion automatic when an
/// entitlement is removed: the next-ranked item is simply the next survivor
/// of this filter, not something the caller has to recompute.
List<NavDestination> filterByEntitlement(
  List<NavDestination> declared,
  Set<String> entitledIds,
) {
  return declared
      .where((d) => d.alwaysVisible || entitledIds.contains(d.id))
      .toList(growable: false);
}

/// Synthesizes the "More" destination that absorbs whatever [resolveBottomNavTabs]
/// truncates. Not part of any role's declared list — it is built from the
/// overflow at resolve time, so its content always matches what is actually
/// hidden.
NavDestination buildMoreDestination(
  List<NavDestination> overflow, {
  required WidgetBuilder builder,
}) {
  return NavDestination(
    id: 'more',
    label: 'More',
    icon: Icons.more_horiz,
    route: '/more',
    alwaysVisible: true,
    builder: builder,
  );
}

/// Resolves the final <= 4 tabs [BottomNav] renders (D-27).
///
/// [eligible] is a role's destinations AFTER [filterByEntitlement] — this
/// function does not itself filter, so it has no entitlement knowledge and
/// cannot drift out of sync with it.
///
/// Behaviour, in full:
///  - `<= 3` eligible destinations: rendered as-is, no "More". A role with
///    fewer than four destinations is not padded to four (D-27: "fewer than
///    four destinations still renders correctly").
///  - `> 3` eligible destinations: the first three, plus a synthesized
///    "More" as the fourth, carrying everything from index 3 onward.
///
/// This is the ONLY place "four tabs" is encoded. [BottomNav] itself renders
/// whatever list it is given, at whatever length — the four-tab rule lives
/// in data flow, not in the widget.
List<NavDestination> resolveBottomNavTabs(
  List<NavDestination> eligible, {
  required WidgetBuilder moreBuilder,
}) {
  if (eligible.length <= 3) return eligible;
  final visible = eligible.take(3).toList(growable: false);
  final overflow = eligible.skip(3).toList(growable: false);
  return [
    ...visible,
    buildMoreDestination(overflow, builder: moreBuilder),
  ];
}
