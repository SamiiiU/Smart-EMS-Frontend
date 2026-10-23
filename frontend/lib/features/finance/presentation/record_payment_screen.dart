import '../data/payment_intent_store.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/confirm_dialog.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/theme/sizing.dart';
import '../../setup/presentation/sections_screen.dart' show PickerChip;
import '../../setup/presentation/setup_scaffold.dart';
import '../data/finance_repository.dart';
import '../domain/finance_models.dart';
import '../domain/money.dart';
import 'receipt_screen.dart';
import 'reject_payment_dialog.dart';

/// Screen 5: record a payment.
///
/// Approval is a SEPARATE step on this backend, and the screen is built
/// around saying so. A recorded payment sits at `pending_approval` and the
/// invoice's paid total does not move until someone approves it. An
/// accountant who believes the money is banked when it is pending will
/// reconcile against a number that does not exist, so the state is stated
/// before recording and again after.
///
/// What this screen deliberately does NOT offer, because the API does not
/// support it (D-19):
///  - **a payment date.** `receivedAt`, `paidAt`, `paymentDate` and `date`
///    are all silently ignored; the server stamps its own clock. Rather
///    than a date field that quietly does nothing, the screen says the
///    payment is recorded as of now.
///  - **cheque, card or online.** `source` accepts `MANUAL_CASH` and
///    `MANUAL_BANK` and 400s on anything else.
///  - **an edit or a reversal.** Once approved a payment is permanent.
class RecordPaymentScreen extends StatefulWidget {
  const RecordPaymentScreen({
    required this.repository,
    required this.invoice,
    super.key,
  });

  final FinanceRepository repository;
  final Invoice invoice;

  @override
  State<RecordPaymentScreen> createState() => RecordPaymentScreenState();
}

class RecordPaymentScreenState extends State<RecordPaymentScreen> {
  String _amount = '';
  String _reference = '';
  PaymentSource _source = PaymentSource.cash;

  PaymentIntent? _intent;
  bool _restoreFailed = false;

  /// True when the pending payment on screen was restored from an earlier,
  /// unconfirmed attempt; false when it was recorded just now (NOTE-QA-10).
  bool _restoredPending = false;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _restoreIntent(initial: true);
  }

  Future<void> _restoreIntent({bool initial = false}) async {
    try {
      final intent = await widget.repository.pendingPaymentIntent(
        widget.invoice.id,
      );
      if (!mounted) return;
      setState(() {
        _intent = intent;
        if (intent != null) {
          _amount = intent.amount;
          _reference = intent.reference ?? '';
          _source = PaymentSource.values.firstWhere(
            (s) => s.wire == intent.source,
          );
          _pendingPaymentId = intent.paymentId;
          // Only an intent found when the screen OPENS is "restored"; the reload
          // right after recording must keep the fresh-payment wording.
          if (initial) _restoredPending = intent.paymentId != null;
          _pendingAmount = intent.paymentId == null
              ? null
              : Money.parse(intent.amount);
        }
        _busy = false;
      });
    } catch (e) {
      // Type only — never the stored payment details.
      debugPrint('Payment intent restore failed: ${e.runtimeType}');
      if (mounted) {
        setState(() {
          _busy = false;
          _restoreFailed = true;
          _error =
              'Saved payment recovery is unavailable. Reopen this screen after storage is restored.';
        });
      }
    }
  }

  String? _error;

  /// The recorded-but-not-yet-approved payment, once there is one.
  String? _pendingPaymentId;
  Money? _pendingAmount;

  Money? get _parsedAmount {
    final text = _amount.trim();
    if (text.isEmpty) return null;
    final money = Money.tryParse(text);
    if (money == null || !money.isPositive) return null;
    return money;
  }

  /// Checked here as well as by the server, so the clerk is told before the
  /// round trip. The server enforces it regardless — its message wins.
  bool get _overOutstanding {
    final amount = _parsedAmount;
    return amount != null && amount.compareTo(widget.invoice.outstanding) > 0;
  }

  Future<void> _record() async {
    if (_busy || _restoreFailed) return;
    final amount = _parsedAmount;
    if (amount == null) return;

    // M5: recording creates a financial record, so it is confirmed first.
    // Cancel/Escape send nothing. A retry re-sends the ORIGINAL details with
    // the ORIGINAL idempotency key (the repository enforces this), so a
    // payment the server already has is returned, never duplicated.
    final retry = _intent != null;
    final confirmed = await confirmAction(
      context,
      title: retry ? 'Retry the original payment?' : 'Record this payment?',
      message: '${amount.format()} via ${_source.label} for '
          '${widget.invoice.studentName} (${widget.invoice.period}). '
          '${retry ? 'The original details and request key are reused, so it cannot be recorded twice. ' : ''}'
          'It will await approval and does not count against the invoice until approved.',
      confirmLabel: retry ? 'Retry' : 'Record',
      confirmKey: const Key('confirm-record-payment'),
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.repository.recordPayment(
      invoiceId: widget.invoice.id,
      amount: amount,
      source: _source,
      reference: _reference.trim().isEmpty ? null : _reference.trim(),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.error;
      _pendingPaymentId = result.paymentId;
      _pendingAmount = result.paymentId == null ? null : amount;
      _restoredPending = false;
    });
    await _restoreIntent();
  }

  Future<void> _approve() async {
    final id = _pendingPaymentId;
    if (id == null) return;

    final confirmed = await confirmAction(
      context,
      title: 'Approve this payment?',
      message: '${_pendingAmount?.format() ?? 'The payment'} will be counted against this '
          'invoice and a receipt will be issued. There is no way to reverse or cancel an '
          'approved payment on this system.',
      confirmLabel: 'Approve',
      irreversible: true,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await widget.repository.approvePayment(id);
    if (!mounted) return;
    if (outcome.alreadyProcessed) {
      await _alreadyProcessed(id, outcome.error!);
      return;
    }
    setState(() {
      _busy = false;
      _error = outcome.error;
    });

    final receipt = outcome.result;
    if (receipt != null && mounted) {
      try {
        await widget.repository.finishPaymentIntent(widget.invoice.id, id);
      } catch (_) {}
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ReceiptScreen(
            repository: widget.repository,
            receiptId: receipt.receiptId,
            receiptNumber: receipt.receiptNumber,
          ),
        ),
      );
    }
  }

  /// The server says this payment is no longer pending (decided elsewhere or
  /// by an earlier attempt). Nothing was applied by THIS attempt, no receipt
  /// is shown, nothing is retried. Its local tracking is cleared because the
  /// record it protects already exists on the server.
  Future<void> _alreadyProcessed(String id, String message) async {
    final status = FinanceRepository.processedStatus(message);
    try {
      await widget.repository.finishPaymentIntent(widget.invoice.id, id);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = null;
      _warning = 'This payment was already processed'
          '${status == null ? '' : ' — it is $status'} — by someone else or by an '
          'earlier attempt. Nothing was applied again. Go back to the invoice to '
          'see its current balance.';
    });
  }

  String? _warning;

  Future<void> _reject() async {
    final id = _pendingPaymentId;
    if (id == null) return;
    // M5: a reason is required and the action is confirmed (shared dialog).
    final reason = await showRejectPaymentDialog(
      context,
      amount: _pendingAmount ?? widget.invoice.outstanding,
      studentName: widget.invoice.studentName,
    );
    if (reason == null || !mounted) return;
    setState(() {
      _busy = true;
      _warning = null;
    });
    final outcome = await widget.repository.rejectPaymentWithReason(id, reason);
    if (outcome.alreadyProcessed) {
      await _alreadyProcessed(id, outcome.error!);
      return;
    }
    final error = outcome.error;
    if (error == null) {
      try {
        await widget.repository.finishPaymentIntent(widget.invoice.id, id);
      } catch (_) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error =
                'Payment rejected, but its saved tracking could not be cleared. Reopen after storage is restored.';
          });
        }
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (error == null) {
        _intent = null;
        _pendingPaymentId = null;
        _pendingAmount = null;
        _amount = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final invoice = widget.invoice;
    final recorded = _pendingPaymentId != null;

    return SetupScaffold(
      title: 'Record a payment',
      note: InlineAlert(
        tone: InlineAlertTone.info,
        message:
            '${invoice.studentName} · ${invoice.period} · '
            '${invoice.outstanding.format()} outstanding.',
      ),
      children: [
        _PaymentSummary(
          outstanding: invoice.outstanding,
          entered: recorded ? _pendingAmount : _parsedAmount,
          recorded: recorded,
        ),
        const SizedBox(height: AppSpacing.space5),
        if (!recorded) ...[
          if (_intent != null)
            InlineAlert(
              tone: InlineAlertTone.warning,
              message:
                  'Saved payment: ${Money.parse(_intent!.amount).format()} via ${PaymentSource.labelForWire(_intent!.source)}. Its result is not confirmed. Retry these original details to avoid a duplicate.',
            ),
          if (_intent == null) ...[
            SetupField(
              label: 'Amount received',
              value: _amount,
              placeholder: '0.00',
              onChanged: (v) => setState(() => _amount = v),
            ),
            if (_amount.trim().isNotEmpty && _parsedAmount == null)
              Text(
                'Enter an amount in rupees, with at most two decimals — '
                'for example 2500 or 2500.50.',
                style: AppTypography.bodyAdminMeta.copyWith(color: t.danger),
              ),
            if (_overOutstanding)
              Text(
                'That is more than the ${invoice.outstanding.format()} still '
                'owed on this invoice.',
                style: AppTypography.bodyAdminMeta.copyWith(color: t.danger),
              ),
            const SizedBox(height: AppSpacing.space4),
            Text(
              'How it was paid',
              style: AppTypography.fieldLabel.copyWith(color: t.textSecondary),
            ),
            const SizedBox(height: AppSpacing.space2),
            Wrap(
              spacing: AppSpacing.space2,
              runSpacing: AppSpacing.space2,
              children: [
                for (final source in PaymentSource.values)
                  PickerChip(
                    label: source.label,
                    selected: _source == source,
                    onTap: () => setState(() => _source = source),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(
              'Cheque, card and online are not available — this system only '
              'records cash, bank transfer and bank challan payments.',
              style: AppTypography.bodyAdminMeta.copyWith(
                color: t.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.space5),
            SetupField(
              label: 'Reference (optional)',
              value: _reference,
              placeholder: 'Slip or transaction number',
              onChanged: (v) => setState(() => _reference = v),
            ),
            const SizedBox(height: AppSpacing.space4),
          ],
          // The two things about this payment the clerk cannot change.
          const InlineAlert(
            tone: InlineAlertTone.warning,
            message:
                'The payment is dated when it is recorded — an earlier '
                'date cannot be entered. It also has to be approved before '
                'it counts against the invoice.',
          ),
          const SizedBox(height: AppSpacing.space6),
          AppButton(
            label: _busy
                ? 'Recording…'
                : _intent != null
                ? 'Retry original payment'
                : 'Record payment',
            fullWidth: true,
            onPressed:
                _busy ||
                    _restoreFailed ||
                    _parsedAmount == null ||
                    (_intent == null && _overOutstanding)
                ? null
                : _record,
          ),
        ] else ...[
          InlineAlert(
            tone: InlineAlertTone.warning,
            key: const Key('recorded-payment-notice'),
            // NOTE-QA-10: a payment recorded just now is not "restored"; only
            // a payment brought back from an earlier, unconfirmed attempt asks
            // the user to review the current status first. Neither wording
            // says it is approved or collected: only the server decides that.
            message: _restoredPending
                ? '${_pendingAmount?.format() ?? 'A payment'} from an earlier '
                    'attempt is recorded and still awaiting approval. The displayed '
                    'outstanding balance is ${invoice.outstanding.format()}. Check '
                    'the current status before approving it.'
                : '${_pendingAmount?.format() ?? 'The payment'} has been '
                    'recorded and is awaiting approval. It counts against the '
                    'invoice only after approval. Approve it now to issue a '
                    'receipt, or leave it in the approval queue.',
          ),
          const SizedBox(height: AppSpacing.space6),
          AppButton(
            label: _busy ? 'Approving…' : 'Approve and issue receipt',
            fullWidth: true,
            onPressed: _busy ? null : _approve,
          ),
          const SizedBox(height: AppSpacing.space4),
          AppButton(
            label: 'Reject this payment',
            variant: AppButtonVariant.secondary,
            fullWidth: true,
            onPressed: _busy ? null : _reject,
          ),
          const SizedBox(height: AppSpacing.space3),
          AppButton(
            label: 'Done',
            variant: AppButtonVariant.secondary,
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await widget.repository.finishPaymentIntent(
                        widget.invoice.id,
                        _pendingPaymentId!,
                      );
                      if (context.mounted) { Navigator.of(context).pop(); }
                    } catch (_) {
                      if (mounted) {
                        setState(() {
                          _busy = false;
                          _error =
                              'Saved tracking could not be cleared. Try again after storage is restored.';
});
}
                    }
                  },
          ),
          const SizedBox(height: AppSpacing.space3),
          Text(
            'Rejecting is only possible now, before approval. Afterwards a '
            'payment cannot be changed or reversed.',
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          ),
        ],

        if (_warning != null) ...[
          const SizedBox(height: AppSpacing.space5),
          InlineAlert(
            key: const Key('payment-already-processed'),
            tone: InlineAlertTone.warning,
            message: _warning!,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.space5),
          // The backend's own message. "Amount 999999.99 exceeds outstanding
          // balance 5499.00" tells the clerk exactly what to do, and nothing
          // this app could write would be more useful.
          InlineAlert(tone: InlineAlertTone.danger, message: _error!),
        ],

        const SizedBox(height: AppSpacing.space5),
        const InlineAlert(
          tone: InlineAlertTone.info,
          message:
              'Payments cannot be recorded while offline. An interrupted response '
              'does not prove the payment failed. Its original details are saved '
              'for a safe retry; do not enter it as a new payment.',
        ),
      ],
    );
  }
}

/// What this payment is against: the server's outstanding balance and the
/// amount typed (or recorded). Deliberately no "balance after payment" — that
/// would be a new calculation, and a pending payment changes nothing yet.
class _PaymentSummary extends StatelessWidget {
  const _PaymentSummary({required this.outstanding, required this.entered, required this.recorded});

  final Money outstanding;
  final Money? entered;
  final bool recorded;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget tile(String label, String value, {Key? key}) => Expanded(
          child: MergeSemantics(
            key: key,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.space5),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: t.border, width: AppSizing.borderThin),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTypography.caption.copyWith(color: t.textSecondary)),
                  const SizedBox(height: AppSpacing.space2),
                  Text(value, style: AppTypography.sectionHeading.copyWith(color: t.textPrimary)),
                ],
              ),
            ),
          ),
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tile('Outstanding on invoice', outstanding.format(), key: const Key('summary-outstanding')),
        const SizedBox(width: AppSpacing.space4),
        tile(recorded ? 'Recorded, awaiting approval' : 'This payment', entered?.format() ?? '—',
            key: const Key('summary-payment')),
      ],
    );
  }
}
