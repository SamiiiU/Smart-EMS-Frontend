import '../../../core/widgets/status_pill.dart';
import 'money.dart';

/// The finance domain (T14 Batch B).
///
/// Two rules run through every model here, both from the live contract:
///
/// - **Money is never computed in this app.** Each total below is a field
///   the backend sent. There is no `get total => lines.fold(...)` anywhere,
///   because two sources of truth for an invoice total eventually disagree
///   and the user has no way to tell which one is right.
/// - **Money arrives as a String**, because `FinanceJson.quoteMoney` rewrote
///   the raw body before decoding. [Money.fromJson] throws if a number slips
///   through, so a missed key fails loudly instead of drifting.

// --- Fee heads ---------------------------------------------------------------

/// A named component of a fee: tuition, transport, admission.
class FeeHead {
  const FeeHead({
    required this.id,
    required this.name,
    required this.isRecurring,
    required this.taxRate,
  });

  factory FeeHead.fromJson(Map<String, dynamic> json) => FeeHead(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        isRecurring: json['is_recurring'] as bool? ?? false,
        // A RATE, not an amount — kept as the exact text the backend sent
        // rather than turned into a number, for the same reason as money.
        taxRate: json['tax_rate'] as String? ?? '0.00',
      );

  final String id;
  final String name;
  final bool isRecurring;
  final String taxRate;

  bool get hasTax => Money.tryParse(taxRate)?.isPositive ?? false;
}

// --- Fee plans ---------------------------------------------------------------

/// One head at one amount, inside a plan.
class FeePlanItem {
  const FeePlanItem({
    required this.feeHeadId,
    required this.feeHeadName,
    required this.amount,
  });

  factory FeePlanItem.fromJson(Map<String, dynamic> json) => FeePlanItem(
        feeHeadId: json['fee_head_id'] as String? ?? '',
        feeHeadName: json['fee_head_name'] as String? ?? '',
        amount: Money.fromJson(json['amount']),
      );

  final String feeHeadId;
  final String feeHeadName;
  final Money amount;
}

/// A chargeable structure for one class in one academic year.
///
/// The list endpoint omits `items` and the totals; only the detail call
/// carries them. [hasDetail] says which one this came from, so a screen
/// never renders a blank total as though it were zero.
class FeePlan {
  const FeePlan({
    required this.id,
    required this.name,
    required this.frequency,
    required this.classId,
    this.academicYearId,
    this.dueDay,
    this.graceDays,
    this.items = const [],
    this.total,
    this.hasDetail = false,
  });

  factory FeePlan.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?)?.cast<Map<String, dynamic>>();
    return FeePlan(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      frequency: json['frequency'] as String? ?? '',
      classId: json['class_id'] as String? ?? '',
      academicYearId: json['academic_year_id'] as String?,
      dueDay: json['due_day'] as int?,
      graceDays: json['grace_days'] as int?,
      items: rawItems?.map(FeePlanItem.fromJson).toList() ?? const [],
      total: json['total'] == null ? null : Money.fromJson(json['total']),
      hasDetail: rawItems != null,
    );
  }

  final String id;
  final String name;
  final String frequency;
  final String classId;
  final String? academicYearId;
  final int? dueDay;
  final int? graceDays;
  final List<FeePlanItem> items;

  /// The backend's own total. Null on a list row, which does not carry it.
  final Money? total;
  final bool hasDetail;
}

/// What a bulk generation run did.
class GenerationResult {
  const GenerationResult({
    required this.total,
    required this.generated,
    required this.skipped,
  });

  /// ⚠️ `total` here is a COUNT of invoices, not an amount — the backend
  /// reuses the name it also uses for a plan's money total. `FinanceJson`
  /// quotes money keys by name, so this one arrives as the string `"30"`.
  /// Both forms are read rather than the key being dropped from the money
  /// set, because on a plan `total` really is money and losing it there
  /// would put an amount through a double.
  factory GenerationResult.fromJson(Map<String, dynamic> json) =>
      GenerationResult(
        total: _count(json['total']),
        generated: _count(json['generated']),
        skipped: _count(json['skipped']),
      );

  static int _count(Object? value) => switch (value) {
        final int i => i,
        final String s => int.tryParse(s) ?? 0,
        _ => 0,
      };

  final int total;
  final int generated;
  final int skipped;
}

// --- Invoices ----------------------------------------------------------------

/// The three statuses this backend actually uses. There is no `overdue` —
/// see [Invoice.isOverdue], which derives it from the due date.
enum InvoiceStatus {
  unpaid,
  partial,
  paid;

  static InvoiceStatus parse(String? raw) => switch (raw) {
        'paid' => InvoiceStatus.paid,
        'partial' => InvoiceStatus.partial,
        _ => InvoiceStatus.unpaid,
      };

  AppStatus get pill => switch (this) {
        InvoiceStatus.unpaid => AppStatus.unpaid,
        InvoiceStatus.partial => AppStatus.partial,
        InvoiceStatus.paid => AppStatus.paid,
      };
}

class InvoiceLine {
  const InvoiceLine({required this.description, required this.total});

  factory InvoiceLine.fromJson(Map<String, dynamic> json) => InvoiceLine(
        description: json['description'] as String? ?? '',
        total: Money.fromJson(json['total']),
      );

  final String description;
  final Money total;
}

class Invoice {
  const Invoice({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.period,
    required this.dueDate,
    required this.totalAmount,
    required this.paidAmount,
    required this.status,
    this.lines = const [],
    this.hasLines = false,
  });

  factory Invoice.fromJson(Map<String, dynamic> json) {
    final rawLines = (json['lines'] as List?)?.cast<Map<String, dynamic>>();
    return Invoice(
      id: json['id'] as String,
      studentId: json['student_id'] as String? ?? '',
      studentName: json['student_name'] as String? ?? '',
      period: json['period'] as String? ?? '',
      dueDate: json['due_date'] as String? ?? '',
      totalAmount: Money.fromJson(json['total_amount']),
      paidAmount: Money.fromJson(json['paid_amount'], fallback: Money.zero),
      status: InvoiceStatus.parse(json['status'] as String?),
      lines: rawLines?.map(InvoiceLine.fromJson).toList() ?? const [],
      hasLines: rawLines != null,
    );
  }

  final String id;
  final String studentId;
  final String studentName;
  final String period;
  final String dueDate;

  /// Both server-computed. Never derived from [lines].
  final Money totalAmount;
  final Money paidAmount;

  final InvoiceStatus status;
  final List<InvoiceLine> lines;
  final bool hasLines;

  /// What is still owed.
  ///
  /// This is a SUBTRACTION of two server figures, not a re-derivation of
  /// either, and it is exact because both are integer paisa. The defaulters
  /// endpoint computes the same thing and the two agree — checked live.
  Money get outstanding => totalAmount - paidAmount;

  /// Derived on the client, because the API has no overdue status.
  bool isOverdue(DateTime today) {
    if (status == InvoiceStatus.paid) return false;
    final due = DateTime.tryParse(dueDate);
    if (due == null) return false;
    return due.isBefore(DateTime(today.year, today.month, today.day));
  }

  int daysOverdue(DateTime today) {
    final due = DateTime.tryParse(dueDate);
    if (due == null) return 0;
    final midnight = DateTime(today.year, today.month, today.day);
    final days = midnight.difference(due).inDays;
    return days > 0 ? days : 0;
  }
}

/// One page of the invoice list. The envelope is this endpoint's own shape —
/// `{size, content, page, totalElements}`, not Spring's `Page`.
class InvoicePage {
  const InvoicePage({required this.invoices, required this.totalElements});

  final List<Invoice> invoices;
  final int totalElements;
}

// --- Payments ----------------------------------------------------------------

/// The only two payment sources this backend accepts. Anything else is a
/// 400, so the form offers exactly these — no cheque, card or online, however
/// normal those are in a Pakistani school (open item 17).
enum PaymentSource {
  cash('MANUAL_CASH', 'Cash'),
  bank('MANUAL_BANK', 'Bank transfer');

  const PaymentSource(this.wire, this.label);

  final String wire;
  final String label;

  static String labelForWire(String? wire) => switch (wire) {
        'MANUAL_BANK' => 'Bank transfer',
        'MANUAL_CASH' => 'Cash',
        _ => wire ?? '',
      };
}

/// A recorded payment awaiting approval. The money is NOT on the invoice yet.
class PendingPayment {
  const PendingPayment({
    required this.id,
    required this.invoiceId,
    required this.studentName,
    required this.amount,
    required this.source,
    required this.reference,
    required this.receivedAt,
  });

  factory PendingPayment.fromJson(Map<String, dynamic> json) => PendingPayment(
        id: json['id'] as String,
        invoiceId: json['invoice_id'] as String? ?? '',
        studentName: json['student_name'] as String? ?? '',
        amount: Money.fromJson(json['amount']),
        source: PaymentSource.labelForWire(json['source'] as String?),
        reference: json['reference'] as String?,
        receivedAt: json['received_at'] as String? ?? '',
      );

  final String id;
  final String invoiceId;
  final String studentName;
  final Money amount;
  final String source;
  final String? reference;
  final String receivedAt;
}

/// What approval returns. The receipt is keyed by [receiptId] — NOT by the
/// payment id, which stops resolving entirely once a payment is approved.
class ApprovalResult {
  const ApprovalResult({
    required this.receiptId,
    required this.receiptNumber,
    required this.amount,
  });

  factory ApprovalResult.fromJson(Map<String, dynamic> json) => ApprovalResult(
        receiptId: json['receiptId'] as String? ?? '',
        receiptNumber: json['receiptNumber'] as String? ?? '',
        amount: Money.fromJson(json['amount']),
      );

  final String receiptId;
  final String receiptNumber;
  final Money amount;
}

class Receipt {
  const Receipt({
    required this.id,
    required this.receiptNumber,
    required this.generatedAt,
    required this.amount,
    required this.source,
    required this.studentName,
    required this.invoiceId,
  });

  factory Receipt.fromJson(Map<String, dynamic> json) => Receipt(
        id: json['id'] as String,
        receiptNumber: json['receipt_number'] as String? ?? '',
        generatedAt: json['generated_at'] as String? ?? '',
        amount: Money.fromJson(json['amount']),
        source: PaymentSource.labelForWire(json['source'] as String?),
        studentName: json['student_name'] as String? ?? '',
        invoiceId: json['invoice_id'] as String? ?? '',
      );

  final String id;
  final String receiptNumber;
  final String generatedAt;
  final Money amount;
  final String source;
  final String studentName;
  final String invoiceId;
}

// --- Reports -----------------------------------------------------------------

class ClassCollection {
  const ClassCollection({
    required this.className,
    required this.invoiced,
    required this.collected,
    required this.outstanding,
  });

  factory ClassCollection.fromJson(Map<String, dynamic> json) =>
      ClassCollection(
        className: json['class_name'] as String? ?? '',
        invoiced: Money.fromJson(json['invoiced']),
        collected: Money.fromJson(json['collected']),
        outstanding: Money.fromJson(json['outstanding']),
      );

  final String className;
  final Money invoiced;
  final Money collected;
  final Money outstanding;
}

/// Whole-school, all-time totals. The endpoint ignores every filter it
/// accepts (verified with `period=1999-01`), so there is nothing to scope by
/// and the screen says so.
class CollectionReport {
  const CollectionReport({
    required this.totalInvoiced,
    required this.totalCollected,
    required this.outstanding,
    required this.byClass,
  });

  factory CollectionReport.fromJson(Map<String, dynamic> json) =>
      CollectionReport(
        totalInvoiced: Money.fromJson(json['totalInvoiced']),
        totalCollected: Money.fromJson(json['totalCollected']),
        outstanding: Money.fromJson(json['outstanding']),
        byClass: (json['byClass'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ClassCollection.fromJson)
            .toList(),
      );

  final Money totalInvoiced;
  final Money totalCollected;
  final Money outstanding;
  final List<ClassCollection> byClass;
}

/// One unpaid or partly-paid invoice, as the defaulters endpoint reports it.
class DefaulterRow {
  const DefaulterRow({
    required this.invoiceId,
    required this.studentName,
    required this.admissionNumber,
    required this.period,
    required this.dueDate,
    required this.outstanding,
    required this.status,
  });

  factory DefaulterRow.fromJson(Map<String, dynamic> json) => DefaulterRow(
        invoiceId: json['invoice_id'] as String? ?? '',
        studentName: json['student_name'] as String? ?? '',
        admissionNumber: json['admission_number'] as String? ?? '',
        period: json['period'] as String? ?? '',
        dueDate: json['due_date'] as String? ?? '',
        // Server-computed. Not total minus paid, done again here.
        outstanding: Money.fromJson(json['outstanding']),
        status: InvoiceStatus.parse(json['status'] as String?),
      );

  final String invoiceId;
  final String studentName;
  final String admissionNumber;
  final String period;
  final String dueDate;
  final Money outstanding;
  final InvoiceStatus status;

  int daysOverdue(DateTime today) {
    final due = DateTime.tryParse(dueDate);
    if (due == null) return 0;
    final days =
        DateTime(today.year, today.month, today.day).difference(due).inDays;
    return days > 0 ? days : 0;
  }
}

/// D-15's rule applied to money: a worklist is ordered by what needs doing.
///
/// Largest outstanding first, and the longest overdue breaks a tie. An
/// accountant opens this to decide who to phone before lunch; alphabetical
/// order would bury the PKR 80,000 debt under three PKR 200 ones.
List<DefaulterRow> sortDefaulters(List<DefaulterRow> rows, DateTime today) {
  final sorted = [...rows];
  sorted.sort((a, b) {
    final byAmount = b.outstanding.compareTo(a.outstanding);
    if (byAmount != 0) return byAmount;
    final byAge = b.daysOverdue(today).compareTo(a.daysOverdue(today));
    if (byAge != 0) return byAge;
    return a.studentName.compareTo(b.studentName);
  });
  return sorted;
}
