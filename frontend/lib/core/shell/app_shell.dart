import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/sizing.dart';
import '../theme/typography.dart';
import '../widgets/app_button.dart';
import '../widgets/states/error_state.dart';
import '../widgets/states/loading_skeleton.dart';
import 'bottom_nav.dart';
import 'desktop_sidebar.dart';
import 'identity_resolver.dart';
import 'mobile_app_bar.dart';
import 'nav_destination.dart';
import 'phone_nav_drawer.dart';
import 'sync_indicator.dart';
import 'sync_status.dart';

/// The root scaffold: resolves identity, filters and truncates the
/// destination list, picks chrome by breakpoint, and hosts an [IndexedStack]
/// so every tab's state survives switching (D-30).
///
/// Chrome by width — not by platform, per the task spec:
///  - `< AppSizing.navBottomBreakpoint` (600): [BottomNav]
///  - `< AppSizing.navRailBreakpoint` (1024): compact [DesktopSidebar] (rail)
///  - `>= AppSizing.navRailBreakpoint`: full [DesktopSidebar]
///
/// The SAME [destinations] list drives all three — only how much of it is
/// shown, and how, changes.
class AppShell extends StatefulWidget {
  const AppShell({
    required this.institutionName,
    required this.destinations,
    required this.entitledIds,
    this.identityResolver = const StaticIdentityResolver(),
    this.syncStatusSource = const StaticSyncStatusSource(),
    this.sidebarHeader,
    this.sidebarFooter,
    this.onSignOut,
    this.usePhoneDrawer = false,
    super.key,
  });

  /// Below the mobile breakpoint, show a DRAWER instead of the bottom bar.
  ///
  /// D-27 amendment (T16). D-27 truncates a phone to three destinations
  /// plus More, to stop the bar becoming a second navigation surface. Admin
  /// now has NINE destinations, so More had become exactly that — a list of
  /// six, which is a nav menu wearing a tab's clothes.
  ///
  /// The original reasoning is intact and still governs teacher, parent and
  /// student, who have few enough destinations for the rule to work as
  /// intended. Only the role that outgrew it changes.
  final bool usePhoneDrawer;

  /// Sign-out, offered on the gate screens (orphan / identity error).
  ///
  /// Those screens replace the whole shell — no nav, no More tab, no sidebar
  /// footer — so without this a user who lands on one has NO way out of the
  /// account. Found in manual testing (2026-09-19): a parent hit the orphan
  /// screen and was stuck. Null only in tests that do not exercise it.
  final Future<void> Function()? onSignOut;

  final String institutionName;

  /// The role's full ORDERED priority list (D-31). [AppShell] filters and,
  /// for the mobile chrome only, truncates it — the list itself never
  /// changes shape based on breakpoint.
  final List<NavDestination> destinations;

  /// Entitled module ids. No entitlement endpoint exists yet (T5 scope);
  /// callers pass the full id set today. See [filterByEntitlement].
  final Set<String> entitledIds;

  /// SEAM FOR T6 — see `identity_resolver.dart`.
  final IdentityResolver identityResolver;

  /// SEAM FOR T6 — see `sync_status.dart`.
  final SyncStatusSource syncStatusSource;

  final Widget? sidebarHeader;
  final Widget? sidebarFooter;

  @override
  State<AppShell> createState() => AppShellState();
}

/// A full-screen gate state with a way out.
///
/// The gate screens stand in for the entire shell, so the sign-out that
/// normally lives in the sidebar footer or the More tab is gone. This puts
/// it back, below the state, as a secondary action.
class _GateScaffold extends StatelessWidget {
  const _GateScaffold({required this.child, this.onSignOut});

  final Widget child;
  final Future<void> Function()? onSignOut;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.page,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: child),
            if (onSignOut != null)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.space6),
                child: AppButton(
                  label: 'Sign out',
                  variant: AppButtonVariant.secondary,
                  onPressed: onSignOut,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Public so tests can drive tab selection and read chrome state directly,
/// the same way `_AppButtonState`'s pressed/disabled logic is exercised via
/// its rendered output rather than a hidden private type.
class AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  late Future<IdentityResult> _identityFuture;
  late SyncStatus _syncStatus;

  @override
  void initState() {
    super.initState();
    _identityFuture = widget.identityResolver.resolveIdentity();
    _syncStatus = widget.syncStatusSource.current;
    widget.syncStatusSource.statusStream.listen((s) {
      if (mounted) setState(() => _syncStatus = s);
    });
  }

  void _retryIdentity() {
    setState(() {
      _identityFuture = widget.identityResolver.resolveIdentity();
    });
  }

  /// Test seam: drives tab selection the way a real nav tap would.
  void selectTab(int index) => setState(() => _selectedIndex = index);

  int get selectedIndex => _selectedIndex;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<IdentityResult>(
      future: _identityFuture,
      builder: (context, snapshot) {
        // The /me GATE — evaluated before ANY tab renders. Not inside a tab,
        // not a toast.
        if (!snapshot.hasData) {
          return const Scaffold(body: LoadingSkeleton.cards(count: 3));
        }

        final identity = snapshot.data!;
        if (identity.kind == IdentityResultKind.notLinked) {
          // D-17's orphan case. No retry — the user cannot fix this — but
          // they must still be able to leave the account.
          return _GateScaffold(
            onSignOut: widget.onSignOut,
            child: const UnlinkedProfileState(),
          );
        }
        if (identity.kind == IdentityResultKind.error) {
          return _GateScaffold(
            onSignOut: widget.onSignOut,
            child: ErrorState(
              message: identity.message,
              onRetry: _retryIdentity,
            ),
          );
        }

        return _Shell(
          institutionName: widget.institutionName,
          destinations: widget.destinations,
          entitledIds: widget.entitledIds,
          syncStatus: _syncStatus,
          selectedIndex: _selectedIndex,
          onSelect: selectTab,
          sidebarHeader: widget.sidebarHeader,
          sidebarFooter: widget.sidebarFooter,
          usePhoneDrawer: widget.usePhoneDrawer,
        );
      },
    );
  }
}

/// Lets the app bar's menu button open the drawer. A GlobalKey rather than
/// a Builder because the bar is constructed as the Scaffold's `appBar`,
/// which is outside the Scaffold's own BuildContext.
final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

/// Wires the app bar's BELL, which has existed since T5 and never did
/// anything, to the notifications destination when the role has one.
///
/// Returns null when it does not, so no bell renders rather than a bell
/// that goes nowhere (D-19).
VoidCallback? _notificationsTap(
  List<NavDestination> destinations,
  ValueChanged<int> onSelect,
) {
  final index = destinations.indexWhere((d) => d.id == 'notifications');
  if (index < 0) return null;
  return () => onSelect(index);
}

class _Shell extends StatelessWidget {
  const _Shell({
    required this.institutionName,
    required this.destinations,
    required this.entitledIds,
    required this.syncStatus,
    required this.selectedIndex,
    required this.onSelect,
    required this.sidebarHeader,
    required this.sidebarFooter,
    required this.usePhoneDrawer,
  });

  final String institutionName;
  final List<NavDestination> destinations;
  final Set<String> entitledIds;
  final SyncStatus syncStatus;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final Widget? sidebarHeader;
  final Widget? sidebarFooter;
  final bool usePhoneDrawer;

  @override
  Widget build(BuildContext context) {
    final eligible = filterByEntitlement(destinations, entitledIds);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final mobile = width < AppSizing.navBottomBreakpoint;
        // Rail range is 600-1024 INCLUSIVE; full sidebar is strictly ABOVE
        // 1024. <= here, not <, or 1024px itself would wrongly get the full
        // sidebar.
        final compactRail =
            !mobile && width <= AppSizing.navRailBreakpoint;

        // D-27 amendment (T16): a role with too many destinations gets a
        // drawer on a phone instead of 3 + More. Nothing is truncated, so
        // the chrome list is the full eligible one — the same list the
        // desktop sidebar shows.
        final phoneDrawer = mobile && usePhoneDrawer;

        // Mobile truncates to 3 + More (D-27); desktop/rail show everything
        // eligible (class doc on DesktopSidebar).
        final chromeDestinations = (mobile && !phoneDrawer)
            ? resolveBottomNavTabs(
                eligible,
                // The REAL overflow list. Was a "built in a later task"
                // placeholder, which on a phone made every destination past
                // the third unreachable — for admin (5 tabs) that included
                // Import and the More/sign-out screen itself. Found in
                // manual testing 2026-09-19.
                moreBuilder: (_) => _OverflowMore(
                  overflow: eligible.skip(3).toList(growable: false),
                ),
              )
            : eligible;

        // Clamp: entitlement or breakpoint changes can shrink the list out
        // from under a selectedIndex chosen against a longer one.
        final safeIndex = chromeDestinations.isEmpty
            ? 0
            : selectedIndex.clamp(0, chromeDestinations.length - 1);

        final tabs = _keptAliveTabs(chromeDestinations);

        if (phoneDrawer) {
          return Scaffold(
            appBar: MobileAppBar(
              institutionName: institutionName,
              syncStatus: syncStatus,
              onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
              onNotificationsTap:
                  _notificationsTap(chromeDestinations, onSelect),
            ),
            key: _scaffoldKey,
            drawer: PhoneNavDrawer(
              destinations: chromeDestinations,
              selectedIndex: safeIndex,
              onSelect: onSelect,
              footer: sidebarFooter,
            ),
            body: IndexedStack(index: safeIndex, children: tabs),
          );
        }

        if (mobile) {
          return Scaffold(
            appBar: MobileAppBar(
              institutionName: institutionName,
              syncStatus: syncStatus,
              onNotificationsTap:
                  _notificationsTap(chromeDestinations, onSelect),
            ),
            body: IndexedStack(index: safeIndex, children: tabs),
            bottomNavigationBar: BottomNav(
              destinations: chromeDestinations,
              selectedIndex: safeIndex,
              onSelect: onSelect,
            ),
          );
        }

        return Scaffold(
          body: Row(
            children: [
              DesktopSidebar(
                destinations: chromeDestinations,
                selectedIndex: safeIndex,
                onSelect: onSelect,
                compact: compactRail,
                header: sidebarHeader,
                footer: sidebarFooter,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Desktop had NO sync indicator — it lived only in the
                    // mobile app bar, so a teacher on a laptop could not see
                    // pending/offline state at all. Found in manual testing
                    // 2026-09-19. A slim bar, not in the sidebar: the compact
                    // rail is too narrow for the chip's label.
                    _DesktopTopBar(
                      institutionName: institutionName,
                      syncStatus: syncStatus,
                    ),
                    Expanded(
                      child: IndexedStack(index: safeIndex, children: tabs),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Wraps each destination's placeholder content in
/// [AutomaticKeepAliveClientMixin] (D-30). [IndexedStack] already keeps every
/// child mounted — nothing is disposed on switch even without this — but the
/// keep-alive contract is made explicit here so a future change to a lazier
/// container (`PageView`, `TabBarView`) does not silently lose state, and so
/// the D-30 requirement is visible in the shell rather than merely true by
/// accident of the current container choice.
List<Widget> _keptAliveTabs(List<NavDestination> destinations) => [
      for (final d in destinations)
        KeyedSubtree(
          key: ValueKey(d.id),
          child: _KeepAliveTab(builder: d.builder),
        ),
    ];

class _KeepAliveTab extends StatefulWidget {
  const _KeepAliveTab({required this.builder});

  final WidgetBuilder builder;

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.builder(context);
  }
}

class _DesktopTopBar extends StatelessWidget {
  const _DesktopTopBar({
    required this.institutionName,
    required this.syncStatus,
  });

  final String institutionName;
  final SyncStatus syncStatus;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space6,
        vertical: AppSpacing.space3,
      ),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(
          bottom: BorderSide(color: t.border, width: AppSizing.borderThin),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              institutionName,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.personName.copyWith(color: t.textPrimary),
            ),
          ),
          const SizedBox(width: AppSpacing.space4),
          SyncIndicator(status: syncStatus),
        ],
      ),
    );
  }
}

/// The phone "More" tab: every destination that did not fit in the bottom
/// bar, as a list. Tapping one opens that destination's own screen, with a
/// back button to return here.
///
/// A role whose own list already ends in a "More" (settings / sign-out)
/// destination shows it here as "Settings", so the synthesized tab and the
/// role's tab are never two things both called "More".
class _OverflowMore extends StatelessWidget {
  const _OverflowMore({required this.overflow});

  final List<NavDestination> overflow;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.space6),
      children: [
        for (final d in overflow)
          Semantics(
            button: true,
            label: _labelFor(d),
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    backgroundColor: t.page,
                    appBar: AppBar(
                      backgroundColor: t.surface,
                      surfaceTintColor: t.surface,
                      iconTheme: IconThemeData(color: t.textPrimary),
                      title: Text(
                        _labelFor(d),
                        style: AppTypography.cardHeading
                            .copyWith(color: t.textPrimary),
                      ),
                    ),
                    body: Builder(builder: d.builder),
                  ),
                ),
              ),
              child: ExcludeSemantics(
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: AppSizing.listRowMinHeight,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space5,
                  ),
                  margin: const EdgeInsets.only(bottom: AppSpacing.space3),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(
                      color: t.border,
                      width: AppSizing.borderThin,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        d.id == 'more' ? Icons.settings_outlined : d.icon,
                        color: t.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.space4),
                      Expanded(
                        child: Text(
                          _labelFor(d),
                          style: AppTypography.personName
                              .copyWith(color: t.textPrimary),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: t.textSecondary),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _labelFor(NavDestination d) =>
      d.id == 'more' ? 'Settings & sign out' : d.label;
}
