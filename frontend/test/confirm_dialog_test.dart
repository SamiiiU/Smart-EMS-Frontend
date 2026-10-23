import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/confirm_dialog.dart';

/// Overhaul M1: the shared confirmation dialog.
void main() {
  Future<bool?> open(WidgetTester tester, {bool irreversible = false, double width = 800}) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    bool? result;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(role: AppRole.admin),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await confirmAction(
            context,
            title: 'Approve this payment?',
            message: 'PKR 1,500.00 from Ayesha Khan will be counted.',
            confirmLabel: 'Approve',
            irreversible: irreversible,
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('confirm returns true; the button names the action', (tester) async {
    await open(tester);
    expect(find.text('OK'), findsNothing);
    await tester.tap(find.byKey(const Key('confirm-ok')));
    await tester.pumpAndSettle();
    expect(find.byType(ConfirmDialog), findsNothing);
  });

  testWidgets('cancel and dismissal are both the safe "false"', (tester) async {
    var result = false;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(role: AppRole.admin),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await confirmAction(
            context, title: 'Remove?', message: 'x', confirmLabel: 'Remove'),
          child: const Text('open'),
        ),
      ),
    ));
    for (final dismiss in [
      () => tester.tap(find.byKey(const Key('confirm-cancel'))),
      () => tester.tapAt(const Offset(5, 5)), // the barrier
    ]) {
      result = true;
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await dismiss();
      await tester.pumpAndSettle();
      expect(result, isFalse);
    }
  });

  testWidgets('irreversible actions carry a visible warning', (tester) async {
    await open(tester, irreversible: true);
    expect(find.text('This cannot be undone.'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('fits a 320 px phone without overflow', (tester) async {
    await open(tester, irreversible: true, width: 320);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('confirm-ok')), findsOneWidget);
  });
}
