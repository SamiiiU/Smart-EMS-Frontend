import 'package:flutter/material.dart';

import '../../../core/widgets/adaptive_data_view.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../../core/widgets/status_pill.dart';
import '../../setup/domain/setup_models.dart';
import '../../setup/presentation/academic_years_screen.dart'
    show setupListHeight;
import '../../setup/presentation/sections_screen.dart' show PickerChip;
import '../../setup/presentation/setup_scaffold.dart';
import '../data/finance_repository.dart';
import '../domain/finance_models.dart';
import '../../../core/widgets/app_button.dart';
import 'invoice_detail_screen.dart';

/// Screen 4: the invoice list.
///
/// Only the three filters this backend honours are offered — class, status
/// and period, each confirmed with a bogus-value control. There is no
/// section filter: `?sectionId=` is accepted and IGNORED, so a section chip
/// would silently show the whole class (D-19).
class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({
    required this.repository,
    required this.classes,
    super.key,
  });

  final FinanceRepository repository;
  final List<SchoolClass> classes;

  @override
  State<InvoicesScreen> createState() => InvoicesScreenState();
}

class InvoicesScreenState extends State<InvoicesScreen> {
  ScreenState<List<Invoice>> _state =
      const ScreenState<List<Invoice>>.loading();

  String? _classId;
  String? _status;
  String _period = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(
      () => _state = ScreenState<List<Invoice>>.loading(previous: _state.data),
    );
    try {
      final page = await widget.repository.loadInvoices(
        classId: _classId,
        status: _status,
        period: _period.trim().isEmpty ? null : _period.trim(),
      );
      if (!mounted) return;
      setState(() => _state = ScreenState<List<Invoice>>.data(page.invoices));
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(
        () => _state = ScreenState<List<Invoice>>.failed(
          f,
          cached: _state.data,
          connection: f.unreachable
              ? NetworkStatus.offline
              : NetworkStatus.online,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final today = DateTime.now();

    return SetupScaffold(
      title: 'Invoices',
      children: [
        Text(
          'Class',
          style: AppTypography.fieldLabel.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space2),
        Wrap(
          spacing: AppSpacing.space2,
          runSpacing: AppSpacing.space2,
          children: [
            PickerChip(
              label: 'All',
              selected: _classId == null,
              onTap: () {
                setState(() => _classId = null);
                load();
              },
            ),
            for (final c in widget.classes)
              PickerChip(
                label: c.name,
                selected: _classId == c.id,
                onTap: () {
                  setState(() => _classId = c.id);
                  load();
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.space5),
        Text(
          'Status',
          style: AppTypography.fieldLabel.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space2),
        Wrap(
          spacing: AppSpacing.space2,
          runSpacing: AppSpacing.space2,
          children: [
            PickerChip(
              label: 'All',
              selected: _status == null,
              onTap: () {
                setState(() => _status = null);
                load();
              },
            ),
            for (final s in InvoiceStatus.values)
              PickerChip(
                label: StatusPill.labelFor(s.pill),
                selected: _status == s.name,
                onTap: () {
                  setState(() => _status = s.name);
                  load();
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.space5),
        SetupField(
          label: 'Period (YYYY-MM, optional)',
          value: _period,
          placeholder: 'e.g. 2026-09',
          onChanged: (v) => setState(() => _period = v),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: 'Apply period',
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.sm,
            onPressed: load,
          ),
        ),
        const SizedBox(height: AppSpacing.space4),
        SizedBox(
          height: setupListHeight(context),
          child: ScreenStateBuilder<List<Invoice>>(
            state: _state,
            onRetry: load,
            emptyTitle: 'No invoices match',
            emptyMessage:
                'Nothing has been invoiced for this filter yet. '
                'Invoices are created under “Generate invoices”.',
            emptyIcon: Icons.receipt_outlined,
            // M1 adaptive list: a finance table on desktop (money right-aligned),
            // labelled cards on phones; same accessible row name as before.
            data: (context, invoices) => AdaptiveDataView<Invoice>(
              rows: invoices,
              padding: EdgeInsets.zero,
              semanticLabel: (invoice) => invoiceSemanticLabel(invoice),
              onTap: (invoice) async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => InvoiceDetailScreen(
                      repository: widget.repository,
                      invoiceId: invoice.id,
                    ),
                  ),
                );
                await load();
              },
              columns: [
                DataColumnSpec(
                  label: 'Learner',
                  value: (i) => i.studentName,
                  flex: 3,
                ),
                DataColumnSpec(
                  label: 'Period',
                  value: (i) => i.period,
                  flex: 2,
                ),
                DataColumnSpec(
                  label: 'Total',
                  value: (i) => i.totalAmount.format(),
                  flex: 2,
                  numeric: true,
                ),
                DataColumnSpec(
                  label: 'Outstanding',
                  value: (i) => i.outstanding.isZero
                      ? 'Nothing due'
                      : i.outstanding.format(),
                  flex: 2,
                  numeric: true,
                ),
                DataColumnSpec(
                  label: 'Status',
                  value: (i) => StatusPill.labelFor(i.status.pill),
                  flex: 3,
                  // The backend has no overdue STATUS, so lateness is said in
                  // words next to the pill rather than pretended into one.
                  cell: (i) => Wrap(
                    spacing: AppSpacing.space3,
                    runSpacing: AppSpacing.space1,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusPill(
                        status: i.status.pill,
                        size: StatusPillSize.sm,
                      ),
                      if (i.isOverdue(today))
                        Text(
                          '${i.daysOverdue(today)} days late',
                          style: AppTypography.bodyAdminMeta.copyWith(
                            color: context.tokens.warningTextOnBg,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One invoice, as a row.
///
/// The amount shown is the backend's `total_amount` and the outstanding
/// figure is `total_amount - paid_amount` in integer paisa — a subtraction
/// of two server values, not a re-derivation of either.
class InvoiceRow extends StatelessWidget {
  const InvoiceRow({
    required this.invoice,
    required this.today,
    this.onTap,
    super.key,
  });

  final Invoice invoice;
  final DateTime today;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final overdue = invoice.isOverdue(today);

    final row = Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space3),
      padding: const EdgeInsets.all(AppSpacing.space5),
      constraints: const BoxConstraints(minHeight: AppSizing.listRowMinHeight),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border, width: AppSizing.borderThin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap, not Row: a name, a period, an amount and a pill cannot
          // share one line on a 360px phone at a large text scale.
          Wrap(
            spacing: AppSpacing.space4,
            runSpacing: AppSpacing.space2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                invoice.studentName,
                style: AppTypography.personName.copyWith(color: t.textPrimary),
              ),
              Text(
                invoice.period,
                style: AppTypography.bodyAdminMeta.copyWith(
                  color: t.textSecondary,
                ),
              ),
              StatusPill(status: invoice.status.pill, size: StatusPillSize.sm),
            ],
          ),
          const SizedBox(height: AppSpacing.space2),
          Wrap(
            spacing: AppSpacing.space4,
            runSpacing: AppSpacing.space2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                invoice.totalAmount.format(),
                style: AppTypography.personName.copyWith(color: t.textPrimary),
              ),
              if (!invoice.outstanding.isZero)
                Text(
                  '${invoice.outstanding.format()} outstanding',
                  style: AppTypography.bodyAdminMeta.copyWith(
                    color: t.textSecondary,
                  ),
                ),
              // The backend has no overdue STATUS, so this is said in words
              // next to the pill rather than pretended into one.
              if (overdue)
                Text(
                  'Due ${invoice.dueDate} · '
                  '${invoice.daysOverdue(today)} days late',
                  style: AppTypography.bodyAdminMeta.copyWith(
                    color: t.warningTextOnBg,
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: invoiceSemanticLabel(invoice),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(child: row),
      ),
    );
  }
}

/// One spoken summary per invoice, shared by [InvoiceRow] and the adaptive list.
String invoiceSemanticLabel(Invoice invoice) =>
    '${invoice.studentName}, ${invoice.period}, ${invoice.totalAmount.format()}, '
    '${StatusPill.labelFor(invoice.status.pill)}';
