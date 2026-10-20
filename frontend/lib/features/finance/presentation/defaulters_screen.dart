import 'package:flutter/material.dart';

import '../../../core/widgets/adaptive_data_view.dart';
import '../../../core/widgets/business_date.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
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
import 'invoice_detail_screen.dart';

/// Screen 7: defaulters — a WORKLIST, not a report.
///
/// D-15's principle applied to money: ordered by what needs action, which
/// here is largest outstanding first, longest overdue breaking the tie. An
/// accountant opens this to decide who to phone before lunch, and
/// alphabetical order would bury a PKR 80,000 debt under three PKR 200
/// ones. The ordering rule itself lives on `sortDefaulters`.
///
/// Unlike the collection report, this endpoint really does honour its
/// filters — both were controlled with a bogus value.
class DefaultersScreen extends StatefulWidget {
  const DefaultersScreen({
    required this.repository,
    required this.classes,
    super.key,
  });

  final FinanceRepository repository;
  final List<SchoolClass> classes;

  @override
  State<DefaultersScreen> createState() => DefaultersScreenState();
}

class DefaultersScreenState extends State<DefaultersScreen> {
  ScreenState<List<DefaulterRow>> _state =
      const ScreenState<List<DefaulterRow>>.loading();

  String? _classId;
  final DateTime _today = DateTime.now();

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(
      () => _state = ScreenState<List<DefaulterRow>>.loading(
        previous: _state.data,
      ),
    );
    try {
      final rows = await widget.repository.loadDefaulters(classId: _classId);
      if (!mounted) return;
      setState(
        () => _state = ScreenState<List<DefaulterRow>>.data(
          sortDefaulters(rows, _today),
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(
        () => _state = ScreenState<List<DefaulterRow>>.failed(
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

    return SetupScaffold(
      title: 'Defaulters',
      children: [
        Text(
          'Largest outstanding first.',
          style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space5),
        Wrap(
          spacing: AppSpacing.space2,
          runSpacing: AppSpacing.space2,
          children: [
            PickerChip(
              label: 'All classes',
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
        SizedBox(
          height: setupListHeight(context),
          child: ScreenStateBuilder<List<DefaulterRow>>(
            state: _state,
            onRetry: load,
            emptyTitle: 'Nobody is behind',
            emptyMessage: 'Every invoice in this filter is settled.',
            emptyIcon: Icons.check_circle_outline,
            // M1 adaptive list. The outstanding amount leads (the list is
            // ordered by it and the decision turns on it): the first table
            // column, and the card title on phones.
            data: (context, rows) => AdaptiveDataView<DefaulterRow>(
              rows: rows,
              padding: EdgeInsets.zero,
              semanticLabel: (row) =>
                  '${row.studentName}, ${row.outstanding.format()} outstanding',
              onTap: (row) async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => InvoiceDetailScreen(
                      repository: widget.repository,
                      invoiceId: row.invoiceId,
                    ),
                  ),
                );
                await load();
              },
              columns: [
                DataColumnSpec(
                  label: 'Outstanding',
                  value: (r) => r.outstanding.format(),
                  flex: 2,
                ),
                DataColumnSpec(
                  label: 'Learner',
                  value: (r) => r.studentName,
                  flex: 3,
                ),
                DataColumnSpec(
                  label: 'Admission no.',
                  value: (r) => r.admissionNumber,
                  flex: 2,
                ),
                DataColumnSpec(
                  label: 'Period',
                  value: (r) => r.period,
                  flex: 2,
                ),
                DataColumnSpec(
                  label: 'Due',
                  value: (r) => r.daysOverdue(_today) > 0
                      ? '${r.daysOverdue(_today)} days past due'
                      : formatBusinessDate(context, r.dueDate),
                  flex: 2,
                  cell: (r) {
                    final late = r.daysOverdue(_today);
                    final t = context.tokens;
                    return Text(
                      late > 0
                          ? '$late days past due'
                          : formatBusinessDate(context, r.dueDate),
                      style: AppTypography.bodyAdminMeta.copyWith(
                        color: late > 0 ? t.warningTextOnBg : t.textSecondary,
                      ),
                    );
                  },
                ),
                DataColumnSpec(
                  label: 'Status',
                  value: (r) => StatusPill.labelFor(r.status.pill),
                  flex: 2,
                  cell: (r) => StatusPill(
                    status: r.status.pill,
                    size: StatusPillSize.sm,
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
