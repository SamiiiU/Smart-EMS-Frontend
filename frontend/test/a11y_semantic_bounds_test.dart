import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/adaptive_data_view.dart';
import 'package:smartems/core/widgets/app_button.dart';
import 'package:smartems/core/widgets/section_card.dart';

/// Release blockers (Academy B5 reports 07/09): an AppButton inside a card or a
/// table row must be its OWN accessibility node — own name, own bounds — not merged
/// into the card/row node (which gave an unnamed, card/row-sized "button").
Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.light(role: AppRole.admin),
  home: Scaffold(body: child),
);

/// The semantics node that carries [label] with the button flag, or null.
SemanticsNode? _buttonNode(WidgetTester tester, String label) {
  SemanticsNode? found;
  void visit(SemanticsNode n) {
    final d = n.getSemanticsData();
    if (d.flagsCollection.isButton && d.label == label) found = n;
    n.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  var root = tester.getSemantics(find.byType(Scaffold));
  while (root.parent != null) {
    root = root.parent!;
  }
  visit(root);
  return found;
}

Rect _globalRect(WidgetTester tester, SemanticsNode node) {
  var rect = node.rect;
  SemanticsNode? n = node;
  while (n != null) {
    final t = n.transform;
    if (t != null) rect = MatrixUtils.transformRect(t, rect);
    n = n.parent;
  }
  return rect;
}

void main() {
  testWidgets(
    'a button inside a SectionCard is its own named node with the button\'s bounds',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(
        _app(
          Padding(
            padding: const EdgeInsets.all(16),
            child: SectionCard(
              title: 'Fee terms',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tuition: PKR 3,000.00'),
                  const Text('Billed monthly'),
                  AppButton(
                    label: 'Schedule price change',
                    variant: AppButtonVariant.secondary,
                    onPressed: () => taps++,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final node = _buttonNode(tester, 'Schedule price change');
      expect(
        node,
        isNotNull,
        reason: 'button must be announced with its own name',
      );
      final semantic = _globalRect(tester, node!);
      final drawn = tester.getRect(find.byType(AppButton));
      expect(
        semantic.width,
        closeTo(drawn.width, 1.0),
        reason: 'semantic bounds = the button, not the card',
      );
      expect(semantic.height, closeTo(drawn.height, 1.0));
      expect(semantic.center.dx, closeTo(drawn.center.dx, 1.0));
      // The card itself is not a button.
      final card = tester.getSemantics(find.text('Tuition: PKR 3,000.00'));
      expect(
        card.getSemanticsData().flagsCollection.isButton,
        isFalse,
        reason: 'no card-wide click target',
      );
      // Activation through the accessibility action and by pointer inside the node's bounds.
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pump();
      await tester.tapAt(semantic.topLeft + const Offset(4, 4));
      await tester.pump();
      expect(taps, 2);
      handle.dispose();
    },
  );

  testWidgets('a table row action is its own named node, not the whole row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();
    var opened = 0;
    await tester.pumpWidget(
      _app(
        AdaptiveDataView<String>(
          rows: const ['2026-10-14'],
          semanticLabel: (r) => 'Session $r',
          columns: [DataColumnSpec(label: 'Date', value: (r) => r)],
          rowActions: [
            RowAction<String>(label: 'Attendance', onPressed: (_) => opened++),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final node = _buttonNode(tester, 'Attendance, Session 2026-10-14');
    expect(
      node,
      isNotNull,
      reason: 'row action announced with its action + row name',
    );
    final semantic = _globalRect(tester, node!);
    final drawn = tester.getRect(find.byType(AppButton));
    expect(
      semantic.width,
      closeTo(drawn.width, 1.0),
      reason: 'semantic bounds = the action button, not the row',
    );
    expect(semantic.left, closeTo(drawn.left, 1.0));
    await tester.tapAt(semantic.topLeft + const Offset(4, 4));
    await tester.pump();
    expect(
      opened,
      1,
      reason: 'a click anywhere inside the announced area runs the action',
    );
    handle.dispose();
  });

  testWidgets('keyboard: Tab reaches the card button and Enter activates it', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      _app(
        SectionCard(
          title: 'Profile',
          child: AppButton(
            label: 'Change',
            size: AppButtonSize.sm,
            onPressed: () => taps++,
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final node = _buttonNode(tester, 'Change');
    expect(node?.getSemanticsData().flagsCollection.isFocused, Tristate.isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);
    handle.dispose();
  });
}
