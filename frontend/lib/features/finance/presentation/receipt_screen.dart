import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../setup/presentation/setup_scaffold.dart';
import '../data/finance_repository.dart';
import '../domain/finance_models.dart';

/// Screen 6: the receipt for an approved payment.
///
/// Keyed by the `receiptId` that APPROVAL returns, not by the payment id —
/// a payment stops resolving by its own id the moment it is approved
/// (verified: 404). This is the only route to a receipt: there is no
/// receipts list endpoint, so a receipt can be reached when it is issued
/// and not looked up again later. That is a real gap and it is written down
/// rather than papered over.
///
/// **There is no PDF.** Every plausible path 404s. So no download button is
/// offered, and the screen says why instead of leaving a parent waiting for
/// a printable copy.
class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({
    required this.repository,
    required this.receiptId,
    required this.receiptNumber,
    super.key,
  });

  final FinanceRepository repository;
  final String receiptId;

  /// Known from the approval response, so the number can be shown even if
  /// the fetch below fails.
  final String receiptNumber;

  @override
  State<ReceiptScreen> createState() => ReceiptScreenState();
}

class ReceiptScreenState extends State<ReceiptScreen> {
  ScreenState<Receipt> _state = const ScreenState<Receipt>.loading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(
        () => _state = ScreenState<Receipt>.loading(previous: _state.data));
    try {
      final receipt = await widget.repository.loadReceipt(widget.receiptId);
      if (!mounted) return;
      setState(() => _state = ScreenState<Receipt>.data(receipt, isEmpty: false));
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<Receipt>.failed(
            f,
            cached: _state.data,
            connection:
                f.unreachable ? NetworkStatus.offline : NetworkStatus.online,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return SetupScaffold(
      title: 'Receipt ${widget.receiptNumber}',
      note: const InlineAlert(
        tone: InlineAlertTone.success,
        message: 'The payment has been approved and counted against the '
            'invoice.',
      ),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height / 2,
          child: ScreenStateBuilder<Receipt>(
            state: _state,
            onRetry: _load,
            emptyTitle: 'Receipt unavailable',
            emptyMessage: 'The receipt could not be loaded. The payment was '
                'still approved — its number is ${widget.receiptNumber}.',
            data: (context, receipt) => ListView(
              padding: EdgeInsets.zero,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.space6),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border:
                        Border.all(color: t.border, width: AppSizing.borderThin),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        receipt.amount.format(),
                        style: AppTypography.parentStatusHero
                            .copyWith(color: t.textPrimary),
                      ),
                      const SizedBox(height: AppSpacing.space4),
                      _Line(label: 'Receipt', value: receipt.receiptNumber),
                      _Line(label: 'Student', value: receipt.studentName),
                      _Line(label: 'Paid by', value: receipt.source),
                      _Line(label: 'Issued', value: receipt.generatedAt),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.space5),
                const InlineAlert(
                  tone: InlineAlertTone.info,
                  message: 'This receipt cannot be downloaded or printed yet '
                      '— this system does not produce a PDF. Note the receipt '
                      'number for the payer.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space2),
      child: Wrap(
        spacing: AppSpacing.space4,
        runSpacing: AppSpacing.space1,
        children: [
          Text(
            label,
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          ),
          Text(
            value,
            style: AppTypography.personName.copyWith(color: t.textPrimary),
          ),
        ],
      ),
    );
  }
}
