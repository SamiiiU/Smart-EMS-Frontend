import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/adaptive_data_view.dart';
import 'package:smartems/core/widgets/app_button.dart';
import 'package:smartems/features/finance/data/finance_repository.dart';
import 'package:smartems/features/finance/presentation/pending_payments_screen.dart';
import 'package:smartems/features/finance/presentation/receipt_screen.dart';

/// M5 Pending Payments on AdaptiveDataView with Approve / Reject row actions.
/// Synthetic data on a scripted HTTP transport only — no real payment is ever
/// approved or rejected. Every request is recorded so a cancelled
/// confirmation can be proven to send nothing.

const _p1 = '{"id":"pay-1","invoice_id":"inv-1","student_name":"Ali Khan","amount":1500.00,'
    '"source":"MANUAL_CASH","reference":null,"received_at":"2026-09-24T09:00:00Z"}';
const _p2 = '{"id":"pay-2","invoice_id":"inv-2","student_name":"Sara Ahmed","amount":2000.00,'
    '"source":"BANK_CHALLAN","reference":"CH-778","received_at":"2026-09-25T09:00:00Z"}';

class _Server implements HttpClientAdapter {
  final pending = <String>[_p1, _p2];
  final posts = <String>[];
  final bodies = <String>[];
  int approveStatus = 200;
  int rejectStatus = 200;
  String approveError = 'Payment exceeds the current outstanding balance';
  String rejectError = 'Payment was already processed';
  Completer<void>? hold;

  ResponseBody _raw(int status, String body) => ResponseBody.fromBytes(utf8.encode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    final path = o.uri.path;
    if (o.method == 'POST') {
      posts.add(path);
      bodies.add(o.data is String ? o.data as String : jsonEncode(o.data));
      if (hold != null) await hold!.future;
    }
    if (path == '/api/fee/payments/pending') return _raw(200, '[${pending.join(',')}]');
    if (path.endsWith('/approve')) {
      if (approveStatus != 200) return _raw(approveStatus, jsonEncode({'message': approveError}));
      pending.removeWhere((p) => p.contains('"pay-1"'));
      return _raw(200, '{"id":"pay-1","amount":1500.00,"status":"approved","receiptId":"rcp-1","receiptNumber":"RCP-2026-001"}');
    }
    if (path.endsWith('/reject')) {
      if (rejectStatus != 200) return _raw(rejectStatus, jsonEncode({'message': rejectError}));
      pending.removeWhere((p) => p.contains('"pay-2"'));
      return _raw(200, '{"id":"pay-2","status":"rejected"}');
    }
    if (path.startsWith('/api/fee/receipts/')) {
      return _raw(200, '{"id":"rcp-1","receipt_number":"RCP-2026-001","generated_at":"2026-09-24T00:13:28Z",'
          '"amount":1500.00,"source":"MANUAL_CASH","invoice_id":"inv-1","student_name":"Ali Khan"}');
    }
    return _raw(404, '{"message":"not found"}');
  }

  @override
  void close({bool force = false}) {}
}

Future<_Server> _pump(WidgetTester tester, {double width = 1440, bool canDecide = true}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final server = _Server();
  final repo = FinanceRepository(Dio(BaseOptions(baseUrl: 'https://example.invalid'))..httpClientAdapter = server);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(role: AppRole.admin),
    home: PendingPaymentsScreen(repository: repo, canDecide: canDecide),
  ));
  await tester.pumpAndSettle();
  return server;
}

void main() {
  for (final width in [320.0, 390.0, 768.0, 1024.0, 1440.0]) {
    testWidgets('${width.toInt()} px: no overflow; amounts, learners, methods; actions present', (tester) async {
      await _pump(tester, width: width);
      expect(tester.takeException(), isNull);
      expect(find.text('PKR 1,500.00'), findsOneWidget);
      // Cards render secondary fields as one rich line ("Learner: Ali Khan").
      expect(find.textContaining('Ali Khan', findRichText: true), findsWidgets);
      expect(find.textContaining('Cash', findRichText: true), findsWidgets);
      expect(find.textContaining('CH-778', findRichText: true), findsWidgets);
      expect(find.byKey(const Key('approve-pay-1')), findsOneWidget);
      expect(find.byKey(const Key('reject-pay-2')), findsOneWidget);
      if (width >= AdaptiveDataView.tableBreakpoint) {
        expect(find.text('Actions'), findsOneWidget, reason: 'table header');
        expect(find.text('Received'), findsOneWidget);
      }
      expect(find.textContaining('None of this money is counted'), findsOneWidget);
    });
  }

  testWidgets('without permission the actions are hidden (rows still listed)', (tester) async {
    await _pump(tester, canDecide: false);
    expect(find.text('PKR 1,500.00'), findsOneWidget);
    expect(find.byKey(const Key('approve-pay-1')), findsNothing);
    expect(find.byKey(const Key('reject-pay-1')), findsNothing);
  });

  testWidgets('Approve asks first; Cancel sends nothing', (tester) async {
    final server = await _pump(tester);
    await tester.tap(find.byKey(const Key('approve-pay-1')));
    await tester.pumpAndSettle();
    expect(find.text('Approve this payment?'), findsOneWidget);
    expect(find.textContaining('no way to reverse'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(server.posts, isEmpty);
  });

  testWidgets('confirmed Approve: one request, receipt opened, list refreshed', (tester) async {
    final server = await _pump(tester);
    await tester.tap(find.byKey(const Key('approve-pay-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve').last);
    await tester.pumpAndSettle();
    expect(server.posts, ['/api/fee/payments/pay-1/approve']);
    expect(find.byType(ReceiptScreen), findsOneWidget, reason: 'the receipt the server issued');
    expect(find.text('RCP-2026-001'), findsWidgets);
    Navigator.of(tester.element(find.byType(ReceiptScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.text('PKR 1,500.00'), findsNothing, reason: 'refreshed from the server');
    expect(find.text('PKR 2,000.00'), findsOneWidget);
  });

  testWidgets('confirmation: focus starts on Cancel; Enter cancels; nothing sent; no "Approving…" yet', (tester) async {
    final server = await _pump(tester);
    await tester.tap(find.byKey(const Key('approve-pay-1')));
    await tester.pumpAndSettle();
    expect(find.text('Approving…'), findsNothing, reason: 'nothing is processed while the user decides');
    final cancel = tester.element(find.byKey(const Key('confirm-cancel')));
    final focusCtx = FocusManager.instance.primaryFocus?.context;
    var inCancel = false;
    focusCtx?.visitAncestorElements((e) {
      inCancel = identical(e, cancel);
      return !inCancel;
    });
    expect(inCancel, isTrue, reason: 'focus moved into the dialog, on the safe choice');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Approve this payment?'), findsNothing);
    expect(server.posts, isEmpty);
  });

  testWidgets('confirmation: Escape closes it and sends nothing', (tester) async {
    final server = await _pump(tester);
    await tester.tap(find.byKey(const Key('reject-pay-2')));
    await tester.pumpAndSettle();
    expect(find.text('Reject this payment?'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Reject this payment?'), findsNothing);
    expect(server.posts, isEmpty);
  });

  testWidgets('Reject now asks first; Cancel sends nothing', (tester) async {
    final server = await _pump(tester);
    await tester.tap(find.byKey(const Key('reject-pay-2')));
    await tester.pumpAndSettle();
    expect(find.text('Reject this payment?'), findsOneWidget);
    expect(find.textContaining('could not be verified'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(server.posts, isEmpty);
  });

  testWidgets('confirmed Reject: one request with the trimmed reason, success notice, refreshed', (tester) async {
    final server = await _pump(tester);
    await tester.tap(find.byKey(const Key('reject-pay-2')));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byKey(const Key('reject-reason')), matching: find.byType(TextField)), '  Challan not in bank statement  ');
    await tester.pump();
    await tester.tap(find.byKey(const Key('reject-confirm')));
    await tester.pumpAndSettle();
    expect(server.posts, ['/api/fee/payments/pay-2/reject']);
    expect(jsonDecode(server.bodies.single), {'reason': 'Challan not in bank statement'});
    expect(find.textContaining('rejected'), findsOneWidget);
    expect(find.text('PKR 2,000.00'), findsNothing);
  });

  testWidgets("server refusal is shown verbatim; nothing is assumed approved", (tester) async {
    final server = await _pump(tester)..approveStatus = 409;
    await tester.tap(find.byKey(const Key('approve-pay-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve').last);
    await tester.pumpAndSettle();
    expect(server.posts, ['/api/fee/payments/pay-1/approve']);
    expect(find.text('Payment exceeds the current outstanding balance'), findsOneWidget);
    expect(find.byType(ReceiptScreen), findsNothing);
    expect(find.text('PKR 1,500.00'), findsOneWidget, reason: 'still pending after refresh');
  });

  testWidgets('while one action runs: its row shows progress, every row is disabled', (tester) async {
    final server = await _pump(tester);
    server.hold = Completer<void>();
    await tester.tap(find.byKey(const Key('approve-pay-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Approving…'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reject-pay-2')), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Reject this payment?'), findsNothing, reason: 'other rows disabled');
    expect(server.posts, ['/api/fee/payments/pay-1/approve']);
    server.hold!.complete();
    await tester.pumpAndSettle();
  });

  group('rejection reason (required)', () {
    Finder reasonField() => find.descendant(of: find.byKey(const Key('reject-reason')), matching: find.byType(TextField));
    bool confirmEnabled(WidgetTester tester) =>
        tester.widget<AppButton>(find.byKey(const Key('reject-confirm'))).onPressed != null;

    testWidgets('Reject stays disabled for empty, whitespace-only or too-short reasons', (tester) async {
      final server = await _pump(tester);
      await tester.tap(find.byKey(const Key('reject-pay-2')));
      await tester.pumpAndSettle();
      expect(confirmEnabled(tester), isFalse, reason: 'empty');
      await tester.enterText(reasonField(), '      ');
      await tester.pump();
      expect(confirmEnabled(tester), isFalse, reason: 'whitespace only');
      await tester.enterText(reasonField(), ' ab ');
      await tester.pump();
      expect(confirmEnabled(tester), isFalse, reason: 'too short');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(server.posts, isEmpty, reason: 'Enter in the field cannot submit an invalid reason');
      await tester.enterText(reasonField(), 'Duplicate');
      await tester.pump();
      expect(confirmEnabled(tester), isTrue);
    });

    testWidgets('focus starts in the reason field; Escape closes; nothing sent', (tester) async {
      final server = await _pump(tester);
      await tester.tap(find.byKey(const Key('reject-pay-2')));
      await tester.pumpAndSettle();
      final editable = tester.widget<EditableText>(find.descendant(of: find.byKey(const Key('reject-reason')), matching: find.byType(EditableText)));
      expect(editable.focusNode.hasFocus, isTrue, reason: 'focus inside the dialog');
      await tester.enterText(reasonField(), 'Typed but cancelled');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Reject this payment?'), findsNothing);
      expect(server.posts, isEmpty);
    });

    testWidgets('a server validation error is shown, not a success', (tester) async {
      final server = await _pump(tester)
        ..rejectStatus = 400
        ..rejectError = 'Reason is too long';
      await tester.tap(find.byKey(const Key('reject-pay-2')));
      await tester.pumpAndSettle();
      await tester.enterText(reasonField(), 'Some reason');
      await tester.pump();
      await tester.tap(find.byKey(const Key('reject-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Reason is too long'), findsOneWidget);
      expect(find.textContaining('rejected.'), findsNothing);
      expect(server.posts, hasLength(1));
    });
  });

  group('already processed (no retry, no false success, no receipt)', () {
    Future<void> approve(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('approve-pay-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve').last);
      await tester.pumpAndSettle();
    }

    testWidgets('400 "Payment is already approved": explained, list refreshed, no receipt', (tester) async {
      final server = await _pump(tester)
        ..approveStatus = 400
        ..approveError = 'Payment is already approved';
      server.pending.removeWhere((p) => p.contains('"pay-1"')); // processed elsewhere
      await approve(tester);
      expect(server.posts, ['/api/fee/payments/pay-1/approve'], reason: 'not retried');
      expect(find.textContaining('was already processed'), findsOneWidget);
      expect(find.textContaining('it is approved'), findsOneWidget);
      expect(find.textContaining('Nothing was applied again'), findsOneWidget);
      expect(find.byType(ReceiptScreen), findsNothing);
      expect(find.text('PKR 1,500.00'), findsNothing, reason: 'refreshed from the server');
    });

    testWidgets('409 "Payment was already processed" (race) is the same case', (tester) async {
      final server = await _pump(tester)
        ..approveStatus = 409
        ..approveError = 'Payment was already processed';
      await approve(tester);
      expect(find.textContaining('was already processed'), findsOneWidget);
      expect(find.text('Payment was already processed'), findsNothing, reason: 'explained, not raw');
      expect(server.posts, hasLength(1));
    });

    testWidgets('409 overpayment stays an ordinary error (not "already processed")', (tester) async {
      final server = await _pump(tester)
        ..approveStatus = 409
        ..approveError = 'Payment exceeds the current outstanding balance';
      await approve(tester);
      expect(find.text('Payment exceeds the current outstanding balance'), findsOneWidget);
      expect(find.textContaining('was already processed'), findsNothing);
      expect(server.posts, hasLength(1));
    });

    testWidgets('reject: 400 "Payment is already rejected" is explained', (tester) async {
      final server = await _pump(tester)
        ..rejectStatus = 400
        ..rejectError = 'Payment is already rejected';
      await tester.tap(find.byKey(const Key('reject-pay-2')));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byKey(const Key('reject-reason')), matching: find.byType(TextField)), 'Duplicate entry');
      await tester.pump();
      await tester.tap(find.byKey(const Key('reject-confirm')));
      await tester.pumpAndSettle();
      expect(find.textContaining('it is rejected'), findsOneWidget);
      expect(find.textContaining('rejected.'), findsNothing, reason: 'no success notice');
      expect(server.posts, hasLength(1));
    });

    test('classifier: only the two specific answers count', () {
      expect(FinanceRepository.isAlreadyProcessed(400, 'Payment is already approved'), isTrue);
      expect(FinanceRepository.isAlreadyProcessed(409, 'Payment was already processed'), isTrue);
      expect(FinanceRepository.isAlreadyProcessed(409, 'Payment exceeds the current outstanding balance'), isFalse);
      expect(FinanceRepository.isAlreadyProcessed(400, 'Reason is too long'), isFalse);
      expect(FinanceRepository.isAlreadyProcessed(409, 'Conflicts with existing data'), isFalse);
      expect(FinanceRepository.processedStatus('Payment is already approved'), 'approved');
    });
  });

  group('focus restoration', () {
    bool focusIn(WidgetTester tester, Key key) {
      final ctx = FocusManager.instance.primaryFocus?.context;
      if (ctx == null) return false;
      final target = tester.element(find.byKey(key));
      var hit = identical(ctx, target);
      ctx.visitAncestorElements((e) {
        hit = hit || identical(e, target);
        return !hit;
      });
      return hit;
    }

    Future<void> tabTo(WidgetTester tester, Key key) async {
      for (var i = 0; i < 12 && !focusIn(tester, key); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(focusIn(tester, key), isTrue);
    }

    testWidgets('Approve dialog: Escape returns focus to the Approve button', (tester) async {
      final server = await _pump(tester);
      await tabTo(tester, const Key('approve-pay-1'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(focusIn(tester, const Key('approve-pay-1')), isFalse, reason: 'focus is inside the dialog while open');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(focusIn(tester, const Key('approve-pay-1')), isTrue, reason: 'restored to the opener');
      expect(server.posts, isEmpty);
    });

    testWidgets('Reject dialog: Cancel returns focus to the Reject button', (tester) async {
      final server = await _pump(tester);
      await tabTo(tester, const Key('reject-pay-2'));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reject-cancel')));
      await tester.pumpAndSettle();
      expect(focusIn(tester, const Key('reject-pay-2')), isTrue);
      expect(server.posts, isEmpty);
    });

    testWidgets('opener removed (payment approved): focus falls back safely; Tab continues on the page', (tester) async {
      final server = await _pump(tester);
      await tabTo(tester, const Key('approve-pay-1'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve').last);
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(ReceiptScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('approve-pay-1')), findsNothing, reason: 'row is gone');
      await tabTo(tester, const Key('approve-pay-2'));
      expect(server.posts, ['/api/fee/payments/pay-1/approve'], reason: 'no duplicate execution');
    });
  });

  testWidgets('rows do not navigate when tapped', (tester) async {
    final server = await _pump(tester);
    await tester.tap(find.textContaining('Sara Ahmed', findRichText: true).first);
    await tester.pumpAndSettle();
    expect(find.byType(PendingPaymentsScreen), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(server.posts, isEmpty);
  });

  testWidgets('keyboard: Tab reaches Approve; Enter opens the confirmation; names are specific', (tester) async {
    final handle = tester.ensureSemantics();
    final server = await _pump(tester);
    expect(find.bySemanticsLabel('Approve PKR 1,500.00 from Ali Khan'), findsOneWidget);
    expect(find.bySemanticsLabel('Reject PKR 2,000.00 from Sara Ahmed'), findsOneWidget);
    var reached = false;
    for (var i = 0; i < 12 && !reached; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      reached = tester
          .getSemantics(find.bySemanticsLabel('Approve PKR 1,500.00 from Ali Khan'))
          .getSemanticsData()
          .flagsCollection
          .isFocused
          .toString()
          .contains('isTrue');
    }
    expect(reached, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Approve this payment?'), findsOneWidget);
    expect(server.posts, isEmpty);
    handle.dispose();
  });
}
