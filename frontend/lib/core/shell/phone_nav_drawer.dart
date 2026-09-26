import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/sizing.dart';
import '../theme/typography.dart';
import '../widgets/overline.dart';
import 'desktop_sidebar.dart' show startsGroup;
import 'nav_destination.dart';

/// Phone navigation for a role with too many destinations for a bottom bar.
///
/// ## Why this exists — the D-27 amendment (T16)
///
/// D-27 truncates a phone to three destinations plus **More**, so the bar
/// cannot become a second navigation surface. That reasoning is sound and
/// still governs teacher, parent and student.
///
/// Admin outgrew it. With **nine** destinations, More held six — which is a
/// navigation menu wearing a tab's clothes, and exactly the thing D-27 was
/// written to prevent. A drawer is the honest shape for that many: one
/// surface, everything on it, nothing hidden behind a tab that is not one.
///
/// **Nothing is truncated here.** The drawer shows the same full eligible
/// list the desktop sidebar does, so a destination cannot be unreachable on
/// a phone — the failure that put Import and sign-out out of reach in T10.
class PhoneNavDrawer extends StatelessWidget {
  const PhoneNavDrawer({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
    this.footer,
    super.key,
  });

  final List<NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  /// The sidebar footer, reused verbatim so sign-out sits in the same place
  /// on a phone as on a laptop.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Drawer(
      backgroundColor: t.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.space4,
                ),
                children: [
                  for (final (i, destination) in destinations.indexed) ...[
                    // Grouped for the same reason the sidebar is: nine flat
                    // rows is a wall, and the headings match the hubs the
                    // product already has. Same data, same treatment — the
                    // drawer and the sidebar are the same list.
                    if (startsGroup(destinations, i))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.space6,
                          AppSpacing.space5,
                          AppSpacing.space6,
                          AppSpacing.space2,
                        ),
                        child: Overline(destination.group!),
                      ),
                    _DrawerItem(
                      destination: destination,
                      selected: i == selectedIndex,
                      onTap: () {
                        onSelect(i);
                        // Close after choosing: leaving it open would hide
                        // the screen the tap just navigated to.
                        Navigator.of(context).pop();
                      },
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

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
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

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(
          child: Container(
            margin: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space4,
              vertical: AppSpacing.space1,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space5,
              vertical: AppSpacing.space4,
            ),
            constraints: const BoxConstraints(
              minHeight: AppSizing.touchTargetMin,
            ),
            decoration: BoxDecoration(
              color: selected ? t.primarySubtle : null,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Row(
              children: [
                Icon(
                  destination.icon,
                  color: selected ? t.primaryTextOnSurface : t.textSecondary,
                ),
                const SizedBox(width: AppSpacing.space5),
                Expanded(
                  child: Text(
                    destination.label,
                    style: AppTypography.personName.copyWith(
                      // Selection carries weight AND colour, so it does not
                      // depend on colour alone.
                      color:
                          selected ? t.primaryTextOnSurface : t.textPrimary,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
