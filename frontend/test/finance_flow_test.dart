import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/features/finance/data/finance_repository.dart';
import 'package:smartems/features/finance/data/payment_intent_store.dart';
import 'package:smartems/features/finance/domain/finance_models.dart';
import 'package:smartems/features/finance/presentation/invoice_detail_screen.dart';
import 'package:smartems/features/finance/presentation/receipt_screen.dart';
import 'package:smartems/features/finance/presentation/record_payment_screen.dart';

/// M5 finance workflow: Invoice detail -> Record payment -> Receipt.
/// Synthetic data on a scripted transport that records every request and body.
/// No real payment is ever recorded, approved or rejected.

class _Server implements HttpClientAdapter {
  _Server({this.paid = '0.00', this.status = 'unpaid'});
  String paid;
  String status;
  final posts = <String>[];
  final bodies = <Map<String, dynamic>>[];
  int recordStatus = 201;
  String recordError = 'Amount 9999.00 exceeds outstanding balance 5500.00';
  bool recordTimeout = false;
  int approveStatus = 200;
  String approveError = 'Payment is already approved';
  Completer<void>? hold;

  ResponseBody _raw(int s, String b) => ResponseBody.fromBytes(
    utf8.encode(b),
    s,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<List<int>>? st,
    Future<void>? c,
  ) async {
    final path = o.uri.path;
    if (o.method != 'GET') {
      posts.add('${o.method} $path');
      final d = o.data;
      bodies.add(
        d is Map
            ? Map<String, dynamic>.from(d)
            : (d is String && d.isNotEmpty
                  ? jsonDecode(d) as Map<String, dynamic>
                  : {}),
      );
      if (hold != null) await hold!.future;
    }
    if (path == '/api/fee/invoices/inv-1') {
      return _raw(
        200,
        '{"id":"inv-1","student_id":"stu-1","student_name":"Ali Khan","period":"2026-07",'
        '"due_date":"2026-07-10","subtotal":5500.00,"tax_amount":0.00,"discount_amount":0.00,'
        '"total_amount":5500.00,"paid_amount":$paid,"status":"$status","lines":['
        '{"description":"Tuition Fee","total":5000.00},{"description":"Exam Fee","total":500.00}]}',
      );
    }
    if (path == '/api/fee/payments' && o.method == 'POST') {
      if (recordTimeout) {
        throw DioException(
          requestOptions: o,
          type: DioExceptionType.receiveTimeout,
        );
      }
      if (recordStatus != 201)
        return _raw(recordStatus, jsonEncode({'message': recordError}));
      return _raw(
        201,
        '{"id":"pay-1","amount":1500.00,"status":"pending_approval","idempotentReplay":false}',
      );
    }
    if (path == '/api/fee/payments/pay-1/approve') {
      if (approveStatus != 200)
        return _raw(approveStatus, jsonEncode({'message': approveError}));
      return _raw(
        200,
        '{"id":"pay-1","amount":1500.00,"status":"approved","receiptId":"rcp-1","receiptNumber":"RCP-2026-001"}',
      );
    }
    if (path == '/api/fee/payments/pay-1/reject')
      return _raw(200, '{"id":"pay-1","status":"rejected"}');
    if (path == '/api/fee/receipts/rcp-1') {
      return _raw(
        200,
        '{"id":"rcp-1","receipt_number":"RCP-2026-001","generated_at":"2026-09-24T05:13:28Z",'
        '"amount":1500.00,"source":"MANUAL_CASH","invoice_id":"inv-1","student_name":"Ali Khan"}',
      );
    }
    return _raw(404, '{"message":"not found"}');
  }

  @override
  void close({bool force = false}) {}
}

FinanceRepository _repo(_Server s, {PaymentIntentStore? intents}) =>
    FinanceRepository(
      Dio(BaseOptions(baseUrl: 'https://example.invalid'))
        ..httpClientAdapter = s,
      intents: intents ?? MemoryPaymentIntentStore(),
      newIdempotencyKey: () => '0190f3b4-0000-7000-8000-000000000001',
    );

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light(role: AppRole.admin),
  home: child,
);

void _size(WidgetTester tester, double w, [double h = 1000]) {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Invoice _invoice({String paid = '0.00', String status = 'unpaid'}) =>
    Invoice.fromJson({
      'id': 'inv-1',
      'student_name': 'Ali Khan',
      'period': '2026-07',
      'due_date': '2026-07-10',
      'total_amount': '5500.00',
      'paid_amount': paid,
      'status': status,
    });

Future<void> _enterAmount(WidgetTester tester, String v) async {
  await tester.enterText(find.byType(TextField).first, v);
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  group('Invoice detail', () {
    for (final w in [320.0, 390.0, 768.0, 1024.0, 1440.0]) {
      testWidgets(
        '${w.toInt()} px: no overflow; learner, dates, money and action',
        (tester) async {
          _size(tester, w);
          final s = _Server();
          await tester.pumpWidget(
            _host(
              InvoiceDetailScreen(repository: _repo(s), invoiceId: 'inv-1'),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Ali Khan'), findsOneWidget);
          expect(
            find.textContaining('due Jul 10, 2026'),
            findsOneWidget,
            reason: 'localized business date',
          );
          expect(find.text('PKR 5,500.00'), findsWidgets);
          expect(
            find.text('PKR 5,000.00'),
            findsOneWidget,
            reason: 'line item',
          );
          expect(find.text('Record a payment'), findsOneWidget);
          expect(
            find.textContaining('no way to list the individual payments'),
            findsOneWidget,
          );
          expect(s.posts, isEmpty);
        },
      );
    }

    testWidgets(
      'partial payment: paid and outstanding are the server\'s figures',
      (tester) async {
        _size(tester, 1024);
        final s = _Server(paid: '2000.00', status: 'partial');
        await tester.pumpWidget(
          _host(InvoiceDetailScreen(repository: _repo(s), invoiceId: 'inv-1')),
        );
        await tester.pumpAndSettle();
        expect(find.text('PKR 2,000.00'), findsOneWidget);
        expect(
          find.text('PKR 3,500.00'),
          findsOneWidget,
          reason: 'outstanding = total - paid (exact)',
        );
      },
    );

    testWidgets('fully paid: "Nothing due", settled, no record action', (
      tester,
    ) async {
      _size(tester, 390);
      final s = _Server(paid: '5500.00', status: 'paid');
      await tester.pumpWidget(
        _host(InvoiceDetailScreen(repository: _repo(s), invoiceId: 'inv-1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nothing due'), findsOneWidget);
      expect(find.text('This invoice is settled in full.'), findsOneWidget);
      expect(find.text('Record a payment'), findsNothing);
    });

    testWidgets(
      'semantics: each amount is one named node; headings are headers',
      (tester) async {
        final handle = tester.ensureSemantics();
        _size(tester, 1024);
        await tester.pumpWidget(
          _host(
            InvoiceDetailScreen(
              repository: _repo(_Server()),
              invoiceId: 'inv-1',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.bySemanticsLabel(RegExp(r'^Outstanding\s+PKR 5,500\.00$')),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(RegExp(r'^Total\s+PKR 5,500\.00$')),
          findsOneWidget,
        );
        expect(
          tester.getSemantics(find.text('Charges')).flagsCollection.isHeader,
          isTrue,
        );
        handle.dispose();
      },
    );
  });

  group('Record payment', () {
    testWidgets('invalid amounts cannot be submitted', (tester) async {
      _size(tester, 1024);
      final s = _Server();
      await tester.pumpWidget(
        _host(RecordPaymentScreen(repository: _repo(s), invoice: _invoice())),
      );
      await tester.pumpAndSettle();
      for (final bad in ['', 'abc', '0', '-5', '10.123']) {
        await _enterAmount(tester, bad);
        final btn = find.widgetWithText(GestureDetector, 'Record payment');
        expect(btn, findsWidgets);
        await tester.ensureVisible(find.text('Record payment'));
        await tester.tap(find.text('Record payment'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(
          find.text('Record this payment?'),
          findsNothing,
          reason: '"$bad" must not reach confirmation',
        );
      }
      expect(s.posts, isEmpty);
    });

    testWidgets(
      'confirmation first; Cancel sends nothing; focus returns to the button',
      (tester) async {
        _size(tester, 1024);
        final s = _Server();
        await tester.pumpWidget(
          _host(RecordPaymentScreen(repository: _repo(s), invoice: _invoice())),
        );
        await tester.pumpAndSettle();
        await _enterAmount(tester, '1500');
        expect(
          find.text('PKR 1,500.00'),
          findsOneWidget,
          reason: 'summary shows the typed amount',
        );
        await _tapVisible(tester, find.text('Record payment'));
        expect(find.text('Record this payment?'), findsOneWidget);
        expect(
          find.textContaining('PKR 1,500.00 via Cash for Ali Khan'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('confirm-cancel')));
        await tester.pumpAndSettle();
        expect(s.posts, isEmpty);
      },
    );

    testWidgets(
      'confirmed: exactly one request carrying the idempotency key; awaiting approval',
      (tester) async {
        _size(tester, 1024);
        final s = _Server();
        await tester.pumpWidget(
          _host(RecordPaymentScreen(repository: _repo(s), invoice: _invoice())),
        );
        await tester.pumpAndSettle();
        await _enterAmount(tester, '1500');
        await _tapVisible(tester, find.text('Record payment'));
        await tester.tap(find.byKey(const Key('confirm-record-payment')));
        await tester.pumpAndSettle();
        expect(s.posts, ['POST /api/fee/payments']);
        expect(
          s.bodies.single['idempotencyKey'],
          '0190f3b4-0000-7000-8000-000000000001',
        );
        expect(s.bodies.single['amount'], anyOf('1500.00', 1500.0, 1500));
        expect(find.textContaining('awaiting approval'), findsWidgets);
      },
    );

    testWidgets(
      'while processing, the button is disabled (no duplicate submission)',
      (tester) async {
        _size(tester, 1024);
        final s = _Server()..hold = Completer<void>();
        await tester.pumpWidget(
          _host(RecordPaymentScreen(repository: _repo(s), invoice: _invoice())),
        );
        await tester.pumpAndSettle();
        await _enterAmount(tester, '1500');
        await _tapVisible(tester, find.text('Record payment'));
        await tester.tap(find.byKey(const Key('confirm-record-payment')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('Recording…'), findsOneWidget);
        await tester.tap(find.text('Recording…'), warnIfMissed: false);
        await tester.pump();
        expect(s.posts, hasLength(1));
        s.hold!.complete();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'server refusal (overpayment) is shown verbatim; nothing assumed recorded',
      (tester) async {
        _size(tester, 1024);
        final s = _Server()..recordStatus = 400;
        await tester.pumpWidget(
          _host(RecordPaymentScreen(repository: _repo(s), invoice: _invoice())),
        );
        await tester.pumpAndSettle();
        await _enterAmount(tester, '1500');
        await _tapVisible(tester, find.text('Record payment'));
        await tester.tap(find.byKey(const Key('confirm-record-payment')));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('exceeds outstanding balance'),
          findsOneWidget,
        );
        expect(find.text('Approve and issue receipt'), findsNothing);
      },
    );

    testWidgets(
      'uncertain response (timeout): original kept; retry re-uses the SAME key',
      (tester) async {
        _size(tester, 1024);
        final s = _Server()..recordTimeout = true;
        final store = MemoryPaymentIntentStore();
        await tester.pumpWidget(
          _host(
            RecordPaymentScreen(
              repository: _repo(s, intents: store),
              invoice: _invoice(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _enterAmount(tester, '1500');
        await _tapVisible(tester, find.text('Record payment'));
        await tester.tap(find.byKey(const Key('confirm-record-payment')));
        await tester.pumpAndSettle();
        expect(
          find.text('Retry original payment'),
          findsOneWidget,
          reason: 'no new payment can be started',
        );
        s.recordTimeout = false;
        await _tapVisible(tester, find.text('Retry original payment'));
        expect(find.text('Retry the original payment?'), findsOneWidget);
        await tester.tap(find.byKey(const Key('confirm-record-payment')));
        await tester.pumpAndSettle();
        expect(s.posts, ['POST /api/fee/payments', 'POST /api/fee/payments']);
        expect(
          s.bodies[0]['idempotencyKey'],
          s.bodies[1]['idempotencyKey'],
          reason: 'never a new key',
        );
      },
    );

    Future<_Server> recorded(WidgetTester tester) async {
      _size(tester, 1024);
      final s = _Server();
      await tester.pumpWidget(
        _host(RecordPaymentScreen(repository: _repo(s), invoice: _invoice())),
      );
      await tester.pumpAndSettle();
      await _enterAmount(tester, '1500');
      await _tapVisible(tester, find.text('Record payment'));
      await tester.tap(find.byKey(const Key('confirm-record-payment')));
      await tester.pumpAndSettle();
      return s;
    }

    testWidgets('approve: confirmed, then the server\'s receipt is shown', (
      tester,
    ) async {
      final s = await recorded(tester);
      await _tapVisible(tester, find.text('Approve and issue receipt'));
      expect(
        find.textContaining('no way to reverse or cancel'),
        findsOneWidget,
      );
      await tester.tap(find.text('Approve').last);
      await tester.pumpAndSettle();
      expect(s.posts.last, 'POST /api/fee/payments/pay-1/approve');
      expect(find.byType(ReceiptScreen), findsOneWidget);
      expect(find.text('RCP-2026-001'), findsWidgets);
    });

    testWidgets(
      'approve: already processed -> explained, no receipt, no retry',
      (tester) async {
        final s = await recorded(tester);
        s.approveStatus = 400;
        await _tapVisible(tester, find.text('Approve and issue receipt'));
        await tester.tap(find.text('Approve').last);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('payment-already-processed')),
          findsOneWidget,
        );
        expect(find.byType(ReceiptScreen), findsNothing);
        expect(s.posts.where((p) => p.endsWith('/approve')), hasLength(1));
      },
    );

    testWidgets(
      'reject: reason required; Escape sends nothing; confirmed sends the reason',
      (tester) async {
        final s = await recorded(tester);
        await _tapVisible(tester, find.text('Reject this payment'));
        expect(find.text('Reject this payment?'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(s.posts.where((p) => p.endsWith('/reject')), isEmpty);
        await _tapVisible(tester, find.text('Reject this payment'));
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('reject-reason')),
            matching: find.byType(TextField),
          ),
          'Wrong invoice',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('reject-confirm')));
        await tester.pumpAndSettle();
        expect(s.posts.last, 'POST /api/fee/payments/pay-1/reject');
        expect(s.bodies.last, {'reason': 'Wrong invoice'});
      },
    );

    testWidgets(
      'keyboard: Tab reaches Record payment; Enter opens the confirmation',
      (tester) async {
        _size(tester, 1024, 1400);
        final s = _Server();
        await tester.pumpWidget(
          _host(RecordPaymentScreen(repository: _repo(s), invoice: _invoice())),
        );
        await tester.pumpAndSettle();
        await _enterAmount(tester, '1500');
        var opened = false;
        for (var i = 0; i < 14 && !opened; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          final f = FocusManager.instance.primaryFocus?.context;
          if (f != null &&
              find
                  .descendant(
                    of: find.widgetWithText(Semantics, 'Record payment'),
                    matching: find.byWidget(f.widget),
                  )
                  .evaluate()
                  .isNotEmpty) {
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            opened = find.text('Record this payment?').evaluate().isNotEmpty;
          }
        }
        expect(opened, isTrue);
        expect(s.posts, isEmpty);
      },
    );
  });

  group('Receipt', () {
    for (final w in [320.0, 390.0, 1440.0]) {
      testWidgets(
        '${w.toInt()} px: server receipt rendered; local issue time; no print offered',
        (tester) async {
          _size(tester, w);
          await tester.pumpWidget(
            _host(
              ReceiptScreen(
                repository: _repo(_Server()),
                receiptId: 'rcp-1',
                receiptNumber: 'RCP-2026-001',
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('PKR 1,500.00'), findsOneWidget);
          expect(find.text('RCP-2026-001'), findsOneWidget);
          expect(find.text('Ali Khan'), findsOneWidget);
          expect(find.textContaining('Sep 24, 2026'), findsOneWidget);
          expect(
            find.textContaining('2026-09-24T'),
            findsNothing,
            reason: 'raw ISO not shown',
          );
          expect(
            find.textContaining('cannot be downloaded or printed'),
            findsOneWidget,
          );
          expect(find.text('Download'), findsNothing);
          expect(find.text('Print'), findsNothing);
        },
      );
    }
  });
}
