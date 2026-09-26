import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/sizing.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'nav_destination.dart';

/// Renders WHATEVER LIST IT IS GIVEN.
///
/// "Exactly four, fourth always More" (D-27) is a property of the data
/// `destinations` was built from — [resolveBottomNavTabs] — not a rule
/// encoded here. This widget lays out however many entries it receives, so
/// it cannot silently drift out of sync with the resolver by being edited
/// independently: change the resolver, and this widget just reflects it.
class BottomNav extends StatelessWidget {
  const BottomNav({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
    super.key,
  });

  final List<NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Semantics(
      container: true,
      child: Container(
        height: AppSizing.bottomNavHeight,
        decoration: BoxDecoration(
          color: t.surface,
          border: Border(top: BorderSide(color: t.border)),
        ),
        child: Row(
          children: [
            for (var i = 0; i < destinations.length; i++)
              Expanded(
                child: _BottomNavTab(
                  destination: destinations[i],
                  selected: i == selectedIndex,
                  onTap: () => onSelect(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavTab extends StatelessWidget {
  const _BottomNavTab({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    // Text on a surface: D-32/D-36 route this through primaryTextOnSurface,
    // never primaryAction directly, exactly as AppButton's secondary/ghost
    // labels do. The indicator bar is non-text, so it uses primaryAccent —
    // the same combination already verified for the Tabs primitive (T3).
    final labelColour = selected ? t.primaryTextOnSurface : t.textSecondary;
    final iconColour = selected ? t.primaryTextOnSurface : t.textSecondary;

    return Semantics(
      button: true,
      selected: selected,
      // The label IS the semantic label — the icon beside it is decorative
      // and excluded below, so a screen reader announces "Attendance",
      // never "Attendance, icon" or the icon's own description.
      label: destination.label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Top indicator bar rather than a fill — consistent with the
            // "border/line, not fill" idiom used for active state everywhere
            // else in the shell (DesktopSidebar's left border).
            Container(
              height: AppSizing.tabIndicatorHeight,
              width: AppSpacing.space9,
              color: selected
                  ? t.primaryAccent
                  : SmartEmsTokens.transparent,
            ),
            const SizedBox(height: AppSpacing.space2),
            ExcludeSemantics(
              child: Icon(
                destination.icon,
                color: iconColour,
                size: AppSpacing.space7,
              ),
            ),
            const SizedBox(height: AppSpacing.space1),
            ExcludeSemantics(
              child: Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(color: labelColour),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
