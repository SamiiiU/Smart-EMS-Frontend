import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../setup/presentation/academic_years_screen.dart' show setupListHeight;
import '../../setup/presentation/setup_scaffold.dart';
import '../data/finance_repository.dart';
import '../domain/finance_models.dart';
import 'receipt_screen.dart';

/// The approval queue — the other half of screen 5.
///
/// Recording and approving are two different acts on this backend, and they
/// are often two different people: a clerk at the counter, an accountant
/// checking the day's takings. This is where the second one works.
///
/// Every row states that the money is not counted yet. Approval is
/// irreversible and says so before it happens; rejection is possible only
/// here, before approval.
class PendingPaymentsScreen extends StatefulWidget {
  const PendingPaymentsScreen({required this.repository, super.key});

  final FinanceRepository repository;

  @override
  State<PendingPaymentsScreen> createState() => PendingPaymentsScreenState();
}

class PendingPaymentsScreenState extends State<PendingPaymentsScreen> {
  ScreenState<List<PendingPayment>> _state =
      const ScreenState<List<PendingPayment>>.loading();

  String? _busyId;
  String? _error;

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Approve this payment?'),
        content: Text(
          '${payment.amount.format()} from ${payment.studentName} will be '
          'counted against the invoice and a receipt will be issued.\n\n'
          'This cannot be undone. There is no way to reverse an approved '
          'payment on this system.',
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
      _busyId = payment.id;
      _error = null;
    });
    final outcome = await widget.repository.approvePayment(payment.id);
    if (!mounted) return;
    setState(() {
      _busyId = null;
      _error = outcome.error;
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
    setState(() {
      _busyId = payment.id;
      _error = null;
    });
    final error = await widget.repository.rejectPayment(payment.id);
    if (!mounted) return;
    setState(() {
      _busyId = null;
      _error = error;
    });
    await load();
  }

  @override
  Widget build(BuildContext context) {
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
        SizedBox(
          height: setupListHeight(context),
          child: ScreenStateBuilder<List<PendingPayment>>(
            state: _state,
            onRetry: load,
            emptyTitle: 'Nothing awaiting approval',
            emptyMessage: 'Payments appear here as soon as they are recorded '
                'at the counter.',
            emptyIcon: Icons.payments_outlined,
            data: (context, payments) => ListView(
              children: [
                for (final payment in payments)
                  _PendingRow(
                    payment: payment,
                    busy: _busyId == payment.id,
                    onApprove: () => _approve(payment),
                    onReject: () => _reject(payment),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({
    required this.payment,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final PendingPayment payment;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space3),
      padding: const EdgeInsets.all(AppSpacing.space5),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border, width: AppSizing.borderThin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.space4,
            runSpacing: AppSpacing.space2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                payment.amount.format(),
                style: AppTypography.personName.copyWith(color: t.textPrimary),
              ),
              Text(
                payment.studentName,
                style: AppTypography.bodyAdminMeta
                    .copyWith(color: t.textSecondary),
              ),
              Text(
                payment.source,
                style: AppTypography.bodyAdminMeta
                    .copyWith(color: t.textSecondary),
              ),
              if (payment.reference != null && payment.reference!.isNotEmpty)
                Text(
                  'Ref ${payment.reference}',
                  style: AppTypography.bodyAdminMeta
                      .copyWith(color: t.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.space4),
          // Wrap rather than Row so two buttons and a long name reflow on a
          // 360px phone instead of overflowing.
          Wrap(
            spacing: AppSpacing.space3,
            runSpacing: AppSpacing.space3,
            children: [
              AppButton(
                label: busy ? 'Working…' : 'Approve',
                onPressed: busy ? null : onApprove,
              ),
              AppButton(
                label: 'Reject',
                variant: AppButtonVariant.secondary,
                onPressed: busy ? null : onReject,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
