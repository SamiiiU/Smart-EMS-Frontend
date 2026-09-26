import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../setup/presentation/sections_screen.dart' show PickerChip;
import '../../setup/presentation/setup_scaffold.dart';
import '../data/finance_repository.dart';
import '../domain/finance_models.dart';
import '../domain/money.dart';
import 'receipt_screen.dart';

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

  bool _busy = false;
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
    final amount = _parsedAmount;
    if (amount == null) return;

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
    });
  }

  Future<void> _approve() async {
    final id = _pendingPaymentId;
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Approve this payment?'),
        content: Text(
          '${_pendingAmount?.format() ?? ''} will be counted against this '
          'invoice and a receipt will be issued.\n\n'
          'This cannot be undone. There is no way to reverse or cancel an '
          'approved payment on this system.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await widget.repository.approvePayment(id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = outcome.error;
    });

    final receipt = outcome.result;
    if (receipt != null && mounted) {
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

  Future<void> _reject() async {
    final id = _pendingPaymentId;
    if (id == null) return;
    setState(() => _busy = true);
    final error = await widget.repository.rejectPayment(id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (error == null) {
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
        message: '${invoice.studentName} · ${invoice.period} · '
            '${invoice.outstanding.format()} outstanding.',
      ),
      children: [
        if (!recorded) ...[
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
            'accepts cash and bank transfer.',
            style:
                AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space5),
          SetupField(
            label: 'Reference (optional)',
            value: _reference,
            placeholder: 'Slip or transaction number',
            onChanged: (v) => setState(() => _reference = v),
          ),
          const SizedBox(height: AppSpacing.space4),

          // The two things about this payment the clerk cannot change.
          const InlineAlert(
            tone: InlineAlertTone.warning,
            message: 'The payment is dated when it is recorded — an earlier '
                'date cannot be entered. It also has to be approved before '
                'it counts against the invoice.',
          ),
          const SizedBox(height: AppSpacing.space6),
          AppButton(
            label: _busy ? 'Recording…' : 'Record payment',
            fullWidth: true,
            onPressed: _busy || _parsedAmount == null || _overOutstanding
                ? null
                : _record,
          ),
        ] else ...[
          InlineAlert(
            tone: InlineAlertTone.warning,
            message: '${_pendingAmount?.format() ?? 'The payment'} has been '
                'recorded but is NOT counted yet. The invoice still shows '
                '${invoice.outstanding.format()} outstanding until this is '
                'approved.',
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
          Text(
            'Rejecting is only possible now, before approval. Afterwards a '
            'payment cannot be changed or reversed.',
            style:
                AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
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
          message: 'Payments cannot be recorded while offline. Nothing is '
              'stored on this device — if the connection fails, the payment '
              'has not been taken and must be entered again.',
        ),
      ],
    );
  }
}
