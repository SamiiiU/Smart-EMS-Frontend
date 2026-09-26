import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/shell/app_shell.dart';
import 'package:smartems/core/shell/bottom_nav.dart';
import 'package:smartems/core/shell/desktop_sidebar.dart';
import 'package:smartems/core/shell/identity_resolver.dart';
import 'package:smartems/core/shell/mobile_app_bar.dart';
import 'package:smartems/core/shell/nav_destination.dart';
import 'package:smartems/core/shell/role_destinations.dart';
import 'package:smartems/core/shell/sync_indicator.dart';
import 'package:smartems/core/shell/sync_status.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/widgets/overline.dart';
import 'package:smartems/core/theme/sizing.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/app_button.dart';
import 'package:smartems/core/widgets/states/error_state.dart';

Widget host(
  Widget child, {
  bool dark = false,
  Locale? locale,
  TextDirection? direction,
  double textScale = 1.0,
}) {
  Widget app = MaterialApp(
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    theme: AppTheme.light(role: AppRole.admin),
    darkTheme: AppTheme.dark(role: AppRole.admin),
    builder: (context, mqChild) {
      var out = mqChild!;
      if (direction != null) out = Directionality(textDirection: direction, child: out);
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: out,
      );
    },
    home: child,
  );
  return app;
}

NavDestination fakeDest(
  String id, {
  bool alwaysVisible = false,
  void Function()? onBuild,
}) {
  return NavDestination(
    id: id,
    label: id,
    icon: Icons.circle,
    route: '/$id',
    alwaysVisible: alwaysVisible,
    builder: (context) {
      onBuild?.call();
      return Center(child: Text('content:$id'));
    },
  );
}

/// A stateful tab whose counter proves whether its State survived a
/// switch-away-and-back, rather than merely proving `build()` ran.
class _CounterTab extends StatefulWidget {
  const _CounterTab();

  @override
  State<_CounterTab> createState() => _CounterTabState();
}

class _CounterTabState extends State<_CounterTab> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('count:$_count'),
          IconButton(
            key: const ValueKey('counter_increment'),
            icon: const Icon(Icons.add),
            onPressed: () => setState(() => _count++),
          ),
        ],
      ),
    );
  }
}

void main() {
  // ==========================================================================
  // D-31 — entitlement filtering and promotion.
  // ==========================================================================
  group('D-31: entitlement filtering', () {
    test('filterByEntitlement preserves order and drops the unentitled', () {
      final declared = [fakeDest('a'), fakeDest('b'), fakeDest('c')];
      final eligible = filterByEntitlement(declared, {'a', 'c'});
      expect(eligible.map((d) => d.id), ['a', 'c']);
    });

    test('alwaysVisible bypasses entitlement entirely', () {
      final declared = [fakeDest('a', alwaysVisible: true), fakeDest('b')];
      final eligible = filterByEntitlement(declared, <String>{});
      expect(eligible.map((d) => d.id), ['a']);
    });

    test('resolveBottomNavTabs: <= 3 eligible renders as-is, no More', () {
      final eligible = [fakeDest('a'), fakeDest('b')];
      final tabs = resolveBottomNavTabs(
        eligible,
        moreBuilder: (_) => const SizedBox.shrink(),
      );
      expect(tabs.map((d) => d.id), ['a', 'b']);
      expect(
        tabs.any((d) => d.id == 'more'),
        isFalse,
        reason: 'nothing was truncated, so More must not appear',
      );
    });

    test('resolveBottomNavTabs: > 3 eligible truncates to 3 + More', () {
      final eligible =
          [for (final id in ['a', 'b', 'c', 'd', 'e']) fakeDest(id)];
      final tabs = resolveBottomNavTabs(
        eligible,
        moreBuilder: (_) => const SizedBox.shrink(),
      );
      expect(tabs.length, 4);
      expect(tabs.map((d) => d.id), ['a', 'b', 'c', 'more']);
    });

    test('removing an entitlement PROMOTES the next item — no gap', () {
      final declared =
          [for (final id in ['a', 'b', 'c', 'd', 'e']) fakeDest(id)];

      final before = resolveBottomNavTabs(
        filterByEntitlement(declared, {'a', 'b', 'c', 'd', 'e'}),
        moreBuilder: (_) => const SizedBox.shrink(),
      );
      expect(before.map((d) => d.id), ['a', 'b', 'c', 'more']);

      // Remove 'b' — 'c' must promote into its slot, not leave a gap.
      final after = resolveBottomNavTabs(
        filterByEntitlement(declared, {'a', 'c', 'd', 'e'}),
        moreBuilder: (_) => const SizedBox.shrink(),
      );
      expect(
        after.map((d) => d.id),
        ['a', 'c', 'd', 'more'],
        reason: 'c and d must promote automatically — the list was already '
            'ranked, so this requires no special-case code',
      );
    });

    test("D-31's own worked example: Parent, Finance on vs off", () {
      final full = RoleDestinations.allIdsFor(RoleDestinations.parent);
      final onTabs = resolveBottomNavTabs(
        filterByEntitlement(RoleDestinations.parent, full),
        moreBuilder: (_) => const SizedBox.shrink(),
      );
      expect(onTabs.map((d) => d.id), ['my_child', 'attendance', 'fees', 'more']);

      final noFinance = {...full}..remove('fees');
      final offTabs = resolveBottomNavTabs(
        filterByEntitlement(RoleDestinations.parent, noFinance),
        moreBuilder: (_) => const SizedBox.shrink(),
      );
      expect(
        offTabs.map((d) => d.id),
        ['my_child', 'attendance', 'complaints', 'more'],
        reason: 'Fees drops, Complaints promotes into the third slot',
      );
    });

    test('a role declaring fewer than four destinations still renders '
        'correctly', () {
      final declared = [fakeDest('a'), fakeDest('b')];
      final tabs = resolveBottomNavTabs(
        filterByEntitlement(declared, {'a', 'b'}),
        moreBuilder: (_) => const SizedBox.shrink(),
      );
      expect(tabs.length, 2);
    });

    testWidgets('BottomNav renders whatever length list it is given — 2, 3, '
        'or 4', (tester) async {
      for (final n in [2, 3, 4]) {
        final dests = [for (var i = 0; i < n; i++) fakeDest('d$i')];
        await tester.pumpWidget(
          host(
            Scaffold(
              body: BottomNav(
                destinations: dests,
                selectedIndex: 0,
                onSelect: (_) {},
              ),
            ),
          ),
        );
        expect(find.byType(BottomNav), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('DesktopSidebar shows every eligible destination, not '
        'three-plus-More', (tester) async {
      final dests = [for (var i = 0; i < 6; i++) fakeDest('d$i')];
      await tester.pumpWidget(
        host(
          Scaffold(
            body: DesktopSidebar(
              destinations: dests,
              selectedIndex: 0,
              onSelect: (_) {},
            ),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        expect(find.text('d$i'), findsOneWidget);
      }
    });
  });

  // ==========================================================================
  // D-30 — tab state survives switching (navigation half).
  // ==========================================================================
  group('D-30: tab state and scroll survive switching', () {
    testWidgets(
        'scroll position survives: scroll tab 2, switch to 1, switch back',
        (tester) async {
      final controllers = {
        0: ScrollController(),
        1: ScrollController(),
      };

      Widget buildTab(int index) {
        return ListView.builder(
          controller: controllers[index],
          itemCount: 200,
          itemBuilder: (context, i) => SizedBox(
            height: 50,
            child: Text('tab$index-item$i'),
          ),
        );
      }

      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) {
              var selected = 0;
              return StatefulBuilder(
                builder: (context, setInner) {
                  return Scaffold(
                    body: IndexedStack(
                      index: selected,
                      children: [buildTab(0), buildTab(1)],
                    ),
                    bottomNavigationBar: Row(
                      children: [
                        TextButton(
                          onPressed: () => setInner(() => selected = 0),
                          child: const Text('tab0'),
                        ),
                        TextButton(
                          onPressed: () => setInner(() => selected = 1),
                          child: const Text('tab1'),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      );

      // Scroll tab 1 (currently visible after switching).
      await tester.tap(find.text('tab1'));
      await tester.pump();
      controllers[1]!.jumpTo(500);
      await tester.pump();
      expect(controllers[1]!.offset, 500);

      // Switch to tab 0, then back to tab 1.
      await tester.tap(find.text('tab0'));
      await tester.pump();
      await tester.tap(find.text('tab1'));
      await tester.pump();

      expect(
        controllers[1]!.offset,
        500,
        reason: 'IndexedStack must not have disposed tab 1, or its scroll '
            'controller would have reset to 0',
      );

      for (final c in controllers.values) {
        c.dispose();
      }
    });

    testWidgets('AppShell.selectTab switches the visible tab instantly, no '
        'animation frame required', (tester) async {
      final dests = [fakeDest('a'), fakeDest('b')];
      final key = GlobalKey<AppShellState>();

      await tester.pumpWidget(
        host(
          AppShell(
            key: key,
            institutionName: 'Test School',
            destinations: dests,
            entitledIds: {'a', 'b'},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('content:a'), findsOneWidget);

      key.currentState!.selectTab(1);
      // A single pump (not pumpAndSettle) is enough — instant switch, no
      // transition to wait out.
      await tester.pump();

      expect(find.text('content:b'), findsOneWidget);
    });

    testWidgets(
        'switched-away tab STATE survives — AutomaticKeepAliveClientMixin '
        'keeps it mounted rather than disposing it', (tester) async {
      // AutomaticKeepAliveClientMixin prevents STATE DISPOSAL, not
      // rebuild-on-ancestor-setState: Flutter calls build() again on every
      // ancestor rebuild regardless of keep-alive status. The real D-30
      // guarantee is that STATE (not "was build() called") survives a
      // switch away and back, so this proves it with a counter rather than
      // a builder-invocation count.
      final dests = [
        fakeDest('a'),
        NavDestination(
          id: 'b',
          label: 'b',
          icon: Icons.circle,
          route: '/b',
          builder: (context) => const _CounterTab(),
        ),
      ];
      final key = GlobalKey<AppShellState>();

      await tester.pumpWidget(
        host(
          AppShell(
            key: key,
            institutionName: 'Test School',
            destinations: dests,
            entitledIds: {'a', 'b'},
          ),
        ),
      );
      await tester.pumpAndSettle();

      key.currentState!.selectTab(1);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('counter_increment')));
      await tester.tap(find.byKey(const ValueKey('counter_increment')));
      await tester.pump();
      expect(find.text('count:2'), findsOneWidget);

      key.currentState!.selectTab(0);
      await tester.pump();
      key.currentState!.selectTab(1);
      await tester.pump();

      // If the tab's State had been disposed and recreated, the counter
      // would have reset to 0.
      expect(find.text('count:2'), findsOneWidget);
    });
  });

  // ==========================================================================
  // Responsive chrome — exact breakpoints.
  // ==========================================================================
  group('Responsive chrome at exact breakpoints', () {
    Future<void> pumpAt(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(
          AppShell(
            institutionName: 'Test School',
            destinations: [for (var i = 0; i < 5; i++) fakeDest('d$i')],
            entitledIds: {'d0', 'd1', 'd2', 'd3', 'd4'},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('599px -> BottomNav', (tester) async {
      await pumpAt(tester, 599);
      expect(find.byType(BottomNav), findsOneWidget);
      expect(find.byType(DesktopSidebar), findsNothing);
    });

    testWidgets('600px -> compact DesktopSidebar (rail), not BottomNav',
        (tester) async {
      await pumpAt(tester, AppSizing.navBottomBreakpoint);
      expect(find.byType(BottomNav), findsNothing);
      final sidebar =
          tester.widget<DesktopSidebar>(find.byType(DesktopSidebar));
      expect(sidebar.compact, isTrue);
    });

    testWidgets('1024px -> compact DesktopSidebar (rail)', (tester) async {
      await pumpAt(tester, AppSizing.navRailBreakpoint);
      final sidebar =
          tester.widget<DesktopSidebar>(find.byType(DesktopSidebar));
      expect(sidebar.compact, isTrue);
    });

    testWidgets('1025px -> full DesktopSidebar', (tester) async {
      await pumpAt(tester, AppSizing.navRailBreakpoint + 1);
      final sidebar =
          tester.widget<DesktopSidebar>(find.byType(DesktopSidebar));
      expect(sidebar.compact, isFalse);
    });

    testWidgets('the SAME destination list drives all three chrome forms',
        (tester) async {
      // 800px is the compact rail: DesktopSidebar renders icon-only there
      // (no label text), so a literal text search would fail by design —
      // assert on the resolved destination set instead of on text.
      for (final width in [599.0, 800.0, 1200.0]) {
        await pumpAt(tester, width);
        if (width < AppSizing.navBottomBreakpoint) {
          final nav = tester.widget<BottomNav>(find.byType(BottomNav));
          expect(nav.destinations.first.id, 'd0');
        } else {
          final sidebar =
              tester.widget<DesktopSidebar>(find.byType(DesktopSidebar));
          expect(sidebar.destinations.first.id, 'd0');
          expect(sidebar.destinations, hasLength(5));
        }
      }
    });
  });

  // ==========================================================================
  // MobileAppBar — D-26.
  // ==========================================================================
  group('MobileAppBar — D-26 status only', () {
    // ABSENCE: there is no `actions` constructor parameter on MobileAppBar at
    // all — this is a COMPILE-TIME guarantee, not a runtime one. The
    // constructor below has exactly institutionName/syncStatus/
    // hasUnreadNotifications/onNotificationsTap; adding `actions: [...]`
    // to this call would fail to compile, which is the enforcement.
    testWidgets('renders status only: title and sync indicator, no '
        'action controls beyond the optional notifications destination',
        (tester) async {
      await tester.pumpWidget(
        host(
          const Scaffold(
            appBar: MobileAppBar(
              institutionName: 'Beaconhouse School',
              syncStatus: SyncStatus.synced(),
            ),
          ),
        ),
      );
      expect(find.text('Beaconhouse School'), findsOneWidget);
      expect(find.byType(SyncIndicator), findsOneWidget);
      expect(find.byIcon(Icons.notifications_outlined), findsNothing);
      expect(find.byType(IconButton), findsNothing);
      expect(find.byType(PopupMenuButton), findsNothing);
    });

    // POSITIVE CASE for the absence above (task rule: an absence-assertion
    // must be paired with its positive case) — a screen that genuinely needs
    // an action renders it in its OWN content, not the app bar.
    testWidgets('POSITIVE CASE: a screen needing an action renders it in tab '
        'content, not the app bar', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        host(
          Scaffold(
            appBar: const MobileAppBar(
              institutionName: 'Beaconhouse School',
              syncStatus: SyncStatus.synced(),
            ),
            body: AppButton(label: 'Mark attendance', onPressed: () => tapped++),
          ),
        ),
      );
      await tester.tap(find.byType(AppButton));
      expect(tapped, 1);
    });

    testWidgets('notifications bell is a DESTINATION (navigates), optional, '
        'omitted entirely when there is nothing for it to do (D-19)',
        (tester) async {
      // Omitted: no bell renders. Not a disabled bell — an ABSENT one.
      await tester.pumpWidget(
        host(
          const Scaffold(
            appBar: MobileAppBar(
              institutionName: 'x',
              syncStatus: SyncStatus.synced(),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.notifications_outlined), findsNothing);

      // Supplied: bell renders and navigates on tap.
      var tapped = 0;
      await tester.pumpWidget(
        host(
          Scaffold(
            appBar: MobileAppBar(
              institutionName: 'x',
              syncStatus: const SyncStatus.synced(),
              onNotificationsTap: () => tapped++,
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.notifications_outlined));
      expect(tapped, 1);
    });

    testWidgets('SyncIndicator renders all three states inside the app bar',
        (tester) async {
      for (final status in [
        const SyncStatus.synced(),
        const SyncStatus.syncing(),
        const SyncStatus.offline(pendingCount: 4),
      ]) {
        await tester.pumpWidget(
          host(
            Scaffold(
              appBar: MobileAppBar(
                institutionName: 'x',
                syncStatus: status,
              ),
            ),
          ),
        );
        expect(find.byType(SyncIndicator), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });

  // ==========================================================================
  // `/me` gate — evaluated before any tab renders.
  // ==========================================================================
  group('/me identity gate', () {
    testWidgets('notLinked renders UnlinkedProfileState, not a tab, no retry',
        (tester) async {
      var tabBuilds = 0;
      await tester.pumpWidget(
        host(
          AppShell(
            institutionName: 'x',
            destinations: [fakeDest('a', onBuild: () => tabBuilds++)],
            entitledIds: {'a'},
            identityResolver: const StaticIdentityResolver(
              IdentityResult(IdentityResultKind.notLinked),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(UnlinkedProfileState), findsOneWidget);
      expect(find.byType(BottomNav), findsNothing);
      expect(find.byType(DesktopSidebar), findsNothing);
      expect(
        tabBuilds,
        0,
        reason: 'the gate must be evaluated BEFORE any tab renders',
      );
    });

    testWidgets('error renders ErrorState with a WORKING retry',
        (tester) async {
      var attempts = 0;
      final resolver = _CountingIdentityResolver(() {
        attempts++;
        return attempts == 1
            ? const IdentityResult(IdentityResultKind.error, message: 'Timed out')
            : const IdentityResult(IdentityResultKind.linked);
      });

      await tester.pumpWidget(
        host(
          AppShell(
            institutionName: 'x',
            destinations: [fakeDest('a')],
            entitledIds: {'a'},
            identityResolver: resolver,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('Timed out'), findsOneWidget);

      await tester.tap(find.byType(AppButton));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsNothing);
      expect(find.text('content:a'), findsOneWidget);
    });

    testWidgets('linked renders the shell, with the tab visible',
        (tester) async {
      await tester.pumpWidget(
        host(
          AppShell(
            institutionName: 'x',
            destinations: [fakeDest('a')],
            entitledIds: {'a'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('content:a'), findsOneWidget);
    });
  });

  // ==========================================================================
  // Accessibility paths — tested explicitly, per standing rule (never the
  // default path, so nobody exercises them by accident).
  // ==========================================================================
  group('Accessibility', () {
    testWidgets('reduced motion: tab switch is still instant (nothing to '
        'disable, confirmed rather than assumed)', (tester) async {
      final dests = [fakeDest('a'), fakeDest('b')];
      final key = GlobalKey<AppShellState>();

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: host(
            AppShell(
              key: key,
              institutionName: 'x',
              destinations: dests,
              entitledIds: {'a', 'b'},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      key.currentState!.selectTab(1);
      await tester.pump();
      expect(
        find.text('content:b'),
        findsOneWidget,
        reason: 'switch must be immediate under reduced motion too',
      );
    });

    testWidgets('large text scale: nav labels do not overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(
          Scaffold(
            body: BottomNav(
              destinations: [
                fakeDest('attendance'),
                fakeDest('complaints'),
                fakeDest('more'),
              ],
              selectedIndex: 0,
              onSelect: (_) {},
            ),
          ),
          textScale: 2.0,
        ),
      );
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'a RenderFlex overflow at 2x text scale means labels clip',
      );
    });

    testWidgets('RTL: icon/label order mirrors in DesktopSidebar',
        (tester) async {
      Future<double> iconThenLabelDx(TextDirection dir) async {
        await tester.pumpWidget(
          host(
            Scaffold(
              body: DesktopSidebar(
                destinations: [fakeDest('a')],
                selectedIndex: 0,
                onSelect: (_) {},
              ),
            ),
            direction: dir,
          ),
        );
        final iconDx = tester.getTopLeft(find.byIcon(Icons.circle)).dx;
        final labelDx = tester.getTopLeft(find.text('a')).dx;
        return iconDx - labelDx;
      }

      final ltrDelta = await iconThenLabelDx(TextDirection.ltr);
      final rtlDelta = await iconThenLabelDx(TextDirection.rtl);

      expect(
        ltrDelta.sign,
        isNot(rtlDelta.sign),
        reason: 'icon sits before the label in LTR and after it in RTL — if '
            'the sign is the same, the row did not mirror',
      );
    });

    testWidgets('screen reader: each destination has its OWN distinct '
        'semantic label, separate from the icon', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          Scaffold(
            body: BottomNav(
              destinations: [fakeDest('attendance'), fakeDest('diary')],
              selectedIndex: 0,
              onSelect: (_) {},
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('attendance'), findsOneWidget);
      expect(find.bySemanticsLabel('diary'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('screen reader: DesktopSidebar items are distinctly labelled '
        'too', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          Scaffold(
            body: DesktopSidebar(
              destinations: [fakeDest('staff'), fakeDest('students')],
              selectedIndex: 0,
              onSelect: (_) {},
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('staff'), findsOneWidget);
      expect(find.bySemanticsLabel('students'), findsOneWidget);
      handle.dispose();
    });
  });

  // ==========================================================================
  // Layout — standing Phase 6 requirement.
  // ==========================================================================
  group('No overflow at 360, 768 and 1366px', () {
    for (final width in <double>[360, 768, 1366]) {
      testWidgets('AppShell renders clean at ${width.toInt()}px',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          host(
            AppShell(
              institutionName: 'A Reasonably Long Institution Name Here',
              destinations: RoleDestinations.admin,
              entitledIds: RoleDestinations.allIdsFor(RoleDestinations.admin),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow at ${width.toInt()}px',
        );
      });
    }
  });

  // Polish pass: nine flat admin destinations is a wall, so the sidebar and
  // the drawer group them under headings that match the hubs.
  group('nav grouping', () {
    List<NavDestination> grouped() => [
          NavDestination(
            id: 'a',
            label: 'Dashboard',
            icon: Icons.circle_outlined,
            route: '/a',
            group: 'Overview',
            builder: (_) => const Text('a'),
          ),
          NavDestination(
            id: 'b',
            label: 'Setup',
            icon: Icons.circle_outlined,
            route: '/b',
            group: 'School',
            builder: (_) => const Text('b'),
          ),
          NavDestination(
            id: 'c',
            label: 'Fees',
            icon: Icons.circle_outlined,
            route: '/c',
            group: 'School',
            builder: (_) => const Text('c'),
          ),
        ];

    List<NavDestination> ungrouped() => [
          for (var i = 0; i < 3; i++)
            NavDestination(
              id: 'u$i',
              label: 'Plain $i',
              icon: Icons.circle_outlined,
              route: '/u$i',
              builder: (_) => Text('u$i'),
            ),
        ];

    Widget sidebar(List<NavDestination> destinations, {bool compact = false}) =>
        MaterialApp(
          theme: AppTheme.light(role: AppRole.admin),
          home: Scaffold(
            body: DesktopSidebar(
              destinations: destinations,
              selectedIndex: 0,
              onSelect: (_) {},
              compact: compact,
            ),
          ),
        );

    testWidgets('a heading appears once per group, not once per item',
        (tester) async {
      await tester.pumpWidget(sidebar(grouped()));
      await tester.pumpAndSettle();

      // Overline uppercases, so match on the semantics label, which keeps
      // the natural case for screen readers.
      expect(find.bySemanticsLabel('Overview'), findsOneWidget);
      expect(find.bySemanticsLabel('School'), findsOneWidget);
    });

    testWidgets('an UNGROUPED list renders exactly as it always did',
        (tester) async {
      await tester.pumpWidget(sidebar(ungrouped()));
      await tester.pumpAndSettle();

      // The property that let the shell goldens pass untouched: teacher,
      // parent and student have no groups and must be unaffected.
      expect(find.byType(Overline), findsNothing);
      for (var i = 0; i < 3; i++) {
        expect(find.text('Plain $i'), findsOneWidget);
      }
    });

    testWidgets('the compact rail shows no headings — 72px has no room',
        (tester) async {
      await tester.pumpWidget(sidebar(grouped(), compact: true));
      await tester.pumpAndSettle();

      expect(find.byType(Overline), findsNothing);
    });

    testWidgets('headings do not shift the selected index', (tester) async {
      final destinations = grouped();
      var selected = -1;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(role: AppRole.admin),
        home: Scaffold(
          body: DesktopSidebar(
            destinations: destinations,
            selectedIndex: 0,
            onSelect: (i) => selected = i,
            compact: false,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // 'Fees' is index 2 in the CALLER's list. Headings are interleaved at
      // render time, so a heading must never be counted as a destination.
      await tester.tap(find.text('Fees'));
      await tester.pumpAndSettle();
      expect(selected, 2);
    });

    test('a group is detected by change, not by first-seen', () {
      final destinations = grouped();
      expect(startsGroup(destinations, 0), isTrue);
      expect(startsGroup(destinations, 1), isTrue);
      // Same group as the previous entry — no second heading.
      expect(startsGroup(destinations, 2), isFalse);
    });

    test('an ungrouped destination never starts a group', () {
      expect(startsGroup(ungrouped(), 0), isFalse);
    });
  });
}

class _CountingIdentityResolver implements IdentityResolver {
  _CountingIdentityResolver(this._next);

  final IdentityResult Function() _next;

  @override
  Future<IdentityResult> resolveIdentity() async => _next();
}
