import 'package:flutter/material.dart';

import '../shell/bottom_nav.dart';
import '../shell/desktop_sidebar.dart';
import '../shell/mobile_app_bar.dart';
import '../shell/nav_destination.dart';
import '../shell/role_destinations.dart';
import '../shell/sync_indicator.dart';
import '../shell/sync_status.dart';
import 'app_theme.dart';
import 'scales.dart';
import 'sizing.dart';
import 'typography.dart';

/// The shell/navigation half of the living gallery (T5).
///
/// Shows the chrome components directly rather than embedding a full
/// [AppShell] — [AppShell] owns its own [Scaffold] and is meant to be the
/// whole screen, so nesting it here would nest Scaffolds. What matters for
/// review is visible without that: all four roles' resolved navigation, the
/// entitlement-driven promotion from D-31, and every [SyncIndicator] state.
class ShellGallerySection extends StatefulWidget {
  const ShellGallerySection({super.key});

  @override
  State<ShellGallerySection> createState() => _ShellGallerySectionState();
}

class _ShellGallerySectionState extends State<ShellGallerySection> {
  int _parentTab = 0;
  int _parentTabNoFinance = 0;
  int _teacherTab = 0;
  int _studentTab = 0;
  int _adminTab = 0;
  int _sidebarSelected = 1;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    final parentFull = RoleDestinations.allIdsFor(RoleDestinations.parent);
    final parentNoFinance = {...parentFull}..remove('fees');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _H('Shell and navigation'),
        const SizedBox(height: AppSpacing.space2),
        const _N(
          'One shared destination list per role (D-31), rendered as bottom '
          'tabs under 600px, a compact rail 600–1024px, and a full sidebar '
          'above that. The list is an ORDERED PRIORITY list, not a fixed set '
          'of four — BottomNav and DesktopSidebar render whatever they are '
          'given.',
        ),
        const SizedBox(height: AppSpacing.space8),

        // --- MobileAppBar ------------------------------------------------
        const _H('MobileAppBar (D-26 — status only, no actions)'),
        const SizedBox(height: AppSpacing.space2),
        const _N(
          'No actions parameter exists on this widget at all. The bell is a '
          'destination (opens a list), not a mutating action.',
        ),
        const SizedBox(height: AppSpacing.space5),
        _Frame(
          child: MobileAppBar(
            institutionName: 'Beaconhouse School — Gulberg Campus',
            syncStatus: const SyncStatus.synced(),
            hasUnreadNotifications: true,
            onNotificationsTap: () {},
          ),
        ),
        const SizedBox(height: AppSpacing.space8),

        // --- SyncIndicator -------------------------------------------------
        const _H('SyncIndicator — always visible, all three states'),
        const SizedBox(height: AppSpacing.space2),
        const _N(
          'The previous build rendered nothing when healthy. Here, "synced" '
          'is exactly as visible as "offline".',
        ),
        const SizedBox(height: AppSpacing.space5),
        const Wrap(
          spacing: AppSpacing.space4,
          runSpacing: AppSpacing.space4,
          children: [
            SyncIndicator(status: SyncStatus.synced()),
            SyncIndicator(status: SyncStatus.syncing()),
            SyncIndicator(status: SyncStatus.offline(pendingCount: 3)),
          ],
        ),
        const SizedBox(height: AppSpacing.space8),

        // --- D-31 worked example ------------------------------------------
        const _H('D-31 — entitlement promotion, Parent role'),
        const SizedBox(height: AppSpacing.space2),
        const _N(
          "D-31's own example. With Finance entitled: My child · Attendance · "
          'Fees · More. Remove Finance and Fees drops out — Complaints '
          'promotes into the third slot automatically, because the '
          'declared list was already ranked. No code change between the two '
          'rows below, only a smaller entitledIds set.',
        ),
        const SizedBox(height: AppSpacing.space5),
        Text(
          'entitled: full list (Finance ON)',
          style: AppTypography.overline.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space3),
        _Frame(
          child: BottomNav(
            destinations: resolveBottomNavTabs(
              filterByEntitlement(RoleDestinations.parent, parentFull),
              moreBuilder: (_) => const SizedBox.shrink(),
            ),
            selectedIndex: _parentTab,
            onSelect: (i) => setState(() => _parentTab = i),
          ),
        ),
        const SizedBox(height: AppSpacing.space5),
        Text(
          'entitled: Finance OFF — Fees dropped, Complaints promoted',
          style: AppTypography.overline.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space3),
        _Frame(
          child: BottomNav(
            destinations: resolveBottomNavTabs(
              filterByEntitlement(RoleDestinations.parent, parentNoFinance),
              moreBuilder: (_) => const SizedBox.shrink(),
            ),
            selectedIndex: _parentTabNoFinance,
            onSelect: (i) => setState(() => _parentTabNoFinance = i),
          ),
        ),
        const SizedBox(height: AppSpacing.space8),

        // --- BottomNav, all four roles -------------------------------------
        const _H('BottomNav — all four roles'),
        const SizedBox(height: AppSpacing.space2),
        const _N(
          "Teacher's Classes is a HUB (D-27), ranked below the three daily "
          'tasks, so it lands in More by default rather than earning a tab.',
        ),
        const SizedBox(height: AppSpacing.space5),
        for (final (label, dests, tab, setTab) in [
          (
            'Teacher',
            RoleDestinations.teacher,
            _teacherTab,
            (int i) => setState(() => _teacherTab = i),
          ),
          (
            'Student',
            RoleDestinations.student,
            _studentTab,
            (int i) => setState(() => _studentTab = i),
          ),
          (
            'Admin',
            RoleDestinations.admin,
            _adminTab,
            (int i) => setState(() => _adminTab = i),
          ),
        ]) ...[
          Text(
            label,
            style: AppTypography.overline.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space3),
          _Frame(
            child: BottomNav(
              destinations: resolveBottomNavTabs(
                filterByEntitlement(dests, RoleDestinations.allIdsFor(dests)),
                moreBuilder: (_) => const SizedBox.shrink(),
              ),
              selectedIndex: tab,
              onSelect: setTab,
            ),
          ),
          const SizedBox(height: AppSpacing.space6),
        ],
        const SizedBox(height: AppSpacing.space4),

        // --- DesktopSidebar --------------------------------------------
        const _H('DesktopSidebar — compact rail and full form'),
        const SizedBox(height: AppSpacing.space2),
        const _N(
          'Active state is a LEFT BORDER plus a surface change, never a '
          'fill — a fill reads as a button, a border reads as position. '
          'Desktop shows every entitled destination, not three-plus-More.',
        ),
        const SizedBox(height: AppSpacing.space5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'compact (rail, 600–1024px)',
                  style: AppTypography.overline.copyWith(
                    color: t.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.space3),
                SizedBox(
                  height: 320,
                  child: _Frame(
                    child: DesktopSidebar(
                      destinations: filterByEntitlement(
                        RoleDestinations.admin,
                        RoleDestinations.allIdsFor(RoleDestinations.admin),
                      ),
                      selectedIndex: _sidebarSelected,
                      onSelect: (i) => setState(() => _sidebarSelected = i),
                      compact: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: AppSpacing.space6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'full (>= 1024px)',
                    style: AppTypography.overline.copyWith(
                      color: t.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space3),
                  SizedBox(
                    height: 320,
                    child: _Frame(
                      child: DesktopSidebar(
                        destinations: filterByEntitlement(
                          RoleDestinations.admin,
                          RoleDestinations.allIdsFor(RoleDestinations.admin),
                        ),
                        selectedIndex: _sidebarSelected,
                        onSelect: (i) => setState(() => _sidebarSelected = i),
                        header: Text(
                          'Smart EMS',
                          style: AppTypography.cardHeading.copyWith(
                            color: t.textPrimary,
                          ),
                        ),
                        footer: Row(
                          children: [
                            CircleAvatar(
                              radius: AppSpacing.space6,
                              backgroundColor: t.primarySubtle,
                              child: Text(
                                'AK',
                                // textPrimary, not primaryTextOnSurface — see
                                // the D-36 note in desktop_sidebar.dart.
                                // primarySubtle is not a background that
                                // token is valid on.
                                style: AppTypography.overline.copyWith(
                                  color: t.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.space3),
                            Expanded(
                              child: Text(
                                'Ali Khan · Admin',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.fieldLabel.copyWith(
                                  color: t.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space10),
      ],
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: t.border, width: AppSizing.borderThin),
        ),
        child: child,
      ),
    );
  }
}

class _H extends StatelessWidget {
  const _H(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: AppTypography.sectionHeading.copyWith(
          color: context.tokens.textPrimary,
        ),
      );
}

class _N extends StatelessWidget {
  const _N(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: AppTypography.bodyAdminMeta.copyWith(
          color: context.tokens.textSecondary,
        ),
      );
}
