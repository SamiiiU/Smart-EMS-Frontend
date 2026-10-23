import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/inline_alert.dart';
import '../data/attendance_review_repository.dart';
import '../../../core/widgets/page_header.dart';

/// Campus reviewers decide held offline attendance (ADR-010). Nothing is
/// applied or discarded automatically; each decision needs a reason.
class AttendanceReviewScreen extends StatefulWidget {
  const AttendanceReviewScreen({required this.repository, super.key});

  final AttendanceReviewRepository repository;

  @override
  State<AttendanceReviewScreen> createState() => _AttendanceReviewScreenState();
}

class _AttendanceReviewScreenState extends State<AttendanceReviewScreen> {
  List<AttendanceReview>? _reviews;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await widget.repository.pending();
    if (!mounted) return;
    setState(() {
      _reviews = result.reviews;
      _error =
          result.failure?.message ??
          (result.reviews == null ? 'Could not load reviews.' : null);
    });
  }

  Future<void> _decide(AttendanceReview review, bool accept) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _ReasonDialog(accept: accept),
    );
    if (reason == null || !mounted) return;
    final failure = await widget.repository.decide(
      review.id,
      accept: accept,
      reason: reason,
    );
    if (!mounted) return;
    if (failure != null) {
      setState(() => _error = failure.message ?? 'The decision was not saved.');
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final reviews = _reviews;
    return Scaffold(
      backgroundColor: t.page,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.space6),
            children: [
              const PageHeader(
                title: 'Attendance reviews',
                padding: EdgeInsets.zero,
              ),
              const SizedBox(height: AppSpacing.space3),
              Text(
                'Offline marks that differed from the office record, or synced after '
                'the closing time + 72 hours. The office record stays until you decide.',
                style: AppTypography.bodyAdminMeta.copyWith(
                  color: t.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.space6),
              if (_error != null) ...[
                InlineAlert(tone: InlineAlertTone.danger, message: _error!),
                const SizedBox(height: AppSpacing.space6),
              ],
              if (reviews == null && _error == null)
                const Center(child: CircularProgressIndicator()),
              if (reviews != null && reviews.isEmpty)
                Text(
                  'Nothing is waiting for review.',
                  style: AppTypography.bodyAdminMeta.copyWith(
                    color: t.textSecondary,
                  ),
                ),
              for (final r in reviews ?? const <AttendanceReview>[])
                Card(
                  key: Key('review-${r.id}'),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.space4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${r.studentName} · ${r.attendanceDate}',
                          style: AppTypography.personName.copyWith(
                            color: t.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.space2),
                        Text(
                          'Teacher marked ${r.submittedStatus}; office record '
                          '${r.currentServerStatus ?? 'none'} · '
                          '${r.reason == 'LATE_SYNC' ? 'synced after the deadline' : 'conflict'}',
                          style: AppTypography.bodyAdminMeta.copyWith(
                            color: t.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.space3),
                        Wrap(
                          spacing: AppSpacing.space3,
                          children: [
                            AppButton(
                              label: 'Apply teacher mark',
                              onPressed: () => _decide(r, true),
                            ),
                            AppButton(
                              label: 'Keep office record',
                              variant: AppButtonVariant.secondary,
                              onPressed: () => _decide(r, false),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.accept});
  final bool accept;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  String _reason = '';

  @override
  Widget build(BuildContext context) {
    final valid = _reason.trim().length >= 3;
    return AlertDialog(
      title: Text(widget.accept ? 'Apply teacher mark' : 'Keep office record'),
      content: AppTextField(
        key: const Key('review-reason'),
        label: 'Reason (recorded)',
        value: _reason,
        autofocus: true,
        onChanged: (v) => setState(() => _reason = v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: valid
              ? () => Navigator.of(context).pop(_reason.trim())
              : null,
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
