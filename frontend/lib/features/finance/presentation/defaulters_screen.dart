import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../../core/widgets/status_pill.dart';
import '../../setup/domain/setup_models.dart';
import '../../setup/presentation/academic_years_screen.dart' show setupListHeight;
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
    setState(() => _state =
        ScreenState<List<DefaulterRow>>.loading(previous: _state.data));
    try {
      final rows = await widget.repository.loadDefaulters(classId: _classId);
      if (!mounted) return;
      setState(() => _state = ScreenState<List<DefaulterRow>>.data(
            sortDefaulters(rows, _today),
          ));
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<List<DefaulterRow>>.failed(
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
            data: (context, rows) => ListView(
              children: [
                for (final row in rows)
                  _DefaulterRowTile(
                    row: row,
                    today: _today,
                    onTap: () async {
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
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DefaulterRowTile extends StatelessWidget {
  const _DefaulterRowTile({
    required this.row,
    required this.today,
    required this.onTap,
  });

  final DefaulterRow row;
  final DateTime today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final late = row.daysOverdue(today);

    return Semantics(
      button: true,
      label: '${row.studentName}, ${row.outstanding.format()} outstanding',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(
          child: Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.space3),
            padding: const EdgeInsets.all(AppSpacing.space5),
            constraints:
                const BoxConstraints(minHeight: AppSizing.listRowMinHeight),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border:
                  Border.all(color: t.border, width: AppSizing.borderThin),
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
                      // The outstanding amount leads, because it is what the
                      // list is ordered by and what the decision turns on.
                      row.outstanding.format(),
                      style: AppTypography.personName
                          .copyWith(color: t.textPrimary),
                    ),
                    Text(
                      row.studentName,
                      style: AppTypography.personName
                          .copyWith(color: t.textPrimary),
                    ),
                    StatusPill(status: row.status.pill, size: StatusPillSize.sm),
                  ],
                ),
                const SizedBox(height: AppSpacing.space2),
                Text(
                  late > 0
                      ? '${row.admissionNumber} · ${row.period} · '
                          '$late days past due'
                      : '${row.admissionNumber} · ${row.period} · '
                          'due ${row.dueDate}',
                  style: AppTypography.bodyAdminMeta.copyWith(
                    color: late > 0 ? t.warningTextOnBg : t.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
