import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/sizing.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/overline.dart';
import 'nav_destination.dart';

/// Persistent rail/sidebar for desktop widths. Shows the FULL destination
/// list (D-31's entitlement filter still applies — but not the
/// three-plus-More truncation [resolveBottomNavTabs] does for mobile; a
/// sidebar has the width to just show everything the user is entitled to).
///
/// [compact] switches between the navigation-rail form (600–1024px,
/// icons only) and the full labelled sidebar (>=1024px) — one component
/// covers both desktop chrome tiers, per the shared-destination-list rule.
///
/// Active state is a LEFT BORDER plus a surface change, never a fill — a
/// fill reads as a button; a border reads as position. This is the one
/// requirement this component exists to get right.
class DesktopSidebar extends StatelessWidget {
  const DesktopSidebar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
    this.compact = false,
    this.header,
    this.footer,
    super.key,
  });

  final List<NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool compact;

  /// Logo/institution slot at the top.
  final Widget? header;

  /// User block pinned to the bottom.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Semantics(
      container: true,
      child: Container(
        width: compact
            ? AppSizing.sidebarCompactWidth
            : AppSizing.sidebarWidth,
        decoration: BoxDecoration(
          color: t.surface,
          border: Border(right: BorderSide(color: t.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header != null)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.space5),
                child: header,
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.space3,
                ),
                children: [
                  for (var i = 0; i < destinations.length; i++) ...[
                    // A heading whenever the group changes. Grouping by
                    // FIRST APPEARANCE rather than sorting keeps `i` the
                    // caller's own index, so selection cannot drift.
                    //
                    // Suppressed in the compact rail: 72px has no room for
                    // a label, and a heading with no text is just a gap.
                    if (!compact && startsGroup(destinations, i))
                      _GroupHeading(label: destinations[i].group!),
                    _SidebarItem(
                      destination: destinations[i],
                      selected: i == selectedIndex,
                      compact: compact,
                      onTap: () => onSelect(i),
                    ),
                  ],
                ],
              ),
            ),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.space4),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

/// Whether [i] is the first destination of a new group.
///
/// Shared by the sidebar and the phone drawer so the two cannot disagree
/// about where a heading belongs.
///
/// Compares against the PREVIOUS entry rather than tracking seen names, so a
/// group that legitimately appears twice gets its heading both times instead
/// of the second run silently losing it.
bool startsGroup(List<NavDestination> destinations, int i) {
  final group = destinations[i].group;
  if (group == null) return false;
  if (i == 0) return true;
  return destinations[i - 1].group != group;
}

/// A group label. Uses [Overline], which already owns this job everywhere
/// else in the product — uppercased by the widget, and passed to Semantics
/// in its natural case so a screen reader does not spell it out.
class _GroupHeading extends StatelessWidget {
  const _GroupHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.space6,
          AppSpacing.space5,
          AppSpacing.space6,
          AppSpacing.space2,
        ),
        child: Overline(label),
      );
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final NavDestination destination;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    // Border + surface change, never a fill (class doc). primarySubtle is a
    // light tint, not an opaque fill — reads as "this row is current", not
    // as a pressed button.
    //
    // Label colour is textPrimary, NOT primaryTextOnSurface: D-36 confines
    // primaryTextOnSurface to `surface`/`page`, and `primarySubtle` is
    // neither — in dark mode that pairing measures 3.88:1, below the 4.5:1
    // floor (caught by contrast_test.dart, not by eye). textPrimary clears
    // both modes comfortably (12.0:1 dark / 15.6:1 light).
    final bg = selected ? t.primarySubtle : SmartEmsTokens.transparent;
    final fg = selected ? t.textPrimary : t.textSecondary;
    final borderColour =
        selected ? t.primaryAccent : SmartEmsTokens.transparent;

    final row = Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space3,
        vertical: AppSpacing.space1,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border(
          left: BorderSide(
            color: borderColour,
            width: AppSizing.sidebarActiveBorderWidth,
          ),
        ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.space3 : AppSpacing.space4,
        vertical: AppSpacing.space4,
      ),
      child: compact
          ? Center(
              child: Icon(destination.icon, color: fg, size: AppSpacing.space7),
            )
          : Row(
              children: [
                Icon(destination.icon, color: fg, size: AppSpacing.space7),
                const SizedBox(width: AppSpacing.space4),
                Expanded(
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.personName.copyWith(color: fg),
                  ),
                ),
              ],
            ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        // ExcludeSemantics on the visual row: the Semantics above already
        // supplies the label, so a screen reader is not shown the icon and
        // the text as two separate un-labelled nodes.
        child: ExcludeSemantics(child: row),
      ),
    );
  }
}
