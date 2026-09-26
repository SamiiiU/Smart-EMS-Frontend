import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/features/admin/data/admin_repository.dart';
import 'package:smartems/features/finance/data/finance_repository.dart';
import 'package:smartems/features/finance/domain/finance_models.dart';
import 'package:smartems/features/finance/domain/money.dart';
import 'package:smartems/features/setup/data/setup_repository.dart';

/// T14's end-to-end proof, against the REAL backend.
///
/// Walks the whole revenue path the way the screens do — fee head → fee
/// plan → generate invoices → record a payment → approve it → receipt →
/// and then checks the invoice and the defaulters list reflect it — through
/// `FinanceRepository`, the exact code path every finance screen uses. No
/// curl and no hand-written request bodies.
///
/// ```
/// flutter test test/e2e_finance_live_test.dart --dart-define=LIVE=true
/// ```
/// Without the flag it skips, and it skips again if the backend is down, so
/// the ordinary suite stays hermetic.
///
/// 🔴 **Same honest limit as T13's live test: this drives the repository,
/// not the widgets.** `flutter test` installs a fake clock, and a real HTTP
/// call started by a widget never completes inside it — the screen sits on
/// "Recording…" for ever. Driving the real screens against a live server
/// needs `integration_test`, which this project has never set up. So the
/// proof is in two halves — screens hermetically in `finance_test.dart`
/// against a stub that reproduces this backend's quirks, network live here —
/// plus one manual pass, which is the human step named in HANDOFF.md.
///
/// 🔴 **This test cannot clean up after itself.** There is no delete for a
/// fee head, a fee plan, an invoice or a payment on this backend, and an
/// approved payment cannot be reversed. Every run therefore leaves
/// permanent rows in `test-school`. They are all prefixed `E2E` and are on
/// the purge list in HANDOFF.md.
const _base = 'http://localhost:8080';

const bool _enabled = bool.fromEnvironment('LIVE');

Future<bool> _backendUp() async {
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    final req = await client.getUrl(Uri.parse('$_base/health'));
    final res = await req.close();
    await res.drain<void>();
    client.close();
    return res.statusCode == 200;
  } on Object {
    return false;
  }
}

void main() {
  test('a fee is set up, billed, paid and receipted, through the app’s own code',
      () async {
    if (!_enabled) {
      markTestSkipped('live test — pass --dart-define=LIVE=true to run it');
      return;
    }
    if (!await _backendUp()) {
      markTestSkipped('backend not running on $_base');
      return;
    }

    final dio = Dio(BaseOptions(baseUrl: _base));
    final login = await dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {
        'institutionCode': 'test-school',
        'username': 'admin',
        'password': 'Test1234!',
      },
    );
    dio.options.headers['Authorization'] =
        'Bearer ${login.data!['accessToken']}';

    final finance = FinanceRepository(dio);
    final setup = SetupRepository(dio);
    final admin = AdminRepository(dio);

    final campusId = (await admin.loadCampusIds()).first;
    final stamp = DateTime.now().millisecondsSinceEpoch.toString().substring(8);

    // The year is taken explicitly and never left to the server, because
    // the `current` flag on this backend points at an EXPIRED year.
    final years = await setup.loadYears();
    final year = years.firstWhere((y) => y.current, orElse: () => years.first);
    final schoolClass = (await setup.loadClasses()).first;

    // 1 · Fee head
    final head = await finance.createHead(
      name: 'E2E Head $stamp',
      isRecurring: true,
    );
    expect((await finance.loadHeads()).any((h) => h.id == head.id), isTrue);

    // 2 · Fee plan — an exact amount, carried as text the whole way
    const amount = '1234.56';
    final plan = await finance.createPlan(
      name: 'E2E Plan $stamp',
      frequency: 'monthly',
      classId: schoolClass.id,
      academicYearId: year.id,
      campusId: campusId,
      dueDay: 10,
      graceDays: 0,
      items: [(feeHeadId: head.id, amount: Money.parse(amount))],
    );
    expect(plan.academicYearId, year.id,
        reason: 'the plan must store the year it was given');

    // The server's own total, read back exactly — the point of the whole
    // money type. A double would have turned 1234.56 into 1234.5600000001.
    final detail = await finance.loadPlan(plan.id);
    expect(detail.total, Money.parse(amount));
    expect(detail.total!.paisa, 123456);

    // 3 · Generate, for a period far enough out that nothing collides with
    // real data. The plan itself is unique per run, so the same period is
    // safe to reuse.
    const safePeriod = '2031-03';
    final run = await finance.generate(planId: plan.id, period: safePeriod);
    expect(run.total, greaterThan(0),
        reason: 'the class must have at least one student to bill');

    // 4 · Find the invoice we just created
    final page = await finance.loadInvoices(
      classId: schoolClass.id,
      period: safePeriod,
    );
    final invoice = page.invoices.firstWhere((i) => i.totalAmount ==
        Money.parse(amount));
    expect(invoice.status, InvoiceStatus.unpaid);
    expect(invoice.outstanding, Money.parse(amount));

    // 5 · Record a PART payment — the money must NOT move yet
    final recorded = await finance.recordPayment(
      invoiceId: invoice.id,
      amount: Money.parse('34.56'),
      source: PaymentSource.bank,
      reference: 'E2E $stamp',
    );
    expect(recorded.error, isNull, reason: recorded.error ?? '');
    expect(recorded.paymentId, isNotNull);

    final beforeApproval = await finance.loadInvoice(invoice.id);
    expect(beforeApproval.paidAmount, Money.zero,
        reason: 'a pending payment must not count against the invoice');

    expect(
      (await finance.loadPending()).any((p) => p.id == recorded.paymentId),
      isTrue,
    );

    // 6 · Approve — and the receipt comes back with it
    final approval = await finance.approvePayment(recorded.paymentId!);
    expect(approval.error, isNull, reason: approval.error ?? '');
    expect(approval.result!.receiptNumber, isNotEmpty);

    final receipt = await finance.loadReceipt(approval.result!.receiptId);
    expect(receipt.amount, Money.parse('34.56'));
    expect(receipt.source, 'Bank transfer');

    // 7 · The invoice reflects it, computed by the server
    final afterApproval = await finance.loadInvoice(invoice.id);
    expect(afterApproval.paidAmount, Money.parse('34.56'));
    expect(afterApproval.status, InvoiceStatus.partial);
    expect(afterApproval.outstanding, Money.parse('1200.00'),
        reason: '1234.56 - 34.56 must be exactly 1200.00');

    // 8 · And the defaulters worklist shows what is still owed
    final defaulters = await finance.loadDefaulters(period: safePeriod);
    final row = defaulters.firstWhere((d) => d.invoiceId == invoice.id);
    expect(row.outstanding, Money.parse('1200.00'));

    // 9 · Overpayment is refused by the server, with a message worth showing
    final tooMuch = await finance.recordPayment(
      invoiceId: invoice.id,
      amount: Money.parse('99999.99'),
      source: PaymentSource.cash,
    );
    expect(tooMuch.paymentId, isNull);
    expect(tooMuch.error, contains('exceeds outstanding balance'));

    // 10 · Re-running generation for the same period does not duplicate
    final rerun = await finance.generate(planId: plan.id, period: safePeriod);
    expect(rerun.generated, 0);
    expect(rerun.skipped, greaterThan(0));
  });
}
