import 'dart:async';

import 'package:flutter/material.dart';
import 'dart:ui' show Tristate;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/sizing.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/adaptive_data_view.dart';
import 'package:smartems/core/widgets/app_button.dart';

/// M5: optional per-row actions on the shared data view (e.g. Approve / Reject
/// on pending payments) in both the table and the card layout.
typedef _Row = ({String id, String name, String amount, bool locked});

const _rows = <_Row>[
  (id: 'p1', name: 'Ayesha Khan', amount: 'PKR 5,000.00', locked: false),
  (id: 'p2', name: 'Bilal Ahmed', amount: 'PKR 2,500.00', locked: true),
];

class _Log {
  final opened = <String>[];
  final approved = <String>[];
  final rejected = <String>[];
}

Future<_Log> _pump(
  WidgetTester tester,
  double width, {
  List<RowAction<_Row>>? actions,
  TargetPlatform? platform,
  bool withActions = true,
}) async {
  final log = _Log();
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(role: AppRole.admin).copyWith(platform: platform),
    home: Scaffold(
      body: AdaptiveDataView<_Row>(
        rows: _rows,
        semanticLabel: (r) => '${r.name}, ${r.amount}',
        onTap: (r) => log.opened.add(r.id),
        columns: [
          DataColumnSpec(label: 'Learner', value: (r) => r.name, flex: 3),
          DataColumnSpec(label: 'Amount', value: (r) => r.amount, flex: 2, numeric: true),
        ],
        rowActions: !withActions
            ? const []
            : actions ??
                [
                  RowAction<_Row>(
                    label: 'Approve',
                    icon: Icons.check,
                    variant: AppButtonVariant.primary,
                    key: (r) => Key('approve-${r.id}'),
                    onPressed: (r) => log.approved.add(r.id),
                    isEnabled: (r) => !r.locked,
                    disabledReason: (r) => r.locked ? 'Already being reviewed by someone else' : null,
                  ),
                  RowAction<_Row>(
                    label: 'Reject',
                    key: (r) => Key('reject-${r.id}'),
                    onPressed: (r) => log.rejected.add(r.id),
                  ),
                ],
      ),
    ),
  ));
  await tester.pump();
  return log;
}

void main() {
  for (final width in [320.0, 390.0, 768.0, 1024.0, 1440.0]) {
    testWidgets('${width.toInt()} px: actions render without overflow', (tester) async {
      await _pump(tester, width);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('approve-p1')), findsOneWidget);
      expect(find.byKey(const Key('reject-p1')), findsOneWidget);
      if (width >= AdaptiveDataView.tableBreakpoint) {
        expect(find.text('Actions'), findsOneWidget, reason: 'one header for the actions column');
      } else {
        expect(find.text('Actions'), findsNothing, reason: 'cards need no column header');
      }
    });
  }

  for (final width in [390.0, 1024.0]) {
    testWidgets('${width.toInt()} px: an action never opens the row; the row still opens', (tester) async {
      final log = await _pump(tester, width);
      await tester.tap(find.byKey(const Key('approve-p1')));
      await tester.pump();
      expect(log.approved, ['p1']);
      expect(log.opened, isEmpty, reason: 'action taps must not navigate');

      await tester.tap(find.text('Ayesha Khan'));
      await tester.pump();
      expect(log.opened, ['p1']);
      expect(log.approved, ['p1']);
    });
  }

  testWidgets('disabled: no call, reason exposed as hint and tooltip', (tester) async {
    final log = await _pump(tester, 1024);
    await tester.tap(find.byKey(const Key('approve-p2')), warnIfMissed: false);
    await tester.pump();
    expect(log.approved, isEmpty);
    expect(log.opened, isEmpty);
    // The accessible node is the button itself (its own semantics container),
    // not the keyed wrapper around it.
    final node = tester.getSemantics(find.descendant(of: find.byKey(const Key('approve-p2')), matching: find.byType(AppButton)));
    expect(node.hint, 'Already being reviewed by someone else');
    expect(node.flagsCollection.isEnabled, Tristate.isFalse);
    expect(find.byTooltip('Already being reviewed by someone else'), findsOneWidget);
  });

  testWidgets('permission-restricted: isVisible false hides the action for that row only', (tester) async {
    await _pump(tester, 390, actions: [
      RowAction<_Row>(
        label: 'Approve',
        key: (r) => Key('approve-${r.id}'),
        onPressed: (_) {},
        isVisible: (r) => !r.locked,
      ),
    ]);
    expect(find.byKey(const Key('approve-p1')), findsOneWidget);
    expect(find.byKey(const Key('approve-p2')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading: screen-reported loading shows progress label and blocks taps', (tester) async {
    final calls = <String>[];
    await _pump(tester, 1024, actions: [
      RowAction<_Row>(
        label: 'Approve',
        loadingLabel: 'Approving…',
        key: (r) => Key('approve-${r.id}'),
        onPressed: (r) => calls.add(r.id),
        isLoading: (r) => r.id == 'p1',
      ),
    ]);
    expect(find.text('Approving…'), findsOneWidget);
    await tester.tap(find.byKey(const Key('approve-p1')), warnIfMissed: false);
    await tester.pump();
    expect(calls, isEmpty);
  });

  testWidgets('async action: a double tap runs it once, then re-enables', (tester) async {
    final completer = Completer<void>();
    var calls = 0;
    await _pump(tester, 1024, actions: [
      RowAction<_Row>(
        label: 'Approve',
        key: (r) => Key('approve-${r.id}'),
        onPressed: (_) {
          calls++;
          return completer.future;
        },
      ),
    ]);
    await tester.tap(find.byKey(const Key('approve-p1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('approve-p1')), warnIfMissed: false);
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Approve…'), findsOneWidget, reason: 'default in-flight label');

    completer.complete();
    await tester.pumpAndSettle();
    expect(find.text('Approve…'), findsNothing);
    await tester.tap(find.byKey(const Key('approve-p1')));
    await tester.pump();
    expect(calls, 2);
  });

  testWidgets('accessibility: each action is its own named button, separate from the row', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, 390);
    expect(
      find.bySemanticsLabel('Approve, Ayesha Khan, PKR 5,000.00'),
      findsOneWidget,
      reason: 'default name says which row the action is for',
    );
    expect(find.bySemanticsLabel('Ayesha Khan, PKR 5,000.00'), findsOneWidget,
        reason: 'the row keeps its own single label');
    final node = tester.getSemantics(find.byKey(const Key('reject-p1')));
    expect(node.flagsCollection.isButton, isTrue);
    handle.dispose();
  });

  testWidgets('touch targets: at least the minimum on a touch platform', (tester) async {
    await _pump(tester, 390, platform: TargetPlatform.android);
    for (final key in ['approve-p1', 'reject-p1']) {
      final size = tester.getSize(find.byKey(Key(key)));
      expect(size.height, greaterThanOrEqualTo(AppSizing.touchTargetMin), reason: key);
      expect(size.width, greaterThanOrEqualTo(AppSizing.touchTargetMin), reason: key);
    }
  });

  testWidgets('keyboard: an action is reachable with Tab and runs with Enter', (tester) async {
    final log = await _pump(tester, 1024);
    final target = find.byKey(const Key('reject-p1'));
    var reached = false;
    for (var i = 0; i < 20 && !reached; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus?.context;
      reached = focused != null &&
          find.descendant(of: target, matching: find.byWidgetPredicate((w) => identical(w, focused.widget))).evaluate().isNotEmpty;
    }
    expect(reached, isTrue, reason: 'Reject must be in the focus order');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(log.rejected, ['p1']);
    expect(log.opened, isEmpty);
  });

  for (final width in [390.0, 1024.0]) {
    testWidgets('${width.toInt()} px backward compatible: no actions column or bar', (tester) async {
      await _pump(tester, width, withActions: false);
      expect(find.text('Actions'), findsNothing);
      expect(find.byType(AppButton), findsNothing);
    });
  }
}
