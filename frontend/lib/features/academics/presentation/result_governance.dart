import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../data/academics_repository.dart';
import '../domain/academic_models.dart';
import '../domain/marks.dart';

/// Asks for a mandatory reason (3–500 characters). Null when cancelled.
Future<String?> askReason(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? hint,
}) {
  var value = '';
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final ok = value.trim().length >= 3 && value.length <= 500;
        return AlertDialog(
          // Fields stay reachable above the phone keyboard.
          scrollable: true,
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hint != null) ...[
                Text(hint),
                const SizedBox(height: AppSpacing.space3),
              ],
              AppTextField(
                label: 'Reason (required)',
                value: value,
                autofocus: true,
                required: true,
                onChanged: (v) => setState(() => value = v),
              ),
            ],
          ),
          actions: [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            AppButton(
              label: confirmLabel,
              onPressed: ok
                  ? () => Navigator.of(dialogContext).pop(value.trim())
                  : null,
            ),
          ],
        );
      },
    ),
  );
}

/// Staff-only C9 actions for one learner's result: withhold/release, and after
/// publication an official correction and the version history. Every action is
/// re-authorized by the server; errors are shown verbatim.
class ResultGovernanceActions extends StatefulWidget {
  const ResultGovernanceActions({
    required this.repository,
    required this.exam,
    required this.result,
    required this.onChanged,
    super.key,
  });

  final AcademicsRepository repository;
  final Exam exam;
  final StudentResult result;
  final VoidCallback onChanged;

  @override
  State<ResultGovernanceActions> createState() =>
      ResultGovernanceActionsState();
}

class ResultGovernanceActionsState extends State<ResultGovernanceActions> {
  String? _error;
  bool _busy = false;

  Future<void> _toggleWithheld() async {
    final withhold = !widget.result.withheld;
    String? reason;
    if (withhold) {
      reason = await askReason(
        context,
        title: 'Withhold ${widget.result.studentName}\'s result?',
        confirmLabel: 'Withhold',
        hint:
            'The learner and guardians will not see this result until it is released.',
      );
      if (reason == null || !mounted) return;
    }
    setState(() => _busy = true);
    final error = await widget.repository.setWithheld(
      examId: widget.exam.id,
      studentId: widget.result.studentId,
      withheld: withhold,
      reason: reason,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null) widget.onChanged();
  }

  Future<void> _correct() async {
    final full = await widget.repository.loadStudentResult(
      examId: widget.exam.id,
      studentId: widget.result.studentId,
    );
    if (!mounted) return;
    final outcome = await showDialog<String?>(
      context: context,
      builder: (_) => CorrectionDialog(
        repository: widget.repository,
        exam: widget.exam,
        result: full,
      ),
    );
    if (!mounted) return;
    if (outcome != null) widget.onChanged();
  }

  Future<void> _history() async {
    final versions = await widget.repository.loadVersions(
      examId: widget.exam.id,
      studentId: widget.result.studentId,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Official versions — ${widget.result.studentName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: versions.isEmpty
              ? [const Text('No official version yet.')]
              : [
                  for (final v in versions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.space2),
                      child: Text(
                        'Version ${v.version}'
                        '${v == versions.last ? ' (in force)' : ' (superseded)'}'
                        ' · total ${v.totalMarks ?? '—'}'
                        '${v.reason == null ? '' : ' · ${v.reason}'}',
                      ),
                    ),
                ],
        ),
        actions: [
          AppButton(
            label: 'Close',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final status = widget.exam.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.space3,
          runSpacing: AppSpacing.space2,
          children: [
            if (status != ExamStatus.archived)
              AppButton(
                label: widget.result.withheld
                    ? 'Release result'
                    : 'Withhold result',
                variant: AppButtonVariant.secondary,
                onPressed: _busy ? null : _toggleWithheld,
              ),
            if (status == ExamStatus.published)
              AppButton(
                label: 'Official correction',
                variant: AppButtonVariant.secondary,
                onPressed: _busy ? null : _correct,
              ),
            if (status.isReleased)
              AppButton(
                label: 'Version history',
                variant: AppButtonVariant.secondary,
                onPressed: _busy ? null : _history,
              ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.space2),
            child: Text(
              _error!,
              style: AppTypography.bodyAdminMeta.copyWith(
                color: t.dangerTextOnBg,
              ),
            ),
          ),
      ],
    );
  }
}

/// Official correction of one paper's mark on a PUBLISHED result (C9). The
/// server records a superseding version; the previous one stays on record.
class CorrectionDialog extends StatefulWidget {
  const CorrectionDialog({
    required this.repository,
    required this.exam,
    required this.result,
    super.key,
  });

  final AcademicsRepository repository;
  final Exam exam;
  final StudentResult result;

  @override
  State<CorrectionDialog> createState() => CorrectionDialogState();
}

class CorrectionDialogState extends State<CorrectionDialog> {
  late final List<SubjectResult> _papers = widget.result.subjects
      .where((s) => s.examSubjectId != null)
      .toList();
  String? _paperId;
  String _marks = '';
  bool _absent = false;
  String _reason = '';
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _paperId = _papers.isEmpty ? null : _papers.first.examSubjectId;
  }

  bool get _valid =>
      _paperId != null &&
      _reason.trim().length >= 3 &&
      (_absent || Marks.tryParse(_marks.trim()) != null);

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await widget.repository.correct(
      examId: widget.exam.id,
      examSubjectId: _paperId!,
      studentId: widget.result.studentId,
      marksObtained: _absent ? null : Marks.tryParse(_marks.trim()),
      isAbsent: _absent,
      reason: _reason.trim(),
    );
    if (!mounted) return;
    if (outcome.error != null) {
      setState(() {
        _busy = false;
        _error = outcome.error;
      });
      return;
    }
    Navigator.of(context).pop('Version ${outcome.version}');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Official correction — ${widget.result.studentName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The published version stays on record; the correction becomes the version in force.',
            ),
            const SizedBox(height: AppSpacing.space3),
            if (_papers.isEmpty)
              const Text('No paper of this result can be corrected.')
            else
              DropdownButton<String>(
                value: _paperId,
                isExpanded: true,
                items: [
                  for (final p in _papers)
                    DropdownMenuItem(
                      value: p.examSubjectId,
                      child: Text(
                        '${p.subjectName} — now '
                        '${p.isAbsent ? 'absent' : p.marksObtained?.format() ?? 'not entered'}'
                        ' / ${p.maxMarks.format()}',
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _paperId = v),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _absent,
              title: const Text('Absent for this paper'),
              onChanged: (v) => setState(() => _absent = v ?? false),
            ),
            if (!_absent)
              AppTextField(
                label: 'Corrected mark',
                value: _marks,
                onChanged: (v) => setState(() => _marks = v),
              ),
            const SizedBox(height: AppSpacing.space3),
            AppTextField(
              label: 'Reason (required)',
              value: _reason,
              required: true,
              onChanged: (v) => setState(() => _reason = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.space3),
              Text(_error!),
            ],
          ],
        ),
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: _busy ? 'Saving…' : 'Record correction',
          onPressed: _valid && !_busy ? _submit : null,
        ),
      ],
    );
  }
}
