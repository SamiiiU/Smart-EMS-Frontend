import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../data/setup_repository.dart';
import '../domain/setup_models.dart';

/// C8: one academic year with its lifecycle state and the single forward step
/// the server accepts (draft → active → closing → archived). A legacy year the
/// V54 backfill could not verify shows "Needs classification" and is never
/// presented as archived; classifying it needs a stated reason. The server
/// enforces campus scope, forward-only moves and "current years cannot be
/// archived"; its refusals are shown verbatim.
class AcademicYearLifecycleRow extends StatefulWidget {
  const AcademicYearLifecycleRow({
    required this.year,
    required this.repository,
    required this.onChanged,
    super.key,
  });

  final AcademicYear year;
  final SetupRepository repository;
  final VoidCallback onChanged;

  @override
  State<AcademicYearLifecycleRow> createState() =>
      AcademicYearLifecycleRowState();
}

class AcademicYearLifecycleRowState extends State<AcademicYearLifecycleRow> {
  bool _busy = false;
  String? _error;

  String get _stateLabel =>
      widget.year.reviewRequired || widget.year.status == null
      ? 'Needs classification'
      : widget.year.status!.label;

  Future<void> _guard(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onChanged();
    } on LoadFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = f.message ?? 'The change was refused.';
      });
    }
  }

  Future<void> _advance() async {
    final next = widget.year.status?.next;
    if (next == null) return;
    final ok = await confirmAction(
      context,
      title: '${widget.year.status!.nextActionLabel} “${widget.year.name}”?',
      message: switch (next) {
        YearStatus.active =>
          'The year becomes active for teaching and enrolment.',
        YearStatus.closing =>
          'The year starts closing. It stays writable until it is archived.',
        YearStatus.archived =>
          'Archived years are read-only: no new attendance, marks or '
              'teaching assignments. This cannot be undone.',
        YearStatus.draft => '',
      },
      confirmLabel: widget.year.status!.nextActionLabel!,
      irreversible: next == YearStatus.archived,
    );
    if (!ok || !mounted) return;
    await _guard(() => widget.repository.transitionYear(widget.year.id, next));
  }

  Future<void> _classify() async {
    final choice = await showDialog<(YearStatus, String)>(
      context: context,
      builder: (_) => _ClassifyDialog(yearName: widget.year.name),
    );
    if (choice == null || !mounted) return;
    await _guard(
      () =>
          widget.repository.classifyYear(widget.year.id, choice.$1, choice.$2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final y = widget.year;
    final needsReview = y.reviewRequired || y.status == null;
    return Semantics(
      container: true,
      label:
          '${y.name}, ${y.rangeLabel}, $_stateLabel${y.current ? ', current' : ''}',
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.space3),
        padding: const EdgeInsets.all(AppSpacing.space5),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: needsReview ? t.warning : t.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.space3,
              runSpacing: AppSpacing.space1,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  y.name,
                  style: AppTypography.personName.copyWith(
                    color: t.textPrimary,
                  ),
                ),
                Text(
                  _stateLabel,
                  style: AppTypography.bodyAdminMeta.copyWith(
                    color: needsReview ? t.warningTextOnBg : t.textSecondary,
                  ),
                ),
                if (y.current)
                  Text(
                    'Current',
                    style: AppTypography.bodyAdminMeta.copyWith(
                      color: t.textSecondary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.space1),
            Text(
              y.rangeLabel,
              style: AppTypography.bodyAdminMeta.copyWith(
                color: t.textSecondary,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.space2),
              Text(
                _error!,
                style: AppTypography.bodyAdminMeta.copyWith(
                  color: t.dangerTextOnBg,
                ),
              ),
            ],
            if (needsReview || y.status?.nextActionLabel != null) ...[
              const SizedBox(height: AppSpacing.space3),
              AppButton(
                label: _busy
                    ? 'Working…'
                    : (needsReview
                          ? 'Classify year'
                          : y.status!.nextActionLabel!),
                variant: AppButtonVariant.secondary,
                onPressed: _busy ? null : (needsReview ? _classify : _advance),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ClassifyDialog extends StatefulWidget {
  const _ClassifyDialog({required this.yearName});

  final String yearName;

  @override
  State<_ClassifyDialog> createState() => _ClassifyDialogState();
}

class _ClassifyDialogState extends State<_ClassifyDialog> {
  YearStatus? _status;
  String _reason = '';

  @override
  Widget build(BuildContext context) {
    final ok = _status != null && _reason.trim().length >= 3;
    return AlertDialog(
      title: Text('Classify “${widget.yearName}”'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This year was created before year states existed. Choose the state it '
            'really is in, and say why. It is not assumed to be archived.',
          ),
          const SizedBox(height: AppSpacing.space3),
          DropdownButton<YearStatus>(
            key: const Key('classify-status'),
            value: _status,
            isExpanded: true,
            hint: const Text('Choose a state'),
            items: [
              for (final s in YearStatus.values)
                DropdownMenuItem(value: s, child: Text(s.label)),
            ],
            onChanged: (v) => setState(() => _status = v),
          ),
          const SizedBox(height: AppSpacing.space3),
          AppTextField(
            label: 'Reason (required)',
            value: _reason,
            required: true,
            onChanged: (v) => setState(() => _reason = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: ok
              ? () => Navigator.of(context).pop((_status!, _reason.trim()))
              : null,
          child: const Text('Classify'),
        ),
      ],
    );
  }
}
