import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/features/admin/data/admin_repository.dart';
import 'package:smartems/features/finance/data/finance_repository.dart';
import 'package:smartems/features/finance/domain/finance_models.dart';
import 'package:smartems/features/finance/domain/money.dart';
import 'package:smartems/features/finance/presentation/collection_report_screen.dart';
import 'package:smartems/features/finance/presentation/defaulters_screen.dart';
import 'package:smartems/features/finance/presentation/fee_heads_screen.dart';
import 'package:smartems/features/finance/presentation/fee_plans_screen.dart';
import 'package:smartems/features/finance/presentation/finance_home_screen.dart';
import 'package:smartems/features/finance/presentation/generate_invoices_screen.dart';
import 'package:smartems/features/finance/presentation/invoice_detail_screen.dart';
import 'package:smartems/features/finance/presentation/invoices_screen.dart';
import 'package:smartems/features/finance/presentation/pending_payments_screen.dart';
import 'package:smartems/features/finance/presentation/receipt_screen.dart';
import 'package:smartems/features/finance/presentation/record_payment_screen.dart';
import 'package:smartems/features/setup/data/setup_repository.dart';
import 'package:smartems/features/setup/domain/setup_models.dart';

/// A stub of the fee endpoints carrying this backend's REAL quirks:
///
///  - money as bare JSON numbers with two decimals (`5500.00`), which is the
///    whole reason the decoder exists;
///  - snake_case responses against camelCase requests;
///  - payments landing `pending_approval`, approval returning a receipt;
///  - 409 for plain validation failures;
///  - `?sectionId=` accepted and ignored.
///
/// Bodies are written as RAW JSON TEXT rather than encoded from Dart maps,
/// because `jsonEncode(5500.0)` produces `5500.0` — the stub has to be able
/// to send `5500.00` exactly, or it would not be testing the thing that
/// matters.
class _FeeServer implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  final List<String> heads = [];
  final List<String> plans = [];
  String invoicesJson = '[]';
  String invoiceDetailJson = '{}';
  final List<String> pending = [];
  String defaultersJson = '[]';
  String collectionJson =
      '{"totalInvoiced":0.00,"totalCollected":0.00,"outstanding":0.00,'
      '"byClass":[]}';
  String generateJson = '{"total":1,"generated":1,"skipped":0}';

  /// Set to make the next write fail the way the live API does.
  int? failStatus;
  String failMessage = 'Conflicts with existing data';

  int _id = 0;

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    requests.add(o);
    final path = o.uri.path;
    final body = o.data is Map ? (o.data as Map).cast<String, dynamic>() : null;

    if (o.method == 'GET') {
      if (path == '/api/fee/heads') return _raw(200, '[${heads.join(',')}]');
      if (path == '/api/fee/plans') return _raw(200, '[${plans.join(',')}]');
      if (path.startsWith('/api/fee/plans/')) {
        return _raw(
          200,
          '{"id":"plan-1","name":"Grade 5 Monthly","frequency":"monthly",'
          '"class_id":"class-1","items":[{"fee_head_id":"head-1",'
          '"fee_head_name":"Tuition Fee","amount":5000.00}],'
          '"subtotal":5000.00,"taxAmount":0.00,"total":5000.00}',
        );
      }
      if (path == '/api/fee/invoices') {
        return _raw(200,
            '{"size":20,"page":0,"totalElements":1,"content":$invoicesJson}');
      }
      if (path.startsWith('/api/fee/invoices/')) {
        return _raw(200, invoiceDetailJson);
      }
      if (path == '/api/fee/payments/pending') {
        return _raw(200, '[${pending.join(',')}]');
      }
      if (path.startsWith('/api/fee/receipts/')) {
        return _raw(
          200,
          '{"id":"rcp-1","receipt_number":"RCP-2026-001",'
          '"generated_at":"2026-09-24T00:13:28Z","amount":1500.00,'
          '"source":"MANUAL_BANK","invoice_id":"inv-1",'
          '"student_name":"Ali Khan"}',
        );
      }
      if (path == '/api/fee/reports/collection') {
        return _raw(200, collectionJson);
      }
      if (path == '/api/fee/reports/defaulters') {
        return _raw(200, defaultersJson);
      }
      // Shared setup/admin reads the hub needs.
      if (path == '/api/campuses') {
        return _raw(200, '[{"id":"campus-1","name":"Main"}]');
      }
      if (path == '/api/academic-years') {
        return _raw(
          200,
          '{"content":[{"id":"year-1","name":"2025-26","startDate":'
          '"2025-08-01","endDate":"2026-05-31","current":true}],'
          '"totalElements":1}',
        );
      }
      if (path == '/api/classes') {
        return _raw(
          200,
          '{"content":[{"id":"class-1","name":"Grade 5","levelOrder":5}],'
          '"totalElements":1}',
        );
      }
      return _raw(404, '{"message":"no route"}');
    }

    if (o.method == 'POST') {
      if (failStatus != null) {
        final status = failStatus!;
        failStatus = null;
        return _raw(status, '{"message":"$failMessage"}');
      }
      if (path == '/api/fee/heads') {
        final row = '{"id":"head-${_id++}","name":"${body?['name']}",'
            '"is_recurring":${body?['isRecurring'] ?? false},'
            '"tax_rate":${body?['taxRate'] ?? 0}}';
        heads.add(row);
        return _raw(201, row);
      }
      if (path == '/api/fee/plans') {
        final row = '{"id":"plan-${_id++}","name":"${body?['name']}",'
            '"frequency":"monthly","class_id":"${body?['classId']}",'
            '"academic_year_id":"${body?['academicYearId']}","due_day":10,'
            '"grace_days":0,"items":[],"subtotal":0.00,"total":0.00}';
        plans.add(row);
        return _raw(201, row);
      }
      if (path.endsWith('/generate')) return _raw(200, generateJson);
      if (path == '/api/fee/payments') {
        lastPaymentBody = body;
        final row = '{"id":"pay-1","invoice_id":"${body?['invoiceId']}",'
            '"student_name":"Ali Khan","amount":${body?['amount']},'
            '"source":"${body?['source']}","reference":'
            '${body?['reference'] == null ? 'null' : '"${body?['reference']}"'},'
            '"status":"pending_approval","received_at":"2026-09-24T00:00:00Z"}';
        pending.add(row);
        return _raw(201, row);
      }
      if (path.endsWith('/approve')) {
        pending.clear();
        return _raw(
          200,
          '{"id":"pay-1","amount":1500.00,"status":"approved",'
          '"receiptId":"rcp-1","receiptNumber":"RCP-2026-001"}',
        );
      }
      if (path.endsWith('/reject')) {
        pending.clear();
        return _raw(200, '{"id":"pay-1","status":"rejected"}');
      }
    }
    return _raw(404, '{"message":"no route"}');
  }

  Map<String, dynamic>? lastPaymentBody;

  @override
  void close({bool force = false}) {}
}

ResponseBody _raw(int status, String json) => ResponseBody.fromBytes(
      utf8.encode(json),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

({Dio dio, _FeeServer server, FinanceRepository repo}) _wire() {
  final server = _FeeServer();
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = server;
  return (
    dio: dio,
    server: server,
    repo: FinanceRepository(
      dio,
      // Pinned so a test can assert the key is sent and is a UUID.
      newIdempotencyKey: () => '11111111-2222-4333-8444-555555555555',
    ),
  );
}

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.light(role: AppRole.admin),
      home: child,
    );

const _class = SchoolClass(id: 'class-1', name: 'Grade 5', levelOrder: 5);
const _year = AcademicYear(
  id: 'year-1',
  name: '2025-26',
  startDate: '2025-08-01',
  endDate: '2026-05-31',
  current: true,
);

const _invoiceJson =
    '{"id":"inv-1","student_id":"stu-1","student_name":"Ali Khan",'
    '"period":"2026-07","due_date":"2026-07-10","subtotal":5500.00,'
    '"tax_amount":0.00,"discount_amount":0.00,"total_amount":5500.00,'
    '"paid_amount":0.00,"status":"unpaid"}';

void main() {
  group('the decoding door', () {
    test('a money number from the wire becomes an exact amount', () async {
      final w = _wire();
      w.server.invoicesJson = '[$_invoiceJson]';

      final page = await w.repo.loadInvoices();
      expect(page.invoices.single.totalAmount, Money.parse('5500.00'));
      expect(page.invoices.single.totalAmount.paisa, 550000);
    });

    test('an amount the wire sends as 0.01 survives intact', () async {
      final w = _wire();
      w.server.invoicesJson = _invoiceJson
          .replaceAll('"paid_amount":0.00', '"paid_amount":0.01')
          .replaceAll('"status":"unpaid"', '"status":"partial"');
      w.server.invoicesJson = '[${w.server.invoicesJson}]';

      final page = await w.repo.loadInvoices();
      expect(page.invoices.single.paidAmount.paisa, 1);
      expect(page.invoices.single.outstanding, Money.parse('5499.99'));
    });

    test('only the filters this backend honours are sent', () async {
      final w = _wire();
      w.server.invoicesJson = '[]';
      await w.repo.loadInvoices(classId: 'class-1', status: 'unpaid');

      final query = w.server.requests.last.uri.queryParameters;
      expect(query['classId'], 'class-1');
      expect(query['status'], 'unpaid');
      // ?sectionId= is accepted and IGNORED by the live API, so it is never
      // sent — a filter that does nothing is worse than no filter.
      expect(query.containsKey('sectionId'), isFalse);
    });

    test('the collection report is fetched with no filters at all', () async {
      final w = _wire();
      await w.repo.loadCollectionReport();
      // The endpoint accepts `period` and ignores it entirely.
      expect(w.server.requests.last.uri.queryParameters, isEmpty);
    });
  });

  group('writes', () {
    test('a payment sends a UUID idempotency key and a decimal amount',
        () async {
      final w = _wire();
      final result = await w.repo.recordPayment(
        invoiceId: 'inv-1',
        amount: Money.parse('2500.50'),
        source: PaymentSource.bank,
        reference: 'SLIP-9',
      );

      expect(result.paymentId, 'pay-1');
      final body = w.server.lastPaymentBody!;
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
                r'[0-9a-f]{12}$')
            .hasMatch(body['idempotencyKey'] as String),
        isTrue,
        reason: 'a non-UUID key answers the misleading "Malformed request '
            'body" on the live API',
      );
      // Sent as text, never as a double.
      expect(body['amount'], '2500.50');
      expect(body['amount'], isA<String>());
      expect(body['source'], 'MANUAL_BANK');
      expect(body['reference'], 'SLIP-9');
    });

    test('a real UUID is generated when none is injected', () async {
      final server = _FeeServer();
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = server;
      await FinanceRepository(dio).recordPayment(
        invoiceId: 'inv-1',
        amount: Money.parse('1'),
        source: PaymentSource.cash,
      );
      final key = server.lastPaymentBody!['idempotencyKey'] as String;
      expect(key.length, 36);
      expect(key[14], '4');
    });

    test('the backend’s own message is surfaced, not a guess at it', () async {
      final w = _wire();
      w.server.failStatus = 400;
      w.server.failMessage =
          'Amount 999999.99 exceeds outstanding balance 5499.00';

      final result = await w.repo.recordPayment(
        invoiceId: 'inv-1',
        amount: Money.parse('999999.99'),
        source: PaymentSource.cash,
      );
      expect(result.paymentId, isNull);
      expect(result.error, contains('exceeds outstanding balance 5499.00'));
    });

    test('a 409 on a fee head is NOT reported as a duplicate', () async {
      // This backend answers 409 for a missing field. Rendering "that
      // already exists" would send the admin hunting for a duplicate that
      // is not there.
      final w = _wire();
      w.server.failStatus = 409;
      w.server.failMessage = 'Conflicts with existing data';

      await expectLater(
        w.repo.createHead(name: '', isRecurring: false),
        throwsA(isA<Object>()),
      );
    });

    test('a fee plan always carries an explicit academic year', () async {
      final w = _wire();
      await w.repo.createPlan(
        name: 'Grade 5 Monthly',
        frequency: 'monthly',
        classId: 'class-1',
        academicYearId: 'year-1',
        campusId: 'campus-1',
        dueDay: 10,
        graceDays: 0,
        items: [(feeHeadId: 'head-1', amount: Money.parse('5000'))],
      );

      final body = w.server.requests.last.data as Map;
      expect(body['academicYearId'], 'year-1',
          reason: 'the backend’s `current` year flag points at an EXPIRED '
              'year, so the year is never left to the server');
      expect((body['items'] as List).single, {
        'feeHeadId': 'head-1',
        'amount': '5000.00',
      });
    });
  });

  group('fee heads screen', () {
    testWidgets('an empty school is told what a fee head is for',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(_host(FeeHeadsScreen(repository: w.repo)));
      await tester.pumpAndSettle();

      expect(find.text('No fee heads yet'), findsOneWidget);
    });

    testWidgets('permanence is stated BEFORE the save, not after',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(_host(FeeHeadsScreen(repository: w.repo)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add a fee head'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('cannot be renamed or removed'),
        findsOneWidget,
      );
    });

    testWidgets('a created head appears in the list', (tester) async {
      final w = _wire();
      await tester.pumpWidget(_host(FeeHeadsScreen(repository: w.repo)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add a fee head'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Transport');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Transport'), findsWidgets);
    });

    testWidgets('a malformed tax rate is refused before the round trip',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(_host(FeeHeadsScreen(repository: w.repo)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add a fee head'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Transport');
      await tester.enterText(find.byType(TextField).at(1), '5.005');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('up to two decimals'), findsOneWidget);
      expect(w.server.heads, isEmpty);
    });
  });

  group('fee plans screen', () {
    Widget plansScreen(FinanceRepository repo) => _host(FeePlansScreen(
          repository: repo,
          classes: const [_class],
          heads: const [
            FeeHead(
              id: 'head-1',
              name: 'Tuition Fee',
              isRecurring: true,
              taxRate: '0.00',
            ),
          ],
          year: _year,
          campusId: 'campus-1',
        ));

    testWidgets('the year the plan will be written to is named', (tester) async {
      final w = _wire();
      await tester.pumpWidget(plansScreen(w.repo));
      await tester.pumpAndSettle();

      expect(find.textContaining('2025-26'), findsOneWidget);
    });

    testWidgets('no running total is shown while typing amounts',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(plansScreen(w.repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add a fee plan'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Grade 5 Monthly');
      await tester.enterText(find.byType(TextField).last, '5000');
      await tester.pumpAndSettle();

      // A client-side sum would be a second source of truth for money.
      expect(find.text('PKR 5,000.00'), findsNothing);
      expect(
        find.textContaining('calculated by the server'),
        findsOneWidget,
      );
    });
  });

  group('generate invoices', () {
    Widget generateScreen(FinanceRepository repo) =>
        _host(GenerateInvoicesScreen(
          repository: repo,
          plans: const [
            FeePlan(
              id: 'plan-1',
              name: 'Grade 5 Monthly',
              frequency: 'monthly',
              classId: 'class-1',
            ),
          ],
          classes: const [_class],
        ));

    testWidgets('what will happen is stated before it happens',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(generateScreen(w.repo));
      await tester.pumpAndSettle();

      expect(find.text('What this will do'), findsOneWidget);
      expect(find.textContaining('Grade 5'), findsWidgets);
      expect(find.textContaining('cannot be deleted'), findsOneWidget);
    });

    testWidgets('it does not estimate a student count it cannot know',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(generateScreen(w.repo));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('this screen does not estimate it'),
        findsOneWidget,
      );
    });

    testWidgets('the run is confirmed deliberately and says it is permanent',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(generateScreen(w.repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate for this period'));
      await tester.pumpAndSettle();

      expect(find.text('Generate these invoices?'), findsOneWidget);
      expect(find.textContaining('This cannot be undone'), findsOneWidget);
      // And the reassurance that re-running is safe, which is true here.
      expect(find.textContaining('are skipped, not duplicated'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      // Cancelling ran nothing.
      expect(
        w.server.requests.where((r) => r.path.endsWith('/generate')),
        isEmpty,
      );
    });

    testWidgets('a repeat run reports what was skipped rather than created',
        (tester) async {
      final w = _wire();
      w.server.generateJson = '{"total":30,"generated":0,"skipped":30}';
      await tester.pumpWidget(generateScreen(w.repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate for this period'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing was created'), findsOneWidget);
      expect(find.textContaining('already existed'), findsOneWidget);
    });

    testWidgets('a bad period blocks the button', (tester) async {
      final w = _wire();
      await tester.pumpWidget(generateScreen(w.repo));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '2026');
      await tester.pumpAndSettle();

      expect(find.textContaining('like 2026-09'), findsOneWidget);
    });
  });

  group('invoice list and detail', () {
    testWidgets('an overdue invoice says so in words, since there is no status',
        (tester) async {
      final w = _wire();
      w.server.invoicesJson = '[$_invoiceJson]';
      await tester.pumpWidget(_host(InvoicesScreen(
        repository: w.repo,
        classes: const [_class],
      )));
      await tester.pumpAndSettle();

      expect(find.text('Ali Khan'), findsOneWidget);
      expect(find.text('PKR 5,500.00'), findsOneWidget);
      expect(find.textContaining('days late'), findsOneWidget);
    });

    testWidgets('the detail renders the SERVER total, not the sum of lines',
        (tester) async {
      final w = _wire();
      // Lines add up to 5,500 but the server says 5,000 — a discount the app
      // knows nothing about. The server figure must win.
      w.server.invoiceDetailJson =
          '{"id":"inv-1","student_name":"Ali Khan","period":"2026-07",'
          '"due_date":"2026-07-10","total_amount":5000.00,'
          '"paid_amount":0.00,"status":"unpaid","lines":['
          '{"description":"Tuition Fee","total":5000.00},'
          '{"description":"Exam Fee","total":500.00}]}';

      await tester.pumpWidget(_host(InvoiceDetailScreen(
        repository: w.repo,
        invoiceId: 'inv-1',
      )));
      await tester.pumpAndSettle();

      expect(find.text('PKR 5,000.00'), findsWidgets);
      expect(find.text('PKR 5,500.00'), findsNothing);
    });

    testWidgets('it admits it cannot list the individual payments',
        (tester) async {
      final w = _wire();
      w.server.invoiceDetailJson = _invoiceJson;
      await tester.pumpWidget(_host(InvoiceDetailScreen(
        repository: w.repo,
        invoiceId: 'inv-1',
      )));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('no way to list the individual payments'),
        findsOneWidget,
      );
    });

    testWidgets('a settled invoice offers no payment button', (tester) async {
      final w = _wire();
      w.server.invoiceDetailJson = _invoiceJson
          .replaceAll('"paid_amount":0.00', '"paid_amount":5500.00')
          .replaceAll('"status":"unpaid"', '"status":"paid"');

      await tester.pumpWidget(_host(InvoiceDetailScreen(
        repository: w.repo,
        invoiceId: 'inv-1',
      )));
      await tester.pumpAndSettle();

      expect(find.text('Record a payment'), findsNothing);
      expect(find.textContaining('settled in full'), findsOneWidget);
    });
  });

  group('record payment', () {
    Invoice invoice({String paid = '0.00', String status = 'unpaid'}) =>
        Invoice.fromJson({
          'id': 'inv-1',
          'student_name': 'Ali Khan',
          'period': '2026-07',
          'due_date': '2026-07-10',
          'total_amount': '5500.00',
          'paid_amount': paid,
          'status': status,
        });

    testWidgets('it says the payment is not final until approved',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(_host(RecordPaymentScreen(
        repository: w.repo,
        invoice: invoice(),
      )));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('has to be approved before it counts'),
        findsOneWidget,
      );
    });

    testWidgets('no date field is offered, and the reason is given',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(_host(RecordPaymentScreen(
        repository: w.repo,
        invoice: invoice(),
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('an earlier date cannot be entered'),
          findsOneWidget);
      expect(find.text('Date'), findsNothing);
    });

    testWidgets('only cash and bank transfer are offered', (tester) async {
      final w = _wire();
      await tester.pumpWidget(_host(RecordPaymentScreen(
        repository: w.repo,
        invoice: invoice(),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Bank transfer'), findsOneWidget);
      expect(find.text('Cheque'), findsNothing);
      expect(find.textContaining('Cheque, card and online are not available'),
          findsOneWidget);
    });

    testWidgets('it says plainly that payments cannot be taken offline',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(_host(RecordPaymentScreen(
        repository: w.repo,
        invoice: invoice(),
      )));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('cannot be recorded while offline'),
        findsOneWidget,
      );
    });

    testWidgets('an overpayment is caught before the round trip',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(_host(RecordPaymentScreen(
        repository: w.repo,
        invoice: invoice(paid: '5000.00', status: 'partial'),
      )));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '900');
      await tester.pumpAndSettle();

      expect(find.textContaining('more than the PKR 500.00 still owed'),
          findsOneWidget);
      expect(w.server.lastPaymentBody, isNull);
    });

    testWidgets('after recording, the money is shown as NOT yet counted',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(_host(RecordPaymentScreen(
        repository: w.repo,
        invoice: invoice(),
      )));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '1500');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record payment'));
      await tester.pumpAndSettle();

      expect(find.textContaining('is NOT counted yet'), findsOneWidget);
      expect(find.text('Approve and issue receipt'), findsOneWidget);
    });

    testWidgets('approval is confirmed and stated as irreversible',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(_host(RecordPaymentScreen(
        repository: w.repo,
        invoice: invoice(),
      )));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '1500');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record payment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve and issue receipt'));
      await tester.pumpAndSettle();

      expect(find.textContaining('no way to reverse or cancel'), findsOneWidget);
    });
  });

  group('approvals queue', () {
    testWidgets('every pending payment is marked as not yet counted',
        (tester) async {
      final w = _wire();
      w.server.pending.add(
        '{"id":"pay-1","invoice_id":"inv-1","student_name":"Ali Khan",'
        '"amount":1500.00,"source":"MANUAL_CASH","reference":null,'
        '"received_at":"2026-09-24T00:00:00Z"}',
      );

      await tester
          .pumpWidget(_host(PendingPaymentsScreen(repository: w.repo)));
      await tester.pumpAndSettle();

      expect(find.text('PKR 1,500.00'), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);
      expect(find.textContaining('None of this money is counted'),
          findsOneWidget);
    });

    testWidgets('an empty queue is an empty state, not an error',
        (tester) async {
      final w = _wire();
      await tester
          .pumpWidget(_host(PendingPaymentsScreen(repository: w.repo)));
      await tester.pumpAndSettle();

      expect(find.text('Nothing awaiting approval'), findsOneWidget);
    });
  });

  group('receipt', () {
    testWidgets('it shows the receipt and admits there is no PDF',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(_host(ReceiptScreen(
        repository: w.repo,
        receiptId: 'rcp-1',
        receiptNumber: 'RCP-2026-001',
      )));
      await tester.pumpAndSettle();

      expect(find.text('PKR 1,500.00'), findsOneWidget);
      expect(find.text('RCP-2026-001'), findsWidgets);
      expect(find.textContaining('cannot be downloaded or printed'),
          findsOneWidget);
      expect(find.text('Download'), findsNothing);
    });
  });

  group('defaulters', () {
    testWidgets('the biggest debt is at the top, not the first name',
        (tester) async {
      final w = _wire();
      w.server.defaultersJson = '['
          '{"invoice_id":"i1","student_name":"Aisha","admission_number":"S1",'
          '"period":"2026-07","due_date":"2026-07-10","status":"unpaid",'
          '"total_amount":200.00,"paid_amount":0.00,"outstanding":200.00},'
          '{"invoice_id":"i2","student_name":"Zara","admission_number":"S2",'
          '"period":"2026-07","due_date":"2026-07-10","status":"unpaid",'
          '"total_amount":80000.00,"paid_amount":0.00,"outstanding":80000.00}'
          ']';

      await tester.pumpWidget(_host(DefaultersScreen(
        repository: w.repo,
        classes: const [_class],
      )));
      await tester.pumpAndSettle();

      final amounts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .where((s) => s.startsWith('PKR '))
          .toList();
      expect(amounts.first, 'PKR 80,000.00');
    });

    testWidgets('nobody behind is a clean empty state', (tester) async {
      final w = _wire();
      await tester.pumpWidget(_host(DefaultersScreen(
        repository: w.repo,
        classes: const [_class],
      )));
      await tester.pumpAndSettle();

      expect(find.text('Nobody is behind'), findsOneWidget);
    });
  });

  group('collection report', () {
    testWidgets('it states its scope rather than offering a dead filter',
        (tester) async {
      final w = _wire();
      w.server.collectionJson =
          '{"totalInvoiced":125000.00,"totalCollected":100000.50,'
          '"outstanding":24999.50,"byClass":[{"class_name":"Grade 5",'
          '"invoiced":125000.00,"collected":100000.50,'
          '"outstanding":24999.50}]}';

      await tester
          .pumpWidget(_host(CollectionReportScreen(repository: w.repo)));
      await tester.pumpAndSettle();

      expect(find.text('PKR 100,000.50'), findsWidgets);
      expect(find.textContaining('cannot be narrowed to a month or a year'),
          findsOneWidget);
      // No period control, because the endpoint ignores one.
      expect(find.text('Apply period'), findsNothing);
    });

    testWidgets('nothing invoiced yet is an empty state', (tester) async {
      final w = _wire();
      await tester
          .pumpWidget(_host(CollectionReportScreen(repository: w.repo)));
      await tester.pumpAndSettle();

      expect(find.text('Nothing invoiced yet'), findsOneWidget);
    });
  });

  group('the finance hub', () {
    Widget hub(Dio dio, FinanceRepository repo) => _host(FinanceHomeScreen(
          finance: repo,
          setup: SetupRepository(dio),
          admin: AdminRepository(dio),
        ));

    testWidgets('a blocked step says what is missing, not "could not load"',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(hub(w.dio, w.repo));
      await tester.pumpAndSettle();

      expect(find.text('Create a fee head first'), findsOneWidget);
      expect(find.text('Create a fee plan first'), findsOneWidget);
      expect(find.textContaining('Could not load'), findsNothing);
    });

    testWidgets('the steps unblock in order as their dependency appears',
        (tester) async {
      final w = _wire();
      w.server.heads.add(
        '{"id":"head-1","name":"Tuition Fee","is_recurring":true,'
        '"tax_rate":0.00}',
      );
      await tester.pumpWidget(hub(w.dio, w.repo));
      await tester.pumpAndSettle();

      expect(find.text('Create a fee head first'), findsNothing);
      expect(find.text('Create a fee plan first'), findsOneWidget);
    });
  });

  group('both themes', () {
    // Every screen in the batch, rendered in dark as well as light. A token
    // that only exists in one mode, or a hardcoded colour that slipped past
    // check_tokens.sh, shows up here as an exception or an unreadable pill.
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';

      testWidgets('all eight finance screens render in $mode',
          (tester) async {
        final w = _wire();
        w.server.invoicesJson = '[$_invoiceJson]';
        w.server.invoiceDetailJson = _invoiceJson;
        w.server.heads.add(
          '{"id":"head-1","name":"Tuition Fee","is_recurring":true,'
          '"tax_rate":0.00}',
        );
        w.server.pending.add(
          '{"id":"pay-1","invoice_id":"inv-1","student_name":"Ali Khan",'
          '"amount":1500.00,"source":"MANUAL_CASH","reference":null,'
          '"received_at":"2026-09-24T00:00:00Z"}',
        );
        w.server.defaultersJson = '['
            '{"invoice_id":"i1","student_name":"Aisha","admission_number":"S1",'
            '"period":"2026-07","due_date":"2026-07-10","status":"unpaid",'
            '"total_amount":200.00,"paid_amount":0.00,"outstanding":200.00}]';
        w.server.collectionJson =
            '{"totalInvoiced":125000.00,"totalCollected":100000.50,'
            '"outstanding":24999.50,"byClass":[{"class_name":"Grade 5",'
            '"invoiced":125000.00,"collected":100000.50,'
            '"outstanding":24999.50}]}';

        final screens = <String, Widget>{
          'hub': FinanceHomeScreen(
            finance: w.repo,
            setup: SetupRepository(w.dio),
            admin: AdminRepository(w.dio),
          ),
          'heads': FeeHeadsScreen(repository: w.repo),
          'plans': FeePlansScreen(
            repository: w.repo,
            classes: const [_class],
            heads: const [
              FeeHead(
                id: 'head-1',
                name: 'Tuition Fee',
                isRecurring: true,
                taxRate: '0.00',
              ),
            ],
            year: _year,
            campusId: 'campus-1',
          ),
          'generate': GenerateInvoicesScreen(
            repository: w.repo,
            plans: const [
              FeePlan(
                id: 'plan-1',
                name: 'Grade 5 Monthly',
                frequency: 'monthly',
                classId: 'class-1',
              ),
            ],
            classes: const [_class],
          ),
          'invoices':
              InvoicesScreen(repository: w.repo, classes: const [_class]),
          'invoice': InvoiceDetailScreen(repository: w.repo, invoiceId: 'inv-1'),
          'payment': RecordPaymentScreen(
            repository: w.repo,
            invoice: Invoice.fromJson(const {
              'id': 'inv-1',
              'student_name': 'Ali Khan',
              'period': '2026-07',
              'due_date': '2026-07-10',
              'total_amount': '5500.00',
              'paid_amount': '0.00',
              'status': 'unpaid',
            }),
          ),
          'pending': PendingPaymentsScreen(repository: w.repo),
          'receipt': ReceiptScreen(
            repository: w.repo,
            receiptId: 'rcp-1',
            receiptNumber: 'RCP-2026-001',
          ),
          'defaulters':
              DefaultersScreen(repository: w.repo, classes: const [_class]),
          'report': CollectionReportScreen(repository: w.repo),
        };

        for (final entry in screens.entries) {
          await tester.pumpWidget(MaterialApp(
            theme: dark
                ? AppTheme.dark(role: AppRole.admin)
                : AppTheme.light(role: AppRole.admin),
            home: entry.value,
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: '${entry.key} threw in $mode');
        }
      });
    }
  });

  group('responsive and accessible', () {
    for (final width in [360.0, 768.0, 1366.0]) {
      testWidgets('no finance screen overflows at ${width.toInt()}px',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final w = _wire();
        w.server.invoicesJson = '[$_invoiceJson]';
        w.server.invoiceDetailJson = _invoiceJson;
        w.server.pending.add(
          '{"id":"pay-1","invoice_id":"inv-1","student_name":"Ali Khan",'
          '"amount":1500.00,"source":"MANUAL_CASH","reference":"SLIP-12345",'
          '"received_at":"2026-09-24T00:00:00Z"}',
        );
        w.server.defaultersJson = '['
            '{"invoice_id":"i1","student_name":"Muhammad Abdul Rehman",'
            '"admission_number":"STU-0001","period":"2026-07",'
            '"due_date":"2026-07-10","status":"unpaid",'
            '"total_amount":125000.00,"paid_amount":0.00,'
            '"outstanding":125000.00}]';
        w.server.collectionJson =
            '{"totalInvoiced":1250000.00,"totalCollected":1000000.50,'
            '"outstanding":249999.50,"byClass":[{"class_name":"Grade 5",'
            '"invoiced":1250000.00,"collected":1000000.50,'
            '"outstanding":249999.50}]}';

        final screens = <String, Widget>{
          'hub': FinanceHomeScreen(
            finance: w.repo,
            setup: SetupRepository(w.dio),
            admin: AdminRepository(w.dio),
          ),
          'invoices':
              InvoicesScreen(repository: w.repo, classes: const [_class]),
          'invoice': InvoiceDetailScreen(repository: w.repo, invoiceId: 'inv-1'),
          'pending': PendingPaymentsScreen(repository: w.repo),
          'defaulters':
              DefaultersScreen(repository: w.repo, classes: const [_class]),
          'report': CollectionReportScreen(repository: w.repo),
          'receipt': ReceiptScreen(
            repository: w.repo,
            receiptId: 'rcp-1',
            receiptNumber: 'RCP-2026-001',
          ),
        };

        for (final entry in screens.entries) {
          await tester.pumpWidget(_host(entry.value));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: '${entry.key} overflowed at ${width.toInt()}px');
        }
      });
    }

    testWidgets('an invoice row carries its status in its semantics label',
        (tester) async {
      final w = _wire();
      w.server.invoicesJson = '[$_invoiceJson]';
      await tester.pumpWidget(_host(InvoicesScreen(
        repository: w.repo,
        classes: const [_class],
      )));
      await tester.pumpAndSettle();

      // The pill's colour is not the only carrier of the status — the row's
      // own label states it for a screen reader.
      expect(
        find.bySemanticsLabel(RegExp('Ali Khan.*Unpaid')),
        findsOneWidget,
      );
    });

    testWidgets('amounts survive a large text scale without overflowing',
        (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final w = _wire();
      w.server.invoicesJson = '[$_invoiceJson]';
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(role: AppRole.admin),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: InvoicesScreen(
            repository: w.repo,
            classes: const [_class],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
