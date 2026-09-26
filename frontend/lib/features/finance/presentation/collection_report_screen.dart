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

/// Screen 8: the collection report — invoiced against collected, by class.
///
/// Two things this screen refuses to do, both for the same reason:
///
///  - **No period filter.** The endpoint accepts `period` and
///    `academicYearId` and IGNORES both — `period=1999-01` returned figures
///    identical to the unfiltered call. A filter that changes nothing is
///    worse than none, so the scope is stated in words instead.
///  - **No monthly chart.** The data has no monthly dimension at all. A
///    trend line drawn over it would be invented.
///
/// Every figure is the server's own. Nothing here is summed locally — not
/// even the class rows into the totals, which the endpoint already provides.
class CollectionReportScreen extends StatefulWidget {
  const CollectionReportScreen({required this.repository, super.key});

  final FinanceRepository repository;

  @override
  State<CollectionReportScreen> createState() => CollectionReportScreenState();
}

class CollectionReportScreenState extends State<CollectionReportScreen> {
  ScreenState<CollectionReport> _state =
      const ScreenState<CollectionReport>.loading();

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() =>
        _state = ScreenState<CollectionReport>.loading(previous: _state.data));
    try {
      final report = await widget.repository.loadCollectionReport();
      if (!mounted) return;
      setState(() => _state = ScreenState<CollectionReport>.data(
            report,
            // D-39: a report is one record. Emptiness is about whether any
            // class has been invoiced, which is the class list below.
            isEmpty: report.byClass.isEmpty,
          ));
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<CollectionReport>.failed(
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
      title: 'Collection report',
      note: const InlineAlert(
        tone: InlineAlertTone.info,
        message: 'Everything invoiced and collected so far, across the whole '
            'school. This report cannot be narrowed to a month or a year.',
      ),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height,
          child: ScreenStateBuilder<CollectionReport>(
            state: _state,
            onRetry: load,
            emptyTitle: 'Nothing invoiced yet',
            emptyMessage: 'Once invoices exist, what each class has been '
                'charged and has paid appears here.',
            emptyIcon: Icons.insights_outlined,
            data: _body,
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, CollectionReport report) {
    final t = context.tokens;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.space6),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: t.border, width: AppSizing.borderThin),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                report.totalCollected.format(),
                style: AppTypography.parentStatusHero
                    .copyWith(color: t.textPrimary),
              ),
              Text(
                'collected of ${report.totalInvoiced.format()} invoiced',
                style: AppTypography.bodyAdminMeta
                    .copyWith(color: t.textSecondary),
              ),
              const SizedBox(height: AppSpacing.space4),
              Text(
                '${report.outstanding.format()} outstanding',
                style:
                    AppTypography.personName.copyWith(color: t.warningTextOnBg),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space6),
        Text(
          'By class',
          style: AppTypography.sectionHeading.copyWith(color: t.textPrimary),
        ),
        const SizedBox(height: AppSpacing.space4),
        for (final row in report.byClass)
          Container(
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
                Text(
                  row.className,
                  style:
                      AppTypography.personName.copyWith(color: t.textPrimary),
                ),
                const SizedBox(height: AppSpacing.space2),
                Wrap(
                  spacing: AppSpacing.space5,
                  runSpacing: AppSpacing.space2,
                  children: [
                    _Figure(label: 'Invoiced', value: row.invoiced.format()),
                    _Figure(label: 'Collected', value: row.collected.format()),
                    _Figure(
                      label: 'Outstanding',
                      value: row.outstanding.format(),
                      warn: row.outstanding.isPositive,
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.warn = false});

  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.overline.copyWith(color: t.textSecondary),
        ),
        Text(
          value,
          style: AppTypography.personName.copyWith(
            color: warn ? t.warningTextOnBg : t.textPrimary,
          ),
        ),
      ],
    );
  }
}
