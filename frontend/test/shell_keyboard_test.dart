import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/api_config.dart';
import 'package:smartems/core/network/token_store.dart';
import 'package:smartems/core/shell/bottom_nav.dart';
import 'package:smartems/core/shell/desktop_sidebar.dart';
import 'package:smartems/core/shell/mobile_app_bar.dart';
import 'package:smartems/core/shell/nav_destination.dart';
import 'package:smartems/core/shell/phone_nav_drawer.dart';
import 'package:smartems/core/shell/sync_status.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/app_button.dart';
import 'package:smartems/features/auth/data/auth_repository.dart';
import 'package:smartems/features/auth/presentation/login_screen.dart';
import 'package:smartems/features/setup/presentation/setup_scaffold.dart';

/// A11Y-2 (shell navigation) and A11Y-3 (password visibility toggle): every
/// control must be reachable with Tab / Shift+Tab, run with Enter / Space,
/// show a keyboard-only focus ring, and expose one named, focusable node
/// (Flutter Web turns only focusable nodes into DOM tab stops).

NavDestination _d(String id, String label, IconData icon, {String? group}) =>
    NavDestination(
      id: id,
      label: label,
      icon: icon,
      route: '/$id',
      builder: (_) => const SizedBox(),
      group: group,
    );

final _dest = [
  _d('today', 'Today', Icons.today, group: 'Overview'),
  _d('students', 'Students', Icons.people, group: 'Overview'),
  _d('fees', 'Fees', Icons.payments, group: 'Institution'),
  _d('more', 'More', Icons.more_horiz),
];

Widget _app(
  Widget child, {
  bool dark = false,
  Size size = const Size(1440, 900),
}) => MediaQuery(
  data: MediaQueryData(size: size),
  child: MaterialApp(
    theme: dark
        ? AppTheme.dark(role: AppRole.admin)
        : AppTheme.light(role: AppRole.admin),
    home: child,
  ),
);

Future<void> _tab(WidgetTester tester, {bool shift = false}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

/// The semantics node for [label] currently holds keyboard focus.
bool _focused(WidgetTester tester, String label) {
  final f = find.bySemanticsLabel(label);
  if (f.evaluate().isEmpty) return false;
  return tester.getSemantics(f.first).flagsCollection.isFocused ==
      Tristate.isTrue;
}

/// Real keyboard focus (FocusManager) is inside [finder]'s subtree.
bool _primaryIn(WidgetTester tester, Finder finder) {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null || finder.evaluate().isEmpty) return false;
  final target = finder.evaluate().first;
  if (identical(ctx, target)) return true;
  var found = false;
  ctx.visitAncestorElements((e) {
    found = identical(e, target);
    return !found;
  });
  return found;
}

Future<int> _tabUntil(
  WidgetTester tester,
  String label, {
  int max = 20,
  bool shift = false,
}) async {
  for (var i = 1; i <= max; i++) {
    await _tab(tester, shift: shift);
    if (_focused(tester, label)) return i;
  }
  return 0;
}

/// A keyboard focus ring (2 px foreground border) is painted somewhere.
Finder _ring() => find.byWidgetPredicate(
  (w) =>
      w is DecoratedBox &&
      w.position == DecorationPosition.foreground &&
      w.decoration is BoxDecoration &&
      ((w.decoration as BoxDecoration).border?.top.width ?? 0) == 2,
);

AuthRepository _repo() => AuthRepository(
  dio: Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))
    ..httpClientAdapter = _NoNetwork(),
  tokenStore: InMemoryTokenStore(),
);

class _NoNetwork implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<List<int>>? s,
    Future<void>? c,
  ) async => ResponseBody.fromBytes(
    utf8.encode('{}'),
    500,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
  @override
  void close({bool force = false}) {}
}

void main() {
  group('A11Y-2 desktop sidebar', () {
    testWidgets(
      'Tab / Shift+Tab traverse destinations in order; Enter and Space select',
      (tester) async {
        final selected = <int>[];
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: Row(
                children: [
                  SizedBox(
                    width: 240,
                    child: DesktopSidebar(
                      destinations: _dest,
                      selectedIndex: 0,
                      onSelect: selected.add,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        expect(
          await _tabUntil(tester, 'Today'),
          greaterThan(0),
          reason: 'first destination reachable',
        );
        await _tab(tester);
        expect(
          _focused(tester, 'Students'),
          isTrue,
          reason: 'next Tab is the next destination',
        );
        await _tab(tester, shift: true);
        expect(
          _focused(tester, 'Today'),
          isTrue,
          reason: 'Shift+Tab goes back',
        );
        await _tab(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await _tab(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(selected, [
          1,
          2,
        ], reason: 'Enter on Students, Space on Fees, once each');
        handle.dispose();
      },
    );

    testWidgets(
      'one named node per destination; selected state on the active one',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: SizedBox(
                width: 240,
                child: DesktopSidebar(
                  destinations: _dest,
                  selectedIndex: 1,
                  onSelect: (_) {},
                ),
              ),
            ),
          ),
        );
        expect(find.bySemanticsLabel('Students'), findsOneWidget);
        final students = tester.getSemantics(find.bySemanticsLabel('Students'));
        expect(students.flagsCollection.isSelected, Tristate.isTrue);
        expect(students.flagsCollection.isButton, isTrue);
        expect(
          students.flagsCollection.isFocused,
          isNot(Tristate.none),
          reason: 'focusable: a web tab stop',
        );
        final today = tester.getSemantics(find.bySemanticsLabel('Today'));
        expect(today.flagsCollection.isSelected, isNot(Tristate.isTrue));
        handle.dispose();
      },
    );

    testWidgets(
      'sidebar is traversed as one group, never interleaved with the page',
      (tester) async {
        // Reproduces the browser finding: page buttons level with sidebar rows
        // were visited between them (reading-order bands across both columns).
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DesktopSidebar(
                    destinations: _dest,
                    selectedIndex: 0,
                    onSelect: (_) {},
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        const SizedBox(height: 40),
                        AppButton(label: 'Page A', onPressed: () {}),
                        const SizedBox(height: 8),
                        AppButton(label: 'Page B', onPressed: () {}),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        final order = <String>[];
        for (var i = 0; i < 6; i++) {
          await _tab(tester);
          for (final l in [
            'Today',
            'Students',
            'Fees',
            'More',
            'Page A',
            'Page B',
          ]) {
            final hit = l.startsWith('Page')
                ? _primaryIn(tester, find.widgetWithText(AppButton, l))
                : _focused(tester, l);
            if (hit) order.add(l);
          }
        }
        expect(order, [
          'Today',
          'Students',
          'Fees',
          'More',
          'Page A',
          'Page B',
        ]);
        handle.dispose();
      },
    );

    testWidgets('hidden destinations are not in the tab order', (tester) async {
      final handle = tester.ensureSemantics();
      // The router passes only the destinations this account may see.
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: SizedBox(
              width: 240,
              child: DesktopSidebar(
                destinations: _dest.take(2).toList(),
                selectedIndex: 0,
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Fees'), findsNothing);
      expect(await _tabUntil(tester, 'Fees', max: 6), 0);
      handle.dispose();
    });

    for (final dark in [false, true]) {
      testWidgets(
        'focus ring on keyboard focus only (${dark ? 'dark' : 'light'})',
        (tester) async {
          final handle = tester.ensureSemantics();
          await tester.pumpWidget(
            _app(
              Scaffold(
                body: SizedBox(
                  width: 240,
                  child: DesktopSidebar(
                    destinations: _dest,
                    selectedIndex: 0,
                    onSelect: (_) {},
                  ),
                ),
              ),
              dark: dark,
            ),
          );
          expect(_ring(), findsNothing);
          await _tabUntil(tester, 'Students');
          expect(_ring(), findsOneWidget);
          handle.dispose();
        },
      );
    }

    testWidgets('a tap still selects and leaves no ring', (tester) async {
      final selected = <int>[];
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: SizedBox(
              width: 240,
              child: DesktopSidebar(
                destinations: _dest,
                selectedIndex: 0,
                onSelect: selected.add,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Fees'));
      await tester.pump();
      expect(selected, [2]);
      expect(_ring(), findsNothing);
    });
  });

  group('A11Y-2 mobile bottom navigation', () {
    for (final width in [320.0, 390.0]) {
      testWidgets(
        '${width.toInt()} px: destinations reachable, Enter and Space select',
        (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final selected = <int>[];
          final handle = tester.ensureSemantics();
          await tester.pumpWidget(
            _app(
              Scaffold(
                bottomNavigationBar: BottomNav(
                  destinations: _dest,
                  selectedIndex: 0,
                  onSelect: selected.add,
                ),
              ),
              size: Size(width, 844),
            ),
          );
          expect(tester.takeException(), isNull);
          expect(await _tabUntil(tester, 'Students'), greaterThan(0));
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(await _tabUntil(tester, 'More'), greaterThan(0));
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pump();
          expect(selected, [1, 3]);
          final today = tester.getSemantics(find.bySemanticsLabel('Today'));
          expect(today.flagsCollection.isSelected, Tristate.isTrue);
          handle.dispose();
        },
      );
    }
  });

  group('A11Y-2 phone drawer', () {
    testWidgets(
      'opening moves focus into the drawer; items reachable; Escape closes and restores',
      (tester) async {
        final selected = <int>[];
        final handle = tester.ensureSemantics();
        final key = GlobalKey<ScaffoldState>();
        await tester.pumpWidget(
          _app(
            Scaffold(
              key: key,
              drawer: PhoneNavDrawer(
                destinations: _dest,
                selectedIndex: 0,
                onSelect: selected.add,
              ),
              body: Builder(
                builder: (context) => AppButton(
                  label: 'Open menu',
                  onPressed: () => key.currentState!.openDrawer(),
                ),
              ),
            ),
            size: const Size(390, 844),
          ),
        );
        expect(await _tabUntil(tester, 'Open menu'), greaterThan(0));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(key.currentState!.isDrawerOpen, isTrue);
        expect(
          await _tabUntil(tester, 'Fees'),
          greaterThan(0),
          reason: 'drawer items reachable',
        );
        // Focus is scoped to the open drawer: Tab never lands on the page behind.
        for (var i = 0; i < 8; i++) {
          await _tab(tester);
          expect(
            _primaryIn(tester, find.byType(AppButton)),
            isFalse,
            reason: 'no focus behind the modal drawer',
          );
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(key.currentState!.isDrawerOpen, isFalse);
        expect(
          _primaryIn(tester, find.byType(AppButton)),
          isTrue,
          reason: 'focus returns to the opener',
        );
        handle.dispose();
      },
    );

    testWidgets('Enter on a drawer item selects it once', (tester) async {
      final selected = <int>[];
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: PhoneNavDrawer(
              destinations: _dest,
              selectedIndex: 2,
              onSelect: selected.add,
            ),
          ),
          size: const Size(390, 844),
        ),
      );
      expect(await _tabUntil(tester, 'Students'), greaterThan(0));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selected, [1]);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Fees'))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      handle.dispose();
    });
  });

  group('A11Y-2 mobile app bar', () {
    testWidgets('menu and notifications are reachable and activate', (
      tester,
    ) async {
      var menu = 0;
      var bell = 0;
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          Scaffold(
            appBar: MobileAppBar(
              institutionName: 'Rehearsal Academy',
              syncStatus: const SyncStatus.synced(),
              hasUnreadNotifications: true,
              onMenuTap: () => menu++,
              onNotificationsTap: () => bell++,
            ),
          ),
          size: const Size(390, 844),
        ),
      );
      expect(
        await _tabUntil(tester, 'Notifications, unread'),
        greaterThan(0),
        reason: 'bell reachable',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(bell, 1);
      expect(
        find.bySemanticsLabel('Notifications, unread'),
        findsOneWidget,
        reason: 'one named node',
      );
      var menuReached = false;
      for (var i = 0; i < 4 && !menuReached; i++) {
        await _tab(tester, shift: true);
        menuReached = _primaryIn(tester, find.byType(IconButton));
      }
      expect(
        menuReached,
        isTrue,
        reason: 'menu (Material IconButton) reachable',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(menu, 1);
      handle.dispose();
    });
  });

  group('A11Y-3 login password visibility toggle', () {
    testWidgets(
      'reachable from the password field; Enter/Space toggle; label follows the action',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: LoginScreen(repository: _repo(), onSignedIn: () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final password = find.byWidgetPredicate(
          (w) => w is EditableText && w.obscureText,
        );
        expect(password, findsOneWidget, reason: 'starts hidden');
        await tester.enterText(password, 'not-a-real-secret');
        await tester.pump();
        expect(
          await _tabUntil(tester, 'Show password', max: 6),
          greaterThan(0),
          reason: 'toggle reachable by Tab',
        );
        expect(_ring(), findsWidgets, reason: 'keyboard focus is visible');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(
          find.bySemanticsLabel('Hide password'),
          findsOneWidget,
          reason: 'label now names the next action',
        );
        expect(find.bySemanticsLabel('Show password'), findsNothing);
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText).last)
              .obscureText,
          isFalse,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(find.bySemanticsLabel('Show password'), findsOneWidget);
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText).last)
              .obscureText,
          isTrue,
        );
        // The password value never appears in any semantics label.
        expect(
          find.bySemanticsLabel(RegExp('not-a-real-secret')),
          findsNothing,
        );
        handle.dispose();
      },
    );
  });

  group('A11Y-4 hub step rows (Setup / Fees hubs)', () {
    testWidgets(
      'a step is reachable by Tab, runs with Enter and Space; a blocked step is not focusable',
      (tester) async {
        var opened = 0;
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: ListView(
                children: [
                  StepRow(
                    number: 1,
                    title: 'Fee heads',
                    detail: 'What you charge for.',
                    onTap: () => opened++,
                  ),
                  const StepRow(
                    number: 2,
                    title: 'Fee plans',
                    detail: 'Needs fee heads.',
                    blockedReason: 'Add a fee head first',
                  ),
                  SetupRow(title: 'Grade 6', onTap: () => opened++),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(await _tabUntil(tester, 'Fee heads'), greaterThan(0));
        expect(
          find.bySemanticsLabel('Fee heads'),
          findsOneWidget,
          reason: 'one named node',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(opened, 1);
        expect(
          await _tabUntil(tester, 'Grade 6', max: 4),
          greaterThan(0),
          reason: 'blocked step skipped',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(opened, 2);
        handle.dispose();
      },
    );
  });

  testWidgets('AppButton regression: still reachable and activates once', (
    tester,
  ) async {
    var n = 0;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Center(
            child: AppButton(label: 'Save', onPressed: () => n++),
          ),
        ),
      ),
    );
    await _tab(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(n, 1);
  });
}
