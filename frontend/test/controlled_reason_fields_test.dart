import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/app_button.dart';
import 'package:smartems/features/finance/domain/money.dart';
import 'package:smartems/features/finance/presentation/discount_requests_screen.dart';
import 'package:smartems/features/finance/presentation/reject_payment_dialog.dart';

/// DEF-12/13: reason fields must keep what the user typed across rebuilds (keystroke by keystroke).
Future<void> typeSlowly(WidgetTester tester, Finder field, String text) async {
  for (var i = 1; i <= text.length; i++) {
    final editable = find.descendant(of: field, matching: find.byType(EditableText));
    final current = tester.widget<EditableText>(editable).controller.text;
    await tester.enterText(editable, current + text[i - 1]); // append one character, like real typing
    await tester.pump();
  }
}

void main() {
  Widget host(Widget dialog) => MaterialApp(theme: AppTheme.light(role: AppRole.admin), home: Scaffold(body: dialog));

  testWidgets('payment rejection reason keeps typed text and enables Reject', (tester) async {
    await tester.pumpWidget(host(RejectPaymentDialog(amount: Money.parse('1000.00'), studentName: 'Synthetic')));
    await typeSlowly(tester, find.byKey(const Key('reject-reason')), 'Challan not found');
    final editable = find.descendant(of: find.byKey(const Key('reject-reason')), matching: find.byType(EditableText));
    expect(tester.widget<EditableText>(editable).controller.text, 'Challan not found');
    expect(tester.widget<AppButton>(find.byKey(const Key('reject-confirm'))).onPressed, isNotNull);
  });

  testWidgets('discount rejection reason keeps typed text', (tester) async {
    await tester.pumpWidget(host(const DiscountDecisionDialog(approve: false, value: 'PKR 100.00')));
    await typeSlowly(tester, find.byKey(const Key('discount-reject-reason')), 'Not eligible');
    final editable = find.descendant(of: find.byKey(const Key('discount-reject-reason')), matching: find.byType(EditableText));
    expect(tester.widget<EditableText>(editable).controller.text, 'Not eligible');
  });
}
