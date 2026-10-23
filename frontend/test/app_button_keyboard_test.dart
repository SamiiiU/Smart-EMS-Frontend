import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/adaptive_data_view.dart';
import 'package:smartems/core/widgets/app_button.dart';
import 'package:smartems/core/widgets/app_sheet.dart';
import 'package:smartems/core/widgets/confirm_dialog.dart';

/// Keyboard accessibility of the shared AppButton (M1 accessibility finding):
/// every enabled button must be reachable with Tab / Shift+Tab, activate once
/// with Enter or Space, show a visible keyboard focus ring, and stay inert when
/// disabled.

Widget _app(Widget child, {bool dark = false}) => MaterialApp(
      theme: dark ? AppTheme.dark(role: AppRole.admin) : AppTheme.light(role: AppRole.admin),
      home: Scaffold(body: Center(child: child)),
    );

/// The FocusNode currently holding primary focus belongs to [finder]'s subtree.
bool _hasFocus(WidgetTester tester, Finder finder) {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  final target = tester.element(finder);
  var found = false;
  ctx.visitAncestorElements((e) {
    if (identical(e, target)) found = true;
    return !found;
  });
  return found || identical(ctx, target);
}

/// The keyboard focus ring is a 2 px foreground border.
Finder _ring(Finder within) => find.descendant(
      of: within,
      matching: find.byWidgetPredicate((w) =>
          w is DecoratedBox &&
          w.position == DecorationPosition.foreground &&
          w.decoration is BoxDecoration &&
          ((w.decoration as BoxDecoration).border?.top.width ?? 0) == 2),
    );

Future<void> _tab(WidgetTester tester, {bool shift = false}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

void main() {
  for (final variant in AppButtonVariant.values) {
    testWidgets('${variant.name}: Tab / Shift+Tab traverse adjacent buttons in order', (tester) async {
      await tester.pumpWidget(_app(Row(mainAxisSize: MainAxisSize.min, children: [
        AppButton(key: const Key('a'), label: 'First', variant: variant, onPressed: () {}),
        AppButton(key: const Key('b'), label: 'Second', variant: variant, onPressed: () {}),
        AppButton(key: const Key('c'), label: 'Third', variant: variant, onPressed: () {}),
      ])));
      await _tab(tester);
      expect(_hasFocus(tester, find.byKey(const Key('a'))), isTrue);
      await _tab(tester);
      expect(_hasFocus(tester, find.byKey(const Key('b'))), isTrue);
      await _tab(tester);
      expect(_hasFocus(tester, find.byKey(const Key('c'))), isTrue);
      await _tab(tester, shift: true);
      expect(_hasFocus(tester, find.byKey(const Key('b'))), isTrue);
    });

    testWidgets('${variant.name}: Enter and Space each activate exactly once', (tester) async {
      var presses = 0;
      await tester.pumpWidget(_app(AppButton(key: const Key('a'), label: 'Save', variant: variant, onPressed: () => presses++)));
      await _tab(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(presses, 1, reason: 'Enter: one activation, not two');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(presses, 2, reason: 'Space: one activation');
    });
  }

  testWidgets('disabled: skipped by Tab and inert to keyboard, mouse and touch', (tester) async {
    var presses = 0;
    await tester.pumpWidget(_app(Row(mainAxisSize: MainAxisSize.min, children: [
      const AppButton(key: Key('off'), label: 'Disabled'),
      AppButton(key: const Key('on'), label: 'Enabled', onPressed: () => presses++),
    ])));
    await _tab(tester);
    expect(_hasFocus(tester, find.byKey(const Key('off'))), isFalse);
    expect(_hasFocus(tester, find.byKey(const Key('on'))), isTrue);
    await tester.tap(find.byKey(const Key('off')));
    await tester.pump();
    expect(presses, 0);
    final semantics = tester.getSemantics(find.byKey(const Key('off')));
    expect(semantics.flagsCollection.isButton, isTrue);
  });

  testWidgets('loading pattern: onPressed null while submitting blocks a second activation', (tester) async {
    var presses = 0;
    var submitting = false;
    await tester.pumpWidget(_app(StatefulBuilder(builder: (context, setState) {
      return AppButton(
        key: const Key('a'),
        label: submitting ? 'Saving…' : 'Save',
        onPressed: submitting
            ? null
            : () {
                presses++;
                setState(() => submitting = true);
              },
      );
    })));
    await _tab(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(presses, 1);
    expect(find.text('Saving…'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets('focus ring: shown for keyboard focus only (${dark ? 'dark' : 'light'})', (tester) async {
      await tester.pumpWidget(_app(AppButton(key: const Key('a'), label: 'Save', onPressed: () {}), dark: dark));
      final button = find.byKey(const Key('a'));
      expect(_ring(button), findsNothing, reason: 'no ring before focus');
      await _tab(tester);
      expect(_ring(button), findsOneWidget, reason: 'ring visible after Tab');
      final ctx = tester.element(button);
      final ring = tester.widget<DecoratedBox>(_ring(button));
      expect((ring.decoration as BoxDecoration).border!.top.color, ctx.tokens.primaryAccent);
    });
  }

  testWidgets('focus ring: not shown when activated by touch/mouse', (tester) async {
    await tester.pumpWidget(_app(AppButton(key: const Key('a'), label: 'Save', onPressed: () {})));
    await tester.tap(find.byKey(const Key('a')));
    await tester.pump();
    expect(_ring(find.byKey(const Key('a'))), findsNothing);
  });

  testWidgets('semantics: one named button, no duplicated label, keeps tap action', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(AppButton(key: const Key('a'), label: 'Sign in', onPressed: () {})));
    expect(find.bySemanticsLabel('Sign in'), findsOneWidget);
    expect(find.bySemanticsLabel('Sign in Sign in'), findsNothing);
    final node = tester.getSemantics(find.byKey(const Key('a')));
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });

  testWidgets('web tab stop: the button node is focusable, and focused after Tab', (tester) async {
    // Flutter Web only makes focusable semantics nodes DOM tab stops; without
    // these flags Chromium's Tab skipped every AppButton (seen in the browser).
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(Row(mainAxisSize: MainAxisSize.min, children: [
      AppButton(key: const Key('a'), label: 'Save', onPressed: () {}),
      const AppButton(key: Key('off'), label: 'Disabled'),
    ])));
    var node = tester.getSemantics(find.byKey(const Key('a')));
    expect(node.flagsCollection.isFocused, isNot(Tristate.none), reason: "focusable");
    expect(tester.getSemantics(find.byKey(const Key('off'))).flagsCollection.isFocused, Tristate.none,
        reason: 'disabled is not a tab stop');
    await _tab(tester);
    node = tester.getSemantics(find.byKey(const Key('a')));
    expect(node.flagsCollection.isFocused, Tristate.isTrue);
    expect(node.label, 'Save');
    handle.dispose();
  });

  testWidgets('optional semanticsLabel / semanticsHint replace the name on the same node', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(const AppButton(
      key: Key('a'),
      label: 'Approve',
      semanticsLabel: 'Approve, Ayesha Khan',
      semanticsHint: 'Already being reviewed',
    )));
    final node = tester.getSemantics(find.byKey(const Key('a')));
    expect(node.label, 'Approve, Ayesha Khan');
    expect(node.hint, 'Already being reviewed');
    expect(find.bySemanticsLabel('Approve'), findsNothing, reason: 'no second, shorter node');
    handle.dispose();
  });

  testWidgets('form: Tab moves from a field to the submit button, Enter submits', (tester) async {
    var submitted = 0;
    await tester.pumpWidget(_app(SizedBox(
      width: 300,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const TextField(key: Key('field')),
        AppButton(key: const Key('submit'), label: 'Submit', onPressed: () => submitted++),
      ]),
    )));
    await tester.tap(find.byKey(const Key('field')));
    await tester.pump();
    await _tab(tester);
    expect(_hasFocus(tester, find.byKey(const Key('submit'))), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(submitted, 1);
  });

  testWidgets('dialog: buttons are reachable and Enter runs the focused one only', (tester) async {
    var confirmed = 0;
    var cancelled = 0;
    await tester.pumpWidget(_app(Builder(
      builder: (context) => AppButton(
        key: const Key('open'),
        label: 'Open',
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(actions: [
            AppButton(key: const Key('cancel'), label: 'Cancel', variant: AppButtonVariant.ghost, onPressed: () => cancelled++),
            AppButton(key: const Key('ok'), label: 'Confirm', onPressed: () => confirmed++),
          ]),
        ),
      ),
    )));
    await _tab(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ok')), findsOneWidget);
    for (var i = 0; i < 6 && !_hasFocus(tester, find.byKey(const Key('ok'))); i++) {
      await _tab(tester);
    }
    expect(_hasFocus(tester, find.byKey(const Key('ok'))), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(confirmed, 1);
    expect(cancelled, 0);
  });

  testWidgets('sheet: focus moves in on open; Escape closes; focus returns to the opener', (tester) async {
    var done = 0;
    await tester.pumpWidget(_app(Builder(
      builder: (context) => AppButton(
        key: const Key('open'),
        label: 'Details',
        onPressed: () => showAppSheet<void>(
          context,
          title: 'Details',
          builder: (_) => AppButton(key: const Key('done'), label: 'Done', onPressed: () => done++),
        ),
      ),
    )));
    await _tab(tester);
    expect(_hasFocus(tester, find.byKey(const Key('open'))), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('done')), findsOneWidget);
    expect(_hasFocus(tester, find.byKey(const Key('open'))), isFalse, reason: 'focus is inside the sheet');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('done')), findsNothing);
    expect(_hasFocus(tester, find.byKey(const Key('open'))), isTrue, reason: 'restored to the opener');
    expect(done, 0);
  });

  testWidgets('dialog: Escape on a confirmAction returns focus to its opener', (tester) async {
    await tester.pumpWidget(_app(Builder(
      builder: (context) => AppButton(
        key: const Key('open'),
        label: 'Delete',
        onPressed: () => confirmAction(context, title: 'Sure?', message: 'x', confirmLabel: 'Delete'),
      ),
    )));
    await _tab(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Sure?'), findsOneWidget);
    expect(_hasFocus(tester, find.byKey(const Key('confirm-cancel'))), isTrue, reason: 'focus on Cancel');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Sure?'), findsNothing);
    expect(_hasFocus(tester, find.byKey(const Key('open'))), isTrue);
  });

  testWidgets('sheet: a button in an app sheet is reachable and activates', (tester) async {
    var done = 0;
    await tester.pumpWidget(_app(Builder(
      builder: (context) => AppButton(
        key: const Key('open'),
        label: 'Details',
        onPressed: () => showAppSheet<void>(
          context,
          title: 'Details',
          builder: (_) => AppButton(key: const Key('done'), label: 'Done', onPressed: () => done++),
        ),
      ),
    )));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 6 && !_hasFocus(tester, find.byKey(const Key('done'))); i++) {
      await _tab(tester);
    }
    expect(_hasFocus(tester, find.byKey(const Key('done'))), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(done, 1);
  });

  for (final width in [320.0, 390.0, 768.0, 1024.0, 1440.0]) {
    testWidgets('${width.toInt()} px adaptive layout: row actions reachable once each, Enter runs them', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final approved = <String>[];
      final opened = <String>[];
      await tester.pumpWidget(_app(AdaptiveDataView<String>(
        rows: const ['r1'],
        semanticLabel: (r) => r,
        onTap: opened.add,
        columns: [DataColumnSpec(label: 'Name', value: (r) => r)],
        rowActions: [
          RowAction<String>(label: 'Approve', key: (r) => Key('approve-$r'), onPressed: approved.add),
        ],
      )));
      expect(tester.takeException(), isNull);
      final target = find.byKey(const Key('approve-r1'));
      var stops = 0;
      for (var i = 0; i < 8; i++) {
        await _tab(tester);
        if (_hasFocus(tester, target)) stops++;
      }
      expect(stops, greaterThan(0), reason: 'reachable');
      // Exactly one focus stop per cycle: the row (1) + action (1) = cycle of 2
      // over 8 tabs means 4 visits; a duplicated node would give 8.
      expect(stops, lessThanOrEqualTo(4), reason: 'no duplicate focus node');
      for (var i = 0; i < 8 && !_hasFocus(tester, target); i++) {
        await _tab(tester);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(approved, ['r1'], reason: 'one activation');
      expect(opened, isEmpty, reason: 'the row is not opened');
    });
  }
}
