import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../../core/widgets/status_pill.dart';
import '../../setup/presentation/academic_years_screen.dart' show setupListHeight;
import '../../setup/presentation/setup_scaffold.dart';
import '../data/academics_repository.dart';
import '../domain/academic_models.dart';
import 'report_card_screen.dart';

/// Screen 4: results, per exam, per section.
///
/// 🔴 **Every figure here is the server's.** Total, percentage, grade, grade
/// point, position and pass/fail all come back from the API — a single mark
/// POST returns the whole recomputed result — and the app derives none of
/// them. Two sources of truth for a student's GPA is worse than one that is
/// occasionally wrong, because nobody can tell which is right.
///
/// Ordered by what needs attention (D-15): failures first, then borderline
/// passes, then everyone else. A teacher opens this to find who needs help,
/// and alphabetical order scatters the failures through forty rows.
class ResultsScreen extends StatefulWidget {
  const ResultsScreen({
    required this.repository,
    required this.exam,
    required this.sectionId,
    this.sectionName = '',
    super.key,
  });

  final AcademicsRepository repository;
  final Exam exam;
  final String sectionId;
  final String sectionName;

  @override
  State<ResultsScreen> createState() => ResultsScreenState();
}

class ResultsScreenState extends State<ResultsScreen> {
  ScreenState<List<StudentResult>> _state =
      const ScreenState<List<StudentResult>>.loading();

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => _state =
        ScreenState<List<StudentResult>>.loading(previous: _state.data));
    try {
      final rows = await widget.repository.loadSectionResults(
        examId: widget.exam.id,
        sectionId: widget.sectionId,
      );
      if (!mounted) return;
      setState(() => _state = ScreenState<List<StudentResult>>.data(rows));
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<List<StudentResult>>.failed(
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
      title: 'Results',
      note: widget.exam.marksLocked
          ? null
          : const InlineAlert(
              tone: InlineAlertTone.info,
              message: 'These results update as marks are entered. They '
                  'become visible to parents when the exam is published.',
            ),
      children: [
        Text(
          widget.sectionName.isEmpty
              ? widget.exam.name
              : '${widget.exam.name} · ${widget.sectionName}',
          style: AppTypography.sectionHeading.copyWith(color: t.textPrimary),
        ),
        const SizedBox(height: AppSpacing.space2),
        Text(
          'Anyone who failed comes first, then anyone close to the line.',
          style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space5),
        SizedBox(
          height: setupListHeight(context),
          child: ScreenStateBuilder<List<StudentResult>>(
            state: _state,
            onRetry: load,
            emptyTitle: 'No results yet',
            emptyMessage: 'Results appear as soon as marks are entered for '
                'this section.',
            emptyIcon: Icons.school_outlined,
            data: (context, rows) => ListView(
              children: [
                for (final row in rows)
                  ResultRow(
                    result: row,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ReportCardScreen(
                          repository: widget.repository,
                          exam: widget.exam,
                          studentId: row.studentId,
                          studentName: row.studentName,
                        ),
                      ),
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

/// One student's result row.
class ResultRow extends StatelessWidget {
  const ResultRow({required this.result, this.onTap, super.key});

  final StudentResult result;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final failed = result.status == ResultStatus.fail;

    final row = Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space3),
      padding: const EdgeInsets.all(AppSpacing.space5),
      constraints: const BoxConstraints(minHeight: AppSizing.listRowMinHeight),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: failed ? t.danger : t.border,
          width: AppSizing.borderThin,
        ),
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
                result.studentName,
                style: AppTypography.personName.copyWith(color: t.textPrimary),
              ),
              StatusPill(status: result.status.pill, size: StatusPillSize.sm),
              // The pill vocabulary has no pass/fail, so the word is said
              // rather than left to a colour (D-21).
              Text(
                failed ? 'Failed' : 'Passed',
                style: AppTypography.bodyAdminMeta.copyWith(
                  color: failed ? t.dangerTextOnBg : t.textSecondary,
                ),
              ),
              if (result.isBorderline)
                Text(
                  'Close to the line',
                  style: AppTypography.bodyAdminMeta
                      .copyWith(color: t.warningTextOnBg),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.space2),
          Wrap(
            spacing: AppSpacing.space4,
            runSpacing: AppSpacing.space2,
            children: [
              _Figure(
                label: 'Marks',
                value: '${result.totalMarks.format()}'
                    ' / ${result.totalMax.format()}',
              ),
              _Figure(label: 'Percent', value: result.percentage.formatPercent()),
              if (result.grade.isNotEmpty)
                _Figure(label: 'Grade', value: result.grade),
              _Figure(label: 'GPA', value: result.gradePoint.format()),
              if (result.position != null)
                _Figure(label: 'Position', value: '${result.position}'),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: '${result.studentName}, '
          '${result.percentage.formatPercent()}, '
          'grade ${result.grade}, ${failed ? 'failed' : 'passed'}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(child: row),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

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
          // Every style in this scale is already tabular, so a column of
          // marks lines up digit for digit.
          value,
          style: AppTypography.personName.copyWith(color: t.textPrimary),
        ),
      ],
    );
  }
}
