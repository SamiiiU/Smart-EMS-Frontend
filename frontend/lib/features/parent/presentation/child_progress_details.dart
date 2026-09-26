import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/progress_bar.dart';
import '../domain/parent_models.dart';

/// The rest of a child's day, from fields `/api/parent-progress/student/{id}`
/// has always returned and T9 never read.
///
/// T9 used only `attendanceStatus`, because the diary (T11) and exams (T15)
/// did not exist and a remark had nowhere to come from. They do now.
///
/// Every section here is **absent when there is nothing to show** rather
/// than rendered as an empty box — a parent opening this wants an answer,
/// and four headings with nothing under them is not one.
///
/// 🔴 The remarks are **server-filtered** to `isParentVisible: true`
/// (verified live: a remark flagged false does not arrive). Nothing is
/// filtered here — if it were, a server regression would be invisible, which
/// is exactly the arrangement T15's remarks defect showed to be unreliable.
class ChildProgressDetails extends StatelessWidget {
  const ChildProgressDetails({required this.today, super.key});

  final ChildToday today;

  @override
  Widget build(BuildContext context) {
    final stats = today.attendanceStats;
    final result = today.latestResult;

    final hasAnything = (stats?.hasData ?? false) ||
        result != null ||
        today.remarks.isNotEmpty ||
        today.diaryEntries.isNotEmpty;

    if (!hasAnything) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.space6),
        if (stats != null && stats.hasData) _Attendance(stats: stats),
        if (result != null) _Result(result: result),
        if (today.diaryEntries.isNotEmpty)
          _Section(
            title: 'Today’s diary',
            children: [
              for (final entry in today.diaryEntries) _Line(text: entry),
            ],
          ),
        if (today.remarks.isNotEmpty)
          _Section(
            title: 'From the teacher',
            children: [
              for (final remark in today.remarks) _Remark(remark: remark),
            ],
          ),
      ],
    );
  }
}

class _Attendance extends StatelessWidget {
  const _Attendance({required this.stats});

  final ChildAttendanceStats stats;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return _Section(
      title: 'Attendance so far',
      children: [
        Text(
          '${stats.percentage}% · ${stats.present} of ${stats.totalDays} days',
          style: AppTypography.personName.copyWith(color: t.textPrimary),
        ),
        const SizedBox(height: AppSpacing.space3),
        // The bar's single documented threshold is 75% (ProgressBar), and
        // the server has its own `belowThreshold`. The WORDS below come from
        // the server's judgement so the app cannot disagree with the school.
        ProgressBar(percent: stats.percentage.toDouble().clamp(0, 100)),
        if (stats.belowThreshold) ...[
          const SizedBox(height: AppSpacing.space3),
          Text(
            'This is below the school’s expected attendance.',
            style:
                AppTypography.bodyParentStudent.copyWith(color: t.warningTextOnBg),
          ),
        ],
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.result});

  final ChildLatestResult result;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return _Section(
      title: 'Latest result',
      children: [
        Text(
          result.examName,
          style: AppTypography.personName.copyWith(color: t.textPrimary),
        ),
        const SizedBox(height: AppSpacing.space2),
        Wrap(
          spacing: AppSpacing.space5,
          runSpacing: AppSpacing.space2,
          children: [
            // Rendered as the server's own text — never re-formatted through
            // a double, which is how 90.00 becomes 89.99999.
            Text(
              '${result.percentage}%',
              style: AppTypography.parentStatusHero
                  .copyWith(color: t.textPrimary),
            ),
            if (result.grade.isNotEmpty)
              Text(
                'Grade ${result.grade}',
                style: AppTypography.bodyParentStudent
                    .copyWith(color: t.textSecondary),
              ),
            if (result.position != null)
              Text(
                'Position ${result.position}',
                style: AppTypography.bodyParentStudent
                    .copyWith(color: t.textSecondary),
              ),
          ],
        ),
      ],
    );
  }
}

class _Remark extends StatelessWidget {
  const _Remark({required this.remark});

  final ChildRemark remark;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            remark.body,
            style:
                AppTypography.bodyParentStudent.copyWith(color: t.textPrimary),
          ),
          const SizedBox(height: AppSpacing.space1),
          Text(
            '${remark.authorName} · ${remark.remarkDate}',
            style: AppTypography.timestamp.copyWith(color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space3),
      child: Text(
        text,
        style: AppTypography.bodyParentStudent.copyWith(color: t.textPrimary),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space4),
      padding: const EdgeInsets.all(AppSpacing.space5),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border, width: AppSizing.borderThin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.overline.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space3),
          ...children,
        ],
      ),
    );
  }
}
