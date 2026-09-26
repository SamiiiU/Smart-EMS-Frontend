import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/features/finance/domain/finance_models.dart';
import 'package:smartems/features/finance/domain/money.dart';

/// The money gate for T14.
///
/// These are not ordinary unit tests. Each one pins a property that, if it
/// broke, would produce a receipt that disagrees with the ledger — the
/// failure that destroys an accountant's trust in the product and is almost
/// impossible to debug after the fact, because every individual number looks
/// right.
void main() {
  group('no money value ever passes through a double', () {
    test('money.dart mentions no floating-point type at all', () {
      // The strongest form of the guarantee available: the file that owns
      // every money value has no way to reach a double, checked against its
      // own source rather than against one code path a test happens to take.
      final source =
          File('lib/features/finance/domain/money.dart').readAsStringSync();
      final code = source
          .split('\n')
          .where((line) {
            final trimmed = line.trimLeft();
            return !trimmed.startsWith('///') && !trimmed.startsWith('//');
          })
          .join('\n');

      for (final banned in ['double', 'toDouble', 'num ', 'parseDouble']) {
        expect(
          code.contains(banned),
          isFalse,
          reason: 'money.dart contains "$banned". Money is integer paisa; a '
              'single double anywhere in this file reintroduces the drift '
              'the whole type exists to prevent.',
        );
      }
    });

    test('a money field arriving as a NUMBER is rejected, not coerced', () {
      // If a money key were ever missed in FinanceJson.moneyKeys, jsonDecode
      // would hand us a double. That must fail loudly rather than quietly
      // becoming an amount.
      expect(
        () => Money.fromJson(5500.00),
        throwsA(isA<FormatException>()),
      );
      expect(() => Money.fromJson(5500), throwsA(isA<FormatException>()));
    });

    test('the decoder hands money to the app as text, never as a number', () {
      // Exactly the body shape the live backend returns.
      const raw =
          '{"total_amount":5500.00,"paid_amount":0.10,"status":"unpaid"}';
      final decoded =
          jsonDecode(FinanceJson.quoteMoney(raw)) as Map<String, dynamic>;

      expect(decoded['total_amount'], isA<String>());
      expect(decoded['total_amount'], '5500.00');
      expect(decoded['paid_amount'], isA<String>());
      // Untouched: a non-money field is still decoded normally.
      expect(decoded['status'], 'unpaid');
    });

    test('0.10 + 0.20 is exactly 0.30, which doubles cannot manage', () {
      final a = Money.parse('0.10');
      final b = Money.parse('0.20');
      expect(a + b, Money.parse('0.30'));
      expect((a + b).paisa, 30);

      // The same sum in the type this code refuses to use, for the record.
      expect(0.1 + 0.2 == 0.3, isFalse);
    });

    test('a hundred lines of 0.07 add up exactly', () {
      var total = Money.zero;
      for (var i = 0; i < 100; i++) {
        total = total + Money.parse('0.07');
      }
      expect(total, Money.parse('7.00'));
    });

    test('a third decimal is refused rather than silently rounded', () {
      // The backend rounds 1.005 to 1.01. Accepting the input here would
      // mean showing a number the server did not store.
      expect(Money.tryParse('1.005'), isNull);
      expect(Money.tryParse('1.05'), isNotNull);
      expect(Money.tryParse(''), isNull);
      expect(Money.tryParse('abc'), isNull);
      expect(Money.tryParse('12.'), isNotNull);
      expect(Money.tryParse('1,000'), isNull);
    });

    test('one decimal place is read as tenths, not hundredths', () {
      expect(Money.parse('12.5').paisa, 1250);
      expect(Money.parse('12.05').paisa, 1205);
    });
  });

  group('formatting', () {
    test('a fractional amount keeps both decimals', () {
      expect(Money.parse('2500.50').format(), 'PKR 2,500.50');
      expect(Money.parse('0.07').format(), 'PKR 0.07');
      expect(Money.parse('99.9').format(), 'PKR 99.90');
    });

    test('an amount above 100,000 is grouped in thousands', () {
      expect(Money.parse('125000').format(), 'PKR 125,000.00');
      expect(Money.parse('1234567.89').format(), 'PKR 1,234,567.89');
      expect(Money.parse('100000.01').format(), 'PKR 100,000.01');
    });

    test('small amounts are not grouped', () {
      expect(Money.parse('999.99').format(), 'PKR 999.99');
      expect(Money.zero.format(), 'PKR 0.00');
    });

    test('a negative amount keeps its sign inside the currency', () {
      expect(Money.parse('-1500').format(), 'PKR -1,500.00');
    });

    test('what goes back to the backend is a plain decimal, always 2dp', () {
      expect(Money.parse('2500').toBackendString(), '2500.00');
      expect(Money.parse('0.07').toBackendString(), '0.07');
      expect(Money.parse('12.5').toBackendString(), '12.50');
    });
  });

  group('totals come from the server, never from the client', () {
    test('an invoice reports the total the backend sent, not the line sum',
        () {
      // Lines that deliberately do NOT add up to the total — a discount, a
      // waiver, anything the app does not know about. The invoice must
      // report what the server says it owes.
      final invoice = Invoice.fromJson({
        'id': 'inv-1',
        'student_name': 'Ali Khan',
        'period': '2026-07',
        'due_date': '2026-07-10',
        'total_amount': '5000.00',
        'paid_amount': '0.00',
        'status': 'unpaid',
        'lines': [
          {'description': 'Tuition Fee', 'total': '5000.00'},
          {'description': 'Exam Fee', 'total': '500.00'},
        ],
      });

      expect(invoice.totalAmount, Money.parse('5000.00'));
      expect(invoice.totalAmount, isNot(Money.parse('5500.00')),
          reason: 'the line sum must not win over the server total');
    });

    test('outstanding is the difference of two server figures, exactly', () {
      final invoice = Invoice.fromJson({
        'id': 'inv-1',
        'student_name': 'Ali Khan',
        'period': '2026-07',
        'due_date': '2026-07-10',
        'total_amount': '5500.00',
        'paid_amount': '0.01',
        'status': 'partial',
      });
      expect(invoice.outstanding, Money.parse('5499.99'));
    });

    test('a collection report keeps the totals the endpoint computed', () {
      final report = CollectionReport.fromJson({
        // Deliberately not the sum of byClass: the endpoint owns both, and
        // the screen must not "correct" one with the other.
        'totalInvoiced': '9000.00',
        'totalCollected': '1.00',
        'outstanding': '8999.00',
        'byClass': [
          {
            'class_name': 'Grade 5',
            'invoiced': '5500.00',
            'collected': '1.00',
            'outstanding': '5499.00',
          },
        ],
      });
      expect(report.totalInvoiced, Money.parse('9000.00'));
      expect(report.byClass.single.invoiced, Money.parse('5500.00'));
    });
  });

  test('a COUNT named "total" is not mistaken for an amount', () {
    // The backend reuses `total` for a plan's money total AND for a count of
    // invoices in a generation run. The money decoder quotes it by name, so
    // the count arrives as text. Dropping the key from the money set would
    // put a real amount through a double instead, so the count is read
    // either way — a regression a widget test caught first.
    final quoted = jsonDecode(FinanceJson.quoteMoney(
      '{"total":30,"generated":0,"skipped":30}',
    )) as Map<String, dynamic>;

    final result = GenerationResult.fromJson(quoted);
    expect(result.total, 30);
    expect(result.skipped, 30);
    expect(result.generated, 0);

    // And the same field as an unquoted int still works.
    expect(
      GenerationResult.fromJson(const {
        'total': 1,
        'generated': 1,
        'skipped': 0,
      }).total,
      1,
    );
  });

  group('the defaulters worklist is ordered by what needs action', () {
    DefaulterRow row(String name, String outstanding, String due) =>
        DefaulterRow.fromJson({
          'invoice_id': 'inv-$name',
          'student_name': name,
          'admission_number': 'STU-$name',
          'period': '2026-07',
          'due_date': due,
          'outstanding': outstanding,
          'status': 'unpaid',
        });

    test('largest outstanding first, not alphabetical', () {
      final today = DateTime(2026, 9, 24);
      final sorted = sortDefaulters([
        row('Aisha', '200.00', '2026-07-10'),
        row('Zara', '80000.00', '2026-07-10'),
        row('Bilal', '500.00', '2026-07-10'),
      ], today);

      expect(sorted.map((r) => r.studentName), ['Zara', 'Bilal', 'Aisha']);
    });

    test('equal debts are broken by who has been late longest', () {
      final today = DateTime(2026, 9, 24);
      final sorted = sortDefaulters([
        row('Recent', '500.00', '2026-09-01'),
        row('Ancient', '500.00', '2026-01-01'),
      ], today);

      expect(sorted.first.studentName, 'Ancient');
    });
  });

  group('invoice status', () {
    test('the three statuses this backend actually uses map to pills', () {
      expect(InvoiceStatus.parse('unpaid'), InvoiceStatus.unpaid);
      expect(InvoiceStatus.parse('partial'), InvoiceStatus.partial);
      expect(InvoiceStatus.parse('paid'), InvoiceStatus.paid);
    });

    test('overdue is derived from the due date, because there is no status',
        () {
      Invoice at(String due, String status) => Invoice.fromJson({
            'id': 'i',
            'student_name': 'A',
            'period': '2026-07',
            'due_date': due,
            'total_amount': '100.00',
            'paid_amount': '0.00',
            'status': status,
          });

      final today = DateTime(2026, 9, 24);
      expect(at('2026-07-10', 'unpaid').isOverdue(today), isTrue);
      expect(at('2026-07-10', 'unpaid').daysOverdue(today), 76);
      expect(at('2026-12-10', 'unpaid').isOverdue(today), isFalse);
      // A paid invoice is never overdue, however old.
      expect(at('2020-01-01', 'paid').isOverdue(today), isFalse);
    });
  });

  group('payment sources', () {
    test('only the two the backend accepts exist', () {
      expect(PaymentSource.values.map((s) => s.wire),
          ['MANUAL_CASH', 'MANUAL_BANK']);
    });
  });
}
