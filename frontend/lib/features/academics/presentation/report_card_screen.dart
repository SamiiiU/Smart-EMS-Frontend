import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../setup/presentation/setup_scaffold.dart';
import '../data/academics_repository.dart';
import '../domain/academic_models.dart';

/// Screen 5: one student's report card.
///
/// 🔴 **There is no file.** Re-verified live: the report-card endpoint
/// returns `{generatedAt, available, status}` and nothing else, and both
/// `/pdf` and `/download` are 404. So **no download or print affordance
/// ships** (D-19) — and in particular no print button, which would only
/// print the browser's chrome around a screen that was never laid out for
/// paper.
///
/// The card itself is assembled from the result, which carries the
/// per-subject breakdown. Every number on it is the server's.
class ReportCardScreen extends StatefulWidget {
  const ReportCardScreen({
    required this.repository,
    required this.exam,
    required this.studentId,
    required this.studentName,
    super.key,
  });

  final AcademicsRepository repository;
  final Exam exam;
  final String studentId;
  final String studentName;

  @override
  State<ReportCardScreen> createState() => ReportCardScreenState();
}

class ReportCardScreenState extends State<ReportCardScreen> {
  ScreenState<StudentResult> _state = const ScreenState<StudentResult>.loading();

  /// Null until the exam is published — the endpoint 404s before that,
  /// which is a normal "not ready" state rather than an error.
  ReportCard? _card;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(
        () => _state = ScreenState<StudentResult>.loading(previous: _state.data));
    try {
      final result = await widget.repository.loadStudentResult(
        examId: widget.exam.id,
        studentId: widget.studentId,
      );
      final card = await widget.repository.loadReportCard(
        examId: widget.exam.id,
        studentId: widget.studentId,
      );
      if (!mounted) return;
      setState(() {
        _card = card;
        _state = ScreenState<StudentResult>.data(result, isEmpty: false);
      });
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<StudentResult>.failed(
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
      title: 'Report card',
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height,
          child: ScreenStateBuilder<StudentResult>(
            state: _state,
            onRetry: load,
            emptyTitle: 'No result yet',
            emptyMessage: 'This student has no result for this exam. One '
                'appears as soon as marks are entered.',
            data: _body,
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, StudentResult result) {
    final t = context.tokens;
    final card = _card;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Text(
          widget.studentName,
          style: AppTypography.sectionHeading.copyWith(color: t.textPrimary),
        ),
        const SizedBox(height: AppSpacing.space1),
        Text(
          widget.exam.name,
          style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space5),

        if (card == null)
          const InlineAlert(
            tone: InlineAlertTone.info,
            message: 'The report card is prepared when the exam is '
                'published. The marks below are the current position.',
          )
        else
          InlineAlert(
            tone: InlineAlertTone.success,
            message: 'Report card generated ${card.generatedAt}.',
          ),
        const SizedBox(height: AppSpacing.space6),

        Container(
          padding: const EdgeInsets.all(AppSpacing.space6),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: t.border, width: AppSizing.borderThin),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final subject in result.subjects)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.space3),
                  child: Wrap(
                    spacing: AppSpacing.space4,
                    runSpacing: AppSpacing.space1,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        subject.subjectName,
                        style: AppTypography.personName
                            .copyWith(color: t.textPrimary),
                      ),
                      Text(
                        subject.isAbsent
                            ? 'Absent'
                            : '${subject.marksObtained.format()}'
                                ' / ${subject.maxMarks.format()}',
                        style: AppTypography.personName.copyWith(
                          color: subject.failed
                              ? t.dangerTextOnBg
                              : t.textPrimary,
                        ),
                      ),
                      if (subject.grade.isNotEmpty)
                        Text(
                          subject.grade,
                          style: AppTypography.bodyAdminMeta
                              .copyWith(color: t.textSecondary),
                        ),
                      if (subject.failed)
                        Text(
                          'Below ${subject.passingMarks.format()}',
                          style: AppTypography.bodyAdminMeta
                              .copyWith(color: t.dangerTextOnBg),
                        ),
                    ],
                  ),
                ),
              Divider(color: t.border, height: AppSizing.borderThin),
              const SizedBox(height: AppSpacing.space4),
              Wrap(
                spacing: AppSpacing.space5,
                runSpacing: AppSpacing.space3,
                children: [
                  _Figure(
                    label: 'Total',
                    value: '${result.totalMarks.format()}'
                        ' / ${result.totalMax.format()}',
                  ),
                  _Figure(
                    label: 'Percent',
                    value: result.percentage.formatPercent(),
                  ),
                  if (result.grade.isNotEmpty)
                    _Figure(label: 'Grade', value: result.grade),
                  _Figure(label: 'GPA', value: result.gradePoint.format()),
                  if (result.position != null)
                    _Figure(label: 'Position', value: '${result.position}'),
                  _Figure(
                    label: 'Result',
                    value: result.status == ResultStatus.fail
                        ? 'Failed'
                        : 'Passed',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space5),

        // Stated, not hidden. No download button, and no print button that
        // would only print the browser's chrome.
        const InlineAlert(
          tone: InlineAlertTone.info,
          message: 'This report card cannot be downloaded or printed yet — '
              'this system does not produce a file for it.',
        ),
      ],
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
          value,
          style: AppTypography.personName.copyWith(color: t.textPrimary),
        ),
      ],
    );
  }
}
