import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/scales.dart';
import '../../../core/widgets/adaptive_data_view.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../setup/presentation/academic_years_screen.dart' show setupListHeight;
import '../../setup/presentation/setup_scaffold.dart';
import '../data/finance_repository.dart';
import '../domain/finance_models.dart';
import 'receipt_screen.dart';
import 'reject_payment_dialog.dart';

/// The approval queue — the other half of screen 5.
///
/// Recording and approving are two different acts on this backend, and they
/// are often two different people: a clerk at the counter, an accountant
/// checking the day's takings. This is where the second one works.
///
/// Every row states that the money is not counted yet. Approval is
/// irreversible and says so before it happens; rejection is possible only
/// here, before approval.
///
/// What the server does (FeeService, unchanged by this screen):
/// - **Approve** (`fee.manage`, campus-scoped, finance step-up MFA): claims the
///   payment atomically (`... WHERE status = 'pending_approval'`; a second
///   attempt is a 409 "already processed"), re-checks the invoice balance under
///   a row lock (409 if it would overpay), adds to `paid_amount`, sets the
///   invoice partial/paid, issues a receipt and notifies guardians.
/// - **Reject** (same permission and step-up): claims the payment atomically,
///   marks it rejected and notifies guardians that it could not be verified.
///   A rejected payment can no longer be approved.
/// Step-up is handled by the network layer (prompt once, replay once). This
/// screen never decides anything itself: it shows the server's answer.
///
/// M5: the list is the shared [AdaptiveDataView] (table on wide screens, cards
/// on phones) with Approve / Reject as row actions, kept outside the row's
/// tap target. Rows themselves do not navigate.
class PendingPaymentsScreen extends StatefulWidget {
  const PendingPaymentsScreen({
    required this.repository,
    this.canDecide = true,
    super.key,
  });

  final FinanceRepository repository;

  /// Whether this account may approve/reject (the Fees hub only opens this
  /// screen for `fee.manage` campuses). Hiding the actions is a convenience:
  /// the server enforces `fee.manage` and step-up on every call.
  final bool canDecide;

  @override
  State<PendingPaymentsScreen> createState() => PendingPaymentsScreenState();
}

class PendingPaymentsScreenState extends State<PendingPaymentsScreen> {
  ScreenState<List<PendingPayment>> _state =
      const ScreenState<List<PendingPayment>>.loading();

  /// The payment an action is running for. While set, every row's actions are
  /// disabled: one financial decision at a time from this screen. (The server's
  /// atomic status claim is what guarantees exactly-once; this only prevents
  /// confusing overlapping prompts.)
  String? _busyId;
  String? _error;
  String? _notice;

  /// Set when the server says the payment is no longer pending. Distinct from
  /// [_error]: nothing failed, but THIS attempt did not process the payment.
  String? _warning;

  /// "Already processed" explanation. Never claims this attempt succeeded and
  /// never offers a receipt: only the server's success response carries one.
  String _alreadyProcessed(PendingPayment p, String message) {
    final status = FinanceRepository.processedStatus(message);
    return 'This payment (${p.amount.format()} from ${p.studentName}) was already '
        'processed${status == null ? '' : ' — it is $status'} — by someone else or by '
        'an earlier attempt. Nothing was applied again. The list has been refreshed.';
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => _state =
        ScreenState<List<PendingPayment>>.loading(previous: _state.data));
    try {
      final pending = await widget.repository.loadPending();
      if (!mounted) return;
      setState(() => _state = ScreenState<List<PendingPayment>>.data(pending));
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<List<PendingPayment>>.failed(
            f,
            cached: _state.data,
            connection:
                f.unreachable ? NetworkStatus.offline : NetworkStatus.online,
          ));
    }
  }

  Future<void> _approve(PendingPayment payment) async {
    final confirmed = await confirmAction(
      context,
      title: 'Approve this payment?',
      message: '${payment.amount.format()} from ${payment.studentName} will be '
          'counted against the invoice and a receipt will be issued. There is '
          'no way to reverse an approved payment on this system.',
      confirmLabel: 'Approve',
      irreversible: true,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _busyId = payment.id;
      _error = null;
      _notice = null;
      _warning = null;
    });
    final outcome = await widget.repository.approvePayment(payment.id);
    if (!mounted) return;
    setState(() {
      _busyId = null;
      // Not retried: the server already answered for this payment.
      _warning = outcome.alreadyProcessed ? _alreadyProcessed(payment, outcome.error!) : null;
      _error = outcome.alreadyProcessed ? null : outcome.error;
    });

    final receipt = outcome.result;
    if (receipt != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReceiptScreen(
            repository: widget.repository,
            receiptId: receipt.receiptId,
            receiptNumber: receipt.receiptNumber,
          ),
        ),
      );
    }
    await load();
  }

  Future<void> _reject(PendingPayment payment) async {
    // M5: rejection is consequential too (guardians are notified and the
    // payment can no longer be approved), so it is confirmed like approval.
    // A reason is required (sent on the existing API field). Cancel or
    // Escape return null and send nothing.
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => RejectPaymentDialog(amount: payment.amount, studentName: payment.studentName),
    );
    if (reason == null || !mounted) return;

    setState(() {
      _busyId = payment.id;
      _error = null;
      _notice = null;
      _warning = null;
    });
    final outcome = await widget.repository.rejectPaymentWithReason(payment.id, reason);
    if (!mounted) return;
    setState(() {
      _busyId = null;
      if (outcome.alreadyProcessed) {
        _warning = _alreadyProcessed(payment, outcome.error!);
      } else {
        _error = outcome.error;
        _notice = outcome.error == null
            ? 'Payment of ${payment.amount.format()} from ${payment.studentName} rejected.'
            : null;
      }
    });
    await load();
  }

  static String _received(String iso) {
    final at = DateTime.tryParse(iso);
    return at == null ? iso : DateFormat.yMMMd().format(at.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busyId != null;
    return SetupScaffold(
      title: 'Awaiting approval',
      note: const InlineAlert(
        tone: InlineAlertTone.warning,
        message: 'None of this money is counted against its invoice yet. '
            'Approving is permanent; rejecting is only possible before then.',
      ),
      children: [
        if (_error != null) ...[
          InlineAlert(tone: InlineAlertTone.danger, message: _error!),
          const SizedBox(height: AppSpacing.space5),
        ],
        if (_warning != null) ...[
          InlineAlert(tone: InlineAlertTone.warning, message: _warning!),
          const SizedBox(height: AppSpacing.space5),
        ],
        if (_notice != null) ...[
          InlineAlert(tone: InlineAlertTone.success, message: _notice!),
          const SizedBox(height: AppSpacing.space5),
        ],
        SizedBox(
          height: setupListHeight(context),
          child: ScreenStateBuilder<List<PendingPayment>>(
            state: _state,
            onRetry: load,
            emptyTitle: 'Nothing awaiting approval',
            emptyMessage: 'Payments appear here as soon as they are recorded '
                'at the counter.',
            emptyIcon: Icons.payments_outlined,
            data: (context, payments) => AdaptiveDataView<PendingPayment>(
              rows: payments,
              padding: EdgeInsets.zero,
              semanticLabel: (p) =>
                  '${p.amount.format()} from ${p.studentName}, ${p.source}, not yet counted',
              columns: [
                DataColumnSpec(label: 'Amount', value: (p) => p.amount.format(), flex: 2),
                DataColumnSpec(label: 'Learner', value: (p) => p.studentName, flex: 3),
                DataColumnSpec(label: 'Method', value: (p) => p.source, flex: 2),
                DataColumnSpec(
                  label: 'Reference',
                  value: (p) => p.reference == null || p.reference!.isEmpty ? '—' : p.reference!,
                  flex: 2,
                ),
                DataColumnSpec(label: 'Received', value: (p) => _received(p.receivedAt), flex: 2),
              ],
              actionsFlex: 4,
              rowActions: [
                RowAction<PendingPayment>(
                  label: 'Approve',
                  icon: Icons.check,
                  variant: AppButtonVariant.primary,
                  loadingLabel: 'Approving…',
                  key: (p) => Key('approve-${p.id}'),
                  semanticLabel: (p) => 'Approve ${p.amount.format()} from ${p.studentName}',
                  isVisible: (_) => widget.canDecide,
                  isLoading: (p) => _busyId == p.id,
                  isEnabled: (_) => !busy,
                  disabledReason: (_) => busy ? 'Another payment is being processed' : null,
                  onPressed: _approve,
                ),
                RowAction<PendingPayment>(
                  label: 'Reject',
                  key: (p) => Key('reject-${p.id}'),
                  semanticLabel: (p) => 'Reject ${p.amount.format()} from ${p.studentName}',
                  isVisible: (_) => widget.canDecide,
                  isEnabled: (_) => !busy,
                  disabledReason: (_) => busy ? 'Another payment is being processed' : null,
                  onPressed: _reject,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
