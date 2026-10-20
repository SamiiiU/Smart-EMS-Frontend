import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/adaptive_data_view.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/section_card.dart';
import '../../finance/domain/money.dart';
import '../data/academy_repository.dart';
import '../domain/academy_models.dart';
import 'academy_common.dart';

/// Batch fee terms and on-demand invoice generation (fee.manage on the
/// batch's campus). Setting a fee needs a fresh MFA step-up — the app's
/// step-up interceptor prompts for it when the server asks.
///
/// Fees are immutable once set (no silent overwrite; future-dated price
/// changes need backend support that does not exist yet). Generation is
/// idempotent server-side: each membership is billed at most once per
/// month (monthly) or once ever (one-time course fee). A learner in Maths
/// and Physics owes both batches separately.
///
/// Invoices, payments, receipts and balances are the existing Fees screens:
/// there is no batch-scoped invoice list API yet, so none is shown here.
class BatchFeePanel extends StatefulWidget {
  const BatchFeePanel({
    required this.repository,
    required this.batch,
    super.key,
  });
  final AcademyRepository repository;
  final Batch batch;

  @override
  State<BatchFeePanel> createState() => _BatchFeePanelState();
}

class _BatchFeePanelState extends State<BatchFeePanel> {
  final _loader = GlobalKey<AcademyLoaderState<({BatchFee? fee})>>();
  late String _period = isoDate(DateTime.now()).substring(0, 7);
  bool _generating = false;
  String? _result;
  bool _resultError = false;

  static final _month = RegExp(r'^\d{4}-(0[1-9]|1[0-2])$');

  String _nextMonth(String month) {
    final p = DateTime.tryParse('$month-01') ?? DateTime.now();
    final n = DateTime(p.year, p.month + 1);
    return '${n.year}-${n.month.toString().padLeft(2, '0')}';
  }

  /// A new price from a FUTURE billing month. Existing invoices never change.
  Future<void> _schedule(BatchFee fee) async {
    var amount = '', month = _nextMonth(fee.currentMonth), reason = '';
    final ok = await showFormDialog(
      context,
      title: 'Schedule a price change',
      submitLabel: 'Schedule',
      canSubmit: () =>
          Money.tryParse(amount.trim()) != null &&
          isDecimal2(amount) &&
          _month.hasMatch(month) &&
          reason.trim().length >= 3,
      fields: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InlineAlert(
            tone: InlineAlertTone.info,
            message:
                'The new price applies to learners first billed from the chosen month. Learners already billed keep '
                'their agreed price (${pkr(fee.amount)}) unless you apply an adjustment. Issued invoices never change.',
          ),
          const SizedBox(height: AppSpacing.space5),
          field(
            'New amount (PKR)',
            amount,
            (v) => setState(() => amount = v),
            placeholder: 'e.g. 3500.00',
            required: true,
            error: amount.isEmpty || isDecimal2(amount)
                ? null
                : 'An amount with up to two decimals.',
          ),
          field(
            'Effective billing month (YYYY-MM)',
            month,
            (v) => setState(() => month = v.trim()),
            required: true,
            error: _month.hasMatch(month) ? null : 'Use YYYY-MM.',
          ),
          field(
            'Reason (recorded)',
            reason,
            (v) => setState(() => reason = v),
            required: true,
          ),
        ],
      ),
      submit: () => attempt(
        () => widget.repository.scheduleFeeVersion(
          widget.batch.id,
          amount: amount.trim(),
          effectiveFrom: month,
          reason: reason.trim(),
        ),
      ),
    );
    if (ok) await _loader.currentState?.reload();
  }

  /// Explicit, audited adjustment moving ALL current learners to a scheduled price.
  Future<void> _adjust(BatchFee fee) async {
    var versionId = fee.scheduled.first.id, reason = '';
    String monthOf(String id) =>
        fee.versions.firstWhere((v) => v.id == id).effectiveFrom;
    final ok = await showFormDialog(
      context,
      title: 'Apply a price to existing learners',
      submitLabel: 'Apply adjustment',
      canSubmit: () => reason.trim().length >= 3,
      fields: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const InlineAlert(
            tone: InlineAlertTone.warning,
            message:
                'This changes the agreed price of every current learner from the chosen month onward. '
                'It is recorded with your name and reason. Already-issued invoices are not changed.',
          ),
          const SizedBox(height: AppSpacing.space5),
          dropdown<String>(
            'Scheduled price',
            versionId,
            [
              for (final v in fee.scheduled)
                (v.id, '${pkr(v.amount)} from ${v.effectiveFrom}'),
            ],
            (v) => setState(() => versionId = v ?? versionId),
          ),
          Text('Applies from ${monthOf(versionId)}'),
          const SizedBox(height: AppSpacing.space5),
          field(
            'Reason (recorded)',
            reason,
            (v) => setState(() => reason = v),
            required: true,
          ),
        ],
      ),
      submit: () => attempt(
        () => widget.repository.adjustExistingLearners(
          widget.batch.id,
          versionId: versionId,
          appliesFrom: monthOf(versionId),
          reason: reason.trim(),
        ),
      ),
    );
    if (ok) await _loader.currentState?.reload();
  }

  Future<void> _set() async {
    final heads = await loadForForm(context, widget.repository.feeHeads);
    if (heads == null || !mounted) return;
    if (heads.isEmpty) {
      return showResult(
        context,
        'Create a fee head first (Fees → Fee heads).',
        error: true,
      );
    }
    String? head;
    var amount = '', frequency = 'monthly', due = '10';
    final ok = await showFormDialog(
      context,
      title: 'Set the batch fee',
      submitLabel: 'Set fee',
      canSubmit: () =>
          head != null &&
          Money.tryParse(amount.trim()) != null &&
          (int.tryParse(due) ?? 0) >= 1 &&
          (int.tryParse(due) ?? 0) <= 28,
      fields: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const InlineAlert(
            tone: InlineAlertTone.warning,
            message: 'A batch fee cannot be changed after it is set.',
          ),
          const SizedBox(height: AppSpacing.space5),
          dropdown<String>('Fee head', head, [
            for (final h in heads) (h.id, h.label),
          ], (v) => setState(() => head = v)),
          field(
            'Amount (PKR)',
            amount,
            (v) => setState(() => amount = v),
            placeholder: 'e.g. 4500.00',
            required: true,
            error:
                amount.isEmpty ||
                    (Money.tryParse(amount.trim()) != null &&
                        isDecimal2(amount))
                ? null
                : 'An amount with up to two decimals.',
          ),
          dropdown<String>('Billing', frequency, const [
            ('monthly', 'Monthly'),
            ('one_time', 'One-time course fee'),
          ], (v) => setState(() => frequency = v ?? 'monthly')),
          field(
            'Due day of month (1–28)',
            due,
            (v) => setState(() => due = v),
            required: true,
          ),
        ],
      ),
      submit: () => attempt(
        () => widget.repository.setBatchFee(
          widget.batch.id,
          feeHeadId: head!,
          amount: amount.trim(),
          frequency: frequency,
          dueDay: int.parse(due),
        ),
      ),
    );
    if (ok) await _loader.currentState?.reload();
  }

  Future<void> _generate() async {
    if (_generating) return;
    setState(() {
      _generating = true;
      _result = null;
    });
    try {
      final r = await widget.repository.generateInvoices(
        widget.batch.id,
        _period,
      );
      if (!mounted) return;
      setState(() {
        _result = r.generated == 0
            ? 'No new invoices: every active learner is already billed for ${r.billingKey == 'COURSE' ? 'this course' : r.billingKey}.'
            : 'Created ${r.generated} ${r.generated == 1 ? 'invoice' : 'invoices'}'
                  '${r.alreadyBilled > 0 ? '; ${r.alreadyBilled} already billed were skipped' : ''}. Collect payments in Fees.';
        _resultError = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _result =
            '${AcademyRepository.explain(e, 'Invoices were not generated.')} Running it again is safe — nobody is billed twice.';
        _resultError = true;
      });
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Wrapped in a record: a bare null would read as "still loading" (D-39).
    return AcademyLoader<({BatchFee? fee})>(
      key: _loader,
      load: () async =>
          (fee: await widget.repository.batchFee(widget.batch.id)),
      emptyTitle: '',
      emptyMessage: '',
      builder: (context, loaded, _) {
        final fee = loaded.fee;
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.space6),
          children: [
            SectionCard(
              title: 'Fee terms',
              child: fee == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('No fee is set for this batch.'),
                        const SizedBox(height: AppSpacing.space5),
                        AppButton(
                          label: 'Set fee',
                          onPressed: widget.batch.status == 'cancelled'
                              ? null
                              : _set,
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${fee.feeHeadName}: ${pkr(fee.amount)}',
                          style: AppTypography.cardHeading.copyWith(
                            color: t.textPrimary,
                          ),
                        ),
                        Text(
                          fee.monthly
                              ? 'Billed monthly, due on day ${fee.dueDay}'
                              : 'One-time course fee, due on day ${fee.dueDay}',
                          style: AppTypography.bodyAdminMeta.copyWith(
                            color: t.textSecondary,
                          ),
                        ),
                        Text(
                          'Current price for ${fee.currentMonth.isEmpty ? 'this month' : fee.currentMonth}.',
                          style: AppTypography.caption.copyWith(
                            color: t.textMuted,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.space5),
                        Wrap(
                          spacing: AppSpacing.space4,
                          runSpacing: AppSpacing.space4,
                          children: [
                            AppButton(
                              label: 'Schedule price change',
                              variant: AppButtonVariant.secondary,
                              onPressed: widget.batch.status == 'cancelled'
                                  ? null
                                  : () => _schedule(fee),
                            ),
                            if (fee.scheduled.isNotEmpty)
                              AppButton(
                                label: 'Apply to existing learners',
                                variant: AppButtonVariant.ghost,
                                onPressed: () => _adjust(fee),
                              ),
                          ],
                        ),
                      ],
                    ),
            ),
            if (fee != null && fee.versions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.space6),
              SectionCard(
                title: 'Price history',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final v in fee.versions.reversed)
                      ListTile(
                        key: ValueKey('fee-version-${v.effectiveFrom}'),
                        contentPadding: EdgeInsets.zero,
                        title: Text('${pkr(v.amount)} from ${v.effectiveFrom}'),
                        subtitle: Text(v.reason),
                        trailing: StatusChip(
                          v.id == fee.currentVersionId
                              ? 'current'
                              : fee.scheduled.any((s) => s.id == v.id)
                              ? 'scheduled'
                              : 'past',
                        ),
                      ),
                    Text(
                      'Issued invoices never change. A scheduled price applies to learners first billed from its month; '
                      'learners already billed keep their agreed price unless an adjustment is recorded'
                      '${fee.adjustments > 0 ? ' (${fee.adjustments} recorded)' : ''}.',
                      style: AppTypography.caption.copyWith(color: t.textMuted),
                    ),
                  ],
                ),
              ),
            ],
            if (fee != null) ...[
              const SizedBox(height: AppSpacing.space6),
              SectionCard(
                title: 'Billing',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      fee.monthly
                          ? 'Bills every active learner who joined by the end of the chosen month, once per month.'
                          : 'Bills every active learner once for this course. The month sets the due date.',
                    ),
                    const SizedBox(height: AppSpacing.space5),
                    field(
                      'Billing month (YYYY-MM)',
                      _period,
                      (v) => setState(() => _period = v.trim()),
                      error:
                          RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(_period)
                          ? null
                          : 'Use YYYY-MM.',
                    ),
                    AppButton(
                      label: _generating ? 'Generating…' : 'Generate invoices',
                      onPressed:
                          _generating ||
                              !RegExp(
                                r'^\d{4}-(0[1-9]|1[0-2])$',
                              ).hasMatch(_period)
                          ? null
                          : _generate,
                    ),
                    if (_result != null) ...[
                      const SizedBox(height: AppSpacing.space5),
                      InlineAlert(
                        tone: _resultError
                            ? InlineAlertTone.danger
                            : InlineAlertTone.success,
                        message: _result!,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.space6),
              SectionCard(
                title: 'Invoices for $_period',
                child: SizedBox(
                  height: 360,
                  child:
                      AcademyLoader<
                        ({List<BatchInvoice> invoices, MoneyTotals totals})
                      >(
                        key: ValueKey('invoices-$_period-$_result'),
                        load: () => widget.repository.batchInvoices(
                          widget.batch.id,
                          period:
                              RegExp(
                                r'^\d{4}-(0[1-9]|1[0-2])$',
                              ).hasMatch(_period)
                              ? _period
                              : null,
                        ),
                        isEmpty: (v) => v.invoices.isEmpty,
                        emptyTitle: 'No invoices for this month',
                        emptyMessage:
                            'Generate invoices above; each learner is billed once.',
                        builder: (context, data, _) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Billed ${pkr(data.totals.invoiced)} · '
                              'Collected ${pkr(data.totals.collected)} · '
                              'Outstanding ${pkr(data.totals.outstanding)}',
                              style: AppTypography.bodyAdminMeta.copyWith(
                                color: t.textPrimary,
                              ),
                            ),
                            Expanded(
                              child: AdaptiveDataView<BatchInvoice>(
                                rows: data.invoices,
                                semanticLabel: (i) =>
                                    '${i.studentName}, ${i.status}, outstanding ${i.outstanding}',
                                columns: [
                                  DataColumnSpec(
                                    label: 'Learner',
                                    value: (i) => i.studentName,
                                    flex: 2,
                                  ),
                                  DataColumnSpec(
                                    label: 'Due',
                                    value: (i) => i.dueDate,
                                  ),
                                  DataColumnSpec(
                                    label: 'Total',
                                    numeric: true,
                                    value: (i) =>
                                        Money.tryParse(i.total)?.format() ??
                                        i.total,
                                  ),
                                  DataColumnSpec(
                                    label: 'Outstanding',
                                    numeric: true,
                                    value: (i) =>
                                        Money.tryParse(
                                          i.outstanding,
                                        )?.format() ??
                                        i.outstanding,
                                  ),
                                  DataColumnSpec(
                                    label: 'Status',
                                    value: (i) => i.status,
                                    cell: (i) => StatusChip(i.status),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                ),
              ),
              const SizedBox(height: AppSpacing.space6),
              const InlineAlert(
                tone: InlineAlertTone.info,
                message:
                    'Record payments, approvals and receipts in Fees — the same flow as school invoices.',
              ),
            ],
          ],
        );
      },
    );
  }
}
