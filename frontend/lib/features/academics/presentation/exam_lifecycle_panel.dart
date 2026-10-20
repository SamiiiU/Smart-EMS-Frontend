import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/status_pill.dart';
import '../data/academics_repository.dart';
import '../domain/academic_models.dart';

/// C9 exam lifecycle controls:
/// draft → marking → submitted → moderation → approved → published → archived.
///
/// Offers only the single next step the server accepts, and only to someone
/// holding exam.manage on the exam's campus ([canManage]). The server stays
/// the authority: a refused step (409) or an incomplete approval (400) is
/// shown verbatim and the displayed stage does not move. Publishing goes
/// through the separate publish operation and only from APPROVED.
class ExamLifecyclePanel extends StatefulWidget {
  const ExamLifecyclePanel({
    required this.repository,
    required this.exam,
    required this.status,
    required this.canManage,
    required this.onChanged,
    super.key,
  });

  final AcademicsRepository repository;
  final Exam exam;
  final ExamStatus status;
  final bool canManage;
  final ValueChanged<ExamStatus> onChanged;

  @override
  State<ExamLifecyclePanel> createState() => ExamLifecyclePanelState();
}

class ExamLifecyclePanelState extends State<ExamLifecyclePanel> {
  bool _busy = false;
  String? _error;
  PublishResult? _published;

  static const _stages = [
    ExamStatus.draft,
    ExamStatus.marking,
    ExamStatus.submitted,
    ExamStatus.moderation,
    ExamStatus.approved,
    ExamStatus.published,
    ExamStatus.archived,
  ];

  String get _explanation => switch (widget.status) {
    ExamStatus.draft || ExamStatus.marking =>
      'Teachers enter marks. Submit the exam for moderation when marking is finished.',
    ExamStatus.submitted =>
      'Marks are locked while the exam waits for moderation. Every learner '
          'without marks is shown as incomplete, never as zero.',
    ExamStatus.moderation =>
      'Moderators can fix marks. Approval needs every result complete, or '
          'withheld with a reason.',
    ExamStatus.approved =>
      'Results are approved but not yet visible to learners or guardians.',
    ExamStatus.published =>
      'Results are visible to learners and guardians, except withheld ones. '
          'Changes now need an official correction, which keeps the previous version.',
    ExamStatus.archived => 'This exam is archived. Its results stay visible.',
  };

  Future<void> _advance() async {
    final target = widget.status.next;
    if (target == null) return;
    final publishing = target == ExamStatus.published;
    final confirmed = await confirmAction(
      context,
      title: '${widget.status.nextActionLabel}?',
      message: switch (target) {
        ExamStatus.submitted =>
          'Marks will be locked while the exam waits for moderation.',
        ExamStatus.approved =>
          'Approved results cannot be edited. They become visible only when published.',
        ExamStatus.published =>
          'Results and report cards become available to learners and guardians. '
              'Afterwards, only an official correction can change a result.',
        ExamStatus.archived =>
          'The exam is closed for good. Results stay visible.',
        _ => 'The exam moves to "${target.label}".',
      },
      confirmLabel: widget.status.nextActionLabel ?? 'Continue',
      irreversible: publishing || target == ExamStatus.archived,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    if (publishing) {
      final outcome = await widget.repository.publish(widget.exam.id);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = outcome.error;
        _published = outcome.result;
      });
      if (outcome.result != null) widget.onChanged(ExamStatus.published);
    } else {
      final outcome = await widget.repository.transition(
        widget.exam.id,
        target,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = outcome.error;
      });
      if (outcome.status != null) widget.onChanged(outcome.status!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final action = widget.status.nextActionLabel;
    final currentIndex = _stages.indexOf(widget.status);

    return Semantics(
      container: true,
      label: 'Exam stage: ${widget.status.label}',
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.space5),
        padding: const EdgeInsets.all(AppSpacing.space5),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: t.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.space3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Stage: ${widget.status.label}',
                  style: AppTypography.sectionHeading.copyWith(
                    color: t.textPrimary,
                  ),
                ),
                StatusPill(status: widget.status.pill, size: StatusPillSize.sm),
              ],
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(
              [
                for (var i = 0; i < _stages.length; i++)
                  i == currentIndex
                      ? '[${_stages[i].label}]'
                      : _stages[i].label,
              ].join(' → '),
              style: AppTypography.bodyAdminMeta.copyWith(
                color: t.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.space3),
            Text(
              _explanation,
              style: AppTypography.bodyAdminMeta.copyWith(
                color: t.textSecondary,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.space4),
              InlineAlert(tone: InlineAlertTone.danger, message: _error!),
            ],
            if (_published != null) ...[
              const SizedBox(height: AppSpacing.space4),
              InlineAlert(
                tone: InlineAlertTone.success,
                message:
                    '${_published!.resultsPublished} '
                    '${_published!.resultsPublished == 1 ? 'result' : 'results'} published. '
                    '${_published!.reportCardsQueued} report cards queued for preparation.',
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.space4),
              if (widget.canManage)
                AppButton(
                  label: _busy ? 'Working…' : action,
                  fullWidth: true,
                  onPressed: _busy ? null : _advance,
                )
              else
                Text(
                  'Only an exam manager for this campus can move the exam to the next stage.',
                  style: AppTypography.bodyAdminMeta.copyWith(
                    color: t.textSecondary,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
