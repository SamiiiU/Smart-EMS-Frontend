import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../../core/widgets/status_pill.dart';
import '../../setup/presentation/setup_scaffold.dart';
import '../data/finance_repository.dart';
import '../domain/finance_models.dart';
import 'record_payment_screen.dart';

/// One invoice: its lines, its totals, and the way to pay it.
///
/// 🔴 **It cannot show a payment history.** There is no
/// `/api/fee/invoices/{id}/payments`, and an approved payment cannot even be
/// read by its own id — it 404s once approved. All that exists is the
/// invoice's running `paid_amount`. The screen says that plainly rather than
/// leaving an accountant to assume the list is empty because nobody has
/// paid.
///
/// Every figure here is the server's. Nothing is added up locally; the one
/// arithmetic is `total - paid`, exact in integer paisa.
class InvoiceDetailScreen extends StatefulWidget {
  const InvoiceDetailScreen({
    required this.repository,
    required this.invoiceId,
    super.key,
  });

  final FinanceRepository repository;
  final String invoiceId;

  @override
  State<InvoiceDetailScreen> createState() => InvoiceDetailScreenState();
}

class InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  ScreenState<Invoice> _state = const ScreenState<Invoice>.loading();

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(
        () => _state = ScreenState<Invoice>.loading(previous: _state.data));
    try {
      final invoice = await widget.repository.loadInvoice(widget.invoiceId);
      if (!mounted) return;
      setState(() => _state = ScreenState<Invoice>.data(invoice,
          // One record, never a collection (D-39).
          isEmpty: false));
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<Invoice>.failed(
            f,
            cached: _state.data,
            connection:
                f.unreachable ? NetworkStatus.offline : NetworkStatus.online,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SetupScaffold(
      title: 'Invoice',
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height,
          child: ScreenStateBuilder<Invoice>(
            state: _state,
            onRetry: load,
            emptyTitle: 'Invoice unavailable',
            emptyMessage: 'This invoice could not be loaded.',
            data: _body,
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, Invoice invoice) {
    final t = context.tokens;
    final today = DateTime.now();
    final overdue = invoice.isOverdue(today);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Wrap(
          spacing: AppSpacing.space4,
          runSpacing: AppSpacing.space2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              invoice.studentName,
              style: AppTypography.sectionHeading.copyWith(
                color: t.textPrimary,
              ),
            ),
            StatusPill(status: invoice.status.pill),
          ],
        ),
        const SizedBox(height: AppSpacing.space2),
        Text(
          'Period ${invoice.period} · due ${invoice.dueDate}',
          style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
        ),
        if (overdue) ...[
          const SizedBox(height: AppSpacing.space4),
          InlineAlert(
            tone: InlineAlertTone.warning,
            message: '${invoice.daysOverdue(today)} days past the due date.',
          ),
        ],
        const SizedBox(height: AppSpacing.space6),

        Container(
          padding: const EdgeInsets.all(AppSpacing.space5),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: t.border, width: AppSizing.borderThin),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final line in invoice.lines)
                _AmountRow(label: line.description, amount: line.total.format()),
              if (invoice.hasLines && invoice.lines.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.space3,
                  ),
                  child: Divider(color: t.border, height: AppSizing.borderThin),
                ),
              _AmountRow(
                label: 'Total',
                amount: invoice.totalAmount.format(),
                strong: true,
              ),
              _AmountRow(
                label: 'Paid',
                amount: invoice.paidAmount.format(),
              ),
              _AmountRow(
                label: 'Outstanding',
                amount: invoice.outstanding.format(),
                strong: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space5),

        // The honest gap, stated where it matters.
        const InlineAlert(
          tone: InlineAlertTone.info,
          message: 'Only the total paid is available — this system has no '
              'way to list the individual payments that made it up.',
        ),
        const SizedBox(height: AppSpacing.space6),

        if (invoice.outstanding.isPositive)
          AppButton(
            label: 'Record a payment',
            fullWidth: true,
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RecordPaymentScreen(
                    repository: widget.repository,
                    invoice: invoice,
                  ),
                ),
              );
              await load();
            },
          )
        else
          const InlineAlert(
            tone: InlineAlertTone.success,
            message: 'This invoice is settled in full.',
          ),
      ],
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.amount,
    this.strong = false,
  });

  final String label;
  final String amount;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final style = strong
        ? AppTypography.personName.copyWith(color: t.textPrimary)
        : AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: AppSpacing.space4),
          Text(
            amount,
            // Every style in this scale is already tabular, so a column of
            // amounts aligns digit for digit without a special style.
            style: AppTypography.personName.copyWith(
              color: strong ? t.textPrimary : t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
