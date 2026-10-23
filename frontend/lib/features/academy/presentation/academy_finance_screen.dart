import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/adaptive_data_view.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/section_card.dart';
import '../data/academy_repository.dart';
import '../domain/academy_models.dart';
import 'academy_common.dart';
import 'batch_fee_panel.dart';

/// Academy finance workspace for staff holding fee.manage: read-only batch
/// discovery (no academic rights), each batch's fee and invoices, and the
/// Academy collection report. All totals are computed by the server.
class AcademyFinanceScreen extends StatelessWidget {
  const AcademyFinanceScreen({required this.repository, super.key});
  final AcademyRepository repository;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHeader(
            title: 'Academy fees',
            subtitle: 'Batch billing and collection',
          ),
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Batches'),
              Tab(text: 'Collection'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _FinanceBatches(repository: repository),
                AcademyCollectionReport(repository: repository),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FinanceBatches extends StatefulWidget {
  const _FinanceBatches({required this.repository});
  final AcademyRepository repository;

  @override
  State<_FinanceBatches> createState() => _FinanceBatchesState();
}

class _FinanceBatchesState extends State<_FinanceBatches> {
  final _loader = GlobalKey<AcademyLoaderState<List<FinanceBatch>>>();
  final _reload = CampusReload();

  void _open(FinanceBatch f) => Navigator.of(context)
      .push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            backgroundColor: context.tokens.page,
            body: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const BackButton(),
                      Expanded(
                        child: PageHeader(
                          title: '${f.batch.courseName} · ${f.batch.name}',
                          subtitle: campusName(context, f.batch.campusId),
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: BatchFeePanel(
                      repository: widget.repository,
                      batch: f.batch,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      )
      .then((_) => _loader.currentState?.reload());

  @override
  Widget build(BuildContext context) {
    final filter = listCampus(context, 'fee.manage');
    _reload.track(filter, _loader);
    return AcademyLoader<List<FinanceBatch>>(
      key: _loader,
      load: () => widget.repository.financeBatches(campusId: filter),
      isEmpty: (v) => v.isEmpty,
      emptyTitle: 'No batches',
      emptyMessage: 'Batches on campuses where you manage fees appear here.',
      emptyIcon: Icons.payments_outlined,
      builder: (context, rows, _) => AdaptiveDataView<FinanceBatch>(
        rows: rows,
        onTap: _open,
        rowKey: (f) => ValueKey('finance-batch-${f.batch.id}'),
        semanticLabel: (f) =>
            '${f.batch.courseName} ${f.batch.name}, ${f.feeAmount == null ? 'no fee set' : pkr(f.feeAmount!)}',
        columns: [
          DataColumnSpec(
            label: 'Course',
            value: (f) => f.batch.courseName,
            flex: 2,
          ),
          DataColumnSpec(label: 'Batch', value: (f) => f.batch.name),
          DataColumnSpec(
            label: 'Campus',
            value: (f) => campusName(context, f.batch.campusId),
          ),
          DataColumnSpec(
            label: 'Learners',
            numeric: true,
            value: (f) => '${f.batch.activeLearners}',
          ),
          DataColumnSpec(
            label: 'Fee',
            numeric: true,
            value: (f) => f.feeAmount == null
                ? 'Not set'
                : '${pkr(f.feeAmount!)}${f.feeFrequency == 'monthly' ? ' / month' : ''}',
          ),
        ],
      ),
    );
  }
}

/// Academy collection report. Never mixed into the school class-wise report.
class AcademyCollectionReport extends StatefulWidget {
  const AcademyCollectionReport({required this.repository, super.key});
  final AcademyRepository repository;

  @override
  State<AcademyCollectionReport> createState() =>
      _AcademyCollectionReportState();
}

class _AcademyCollectionReportState extends State<AcademyCollectionReport> {
  final _loader =
      GlobalKey<
        AcademyLoaderState<({List<CollectionRow> rows, MoneyTotals totals})>
      >();
  final _reload = CampusReload();
  String _period = '';

  bool get _validPeriod =>
      _period.isEmpty || RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(_period);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final filter = listCampus(context, 'fee.manage');
    _reload.track(filter, _loader);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.space6),
          child: Wrap(
            spacing: AppSpacing.space5,
            runSpacing: AppSpacing.space5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: field(
                  'Invoice month (YYYY-MM, blank = all)',
                  _period,
                  (v) => setState(() => _period = v.trim()),
                  error: _validPeriod ? null : 'Use YYYY-MM.',
                ),
              ),
              AppButton(
                label: 'Show',
                onPressed: _validPeriod
                    ? () => _loader.currentState?.reload()
                    : null,
              ),
            ],
          ),
        ),
        Expanded(
          child: AcademyLoader<({List<CollectionRow> rows, MoneyTotals totals})>(
            key: _loader,
            load: () => widget.repository.collection(
              campusId: filter,
              period: _period.isEmpty ? null : _period,
            ),
            isEmpty: (v) => v.rows.isEmpty,
            emptyTitle: 'No academy invoices',
            emptyMessage: 'Generate batch invoices to see collection here.',
            builder: (context, report, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space6,
                  ),
                  child: SectionCard(
                    title: 'Totals (${report.totals.invoices} invoices)',
                    child: Wrap(
                      spacing: AppSpacing.space8,
                      runSpacing: AppSpacing.space4,
                      children: [
                        for (final (label, value) in [
                          ('Billed', report.totals.invoiced),
                          ('Collected', report.totals.collected),
                          ('Outstanding', report.totals.outstanding),
                        ])
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: AppTypography.fieldLabel.copyWith(
                                  color: t.textSecondary,
                                ),
                              ),
                              Text(
                                pkr(value),
                                style: AppTypography.cardHeading.copyWith(
                                  color: t.textPrimary,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.space6),
                  child: InlineAlert(
                    tone: InlineAlertTone.info,
                    message:
                        'Academy invoices only. The school class-wise report is separate and unchanged.',
                  ),
                ),
                Expanded(
                  child: AdaptiveDataView<CollectionRow>(
                    rows: report.rows,
                    semanticLabel: (r) =>
                        '${r.courseName} ${r.batchName} ${r.period}: billed ${pkr(r.totals.invoiced)}, outstanding ${pkr(r.totals.outstanding)}',
                    columns: [
                      DataColumnSpec(
                        label: 'Campus',
                        value: (r) => r.campusName,
                      ),
                      DataColumnSpec(
                        label: 'Course · batch',
                        value: (r) => '${r.courseName} · ${r.batchName}',
                        flex: 2,
                      ),
                      DataColumnSpec(label: 'Month', value: (r) => r.period),
                      DataColumnSpec(
                        label: 'Billed',
                        numeric: true,
                        value: (r) => pkr(r.totals.invoiced),
                      ),
                      DataColumnSpec(
                        label: 'Collected',
                        numeric: true,
                        value: (r) => pkr(r.totals.collected),
                      ),
                      DataColumnSpec(
                        label: 'Outstanding',
                        numeric: true,
                        value: (r) => pkr(r.totals.outstanding),
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

/// Shown when the institution profile could not be read: workflows that depend
/// on it stay hidden (never guessed as School or Academy) until a retry succeeds.
class ProfileUnavailableScreen extends StatelessWidget {
  const ProfileUnavailableScreen({
    required this.onRetry,
    required this.loading,
    super.key,
  });
  final Future<void> Function() onRetry;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(title: 'Institution status'),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const InlineAlert(
                tone: InlineAlertTone.warning,
                message:
                    'The institution profile could not be loaded, so profile-specific workflows (such as Academy courses) '
                    'are hidden until it is confirmed. Other screens work normally.',
              ),
              const SizedBox(height: AppSpacing.space6),
              AppButton(
                label: loading ? 'Checking…' : 'Try again',
                onPressed: loading ? null : onRetry,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
