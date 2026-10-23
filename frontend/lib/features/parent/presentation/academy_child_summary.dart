import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../academy/data/academy_repository.dart';
import '../../academy/domain/academy_models.dart';
import '../../academy/presentation/academy_common.dart';

/// A child's Academy day on the parent landing card (ACADEMY profile only):
/// active batches, today's session attendance and the latest PUBLISHED
/// results. Reuses the learner endpoints the Courses screen uses; the server
/// authorises each call for this parent and never returns drafts (filtered
/// again here as defence in depth).
///
/// A failure (including a 404, which means "not your child" for these
/// endpoints) is shown as an error with a retry, never as "no batches".
class AcademyChildSummary extends StatefulWidget {
  const AcademyChildSummary({
    required this.repository,
    required this.studentId,
    required this.hasSchoolRecord,
    this.now,
    super.key,
  });

  final AcademyRepository repository;
  final String studentId;

  /// True when the School snapshot is shown above. A child with no Academy
  /// batches then needs no Academy section at all.
  final bool hasSchoolRecord;
  final DateTime Function()? now;

  @override
  State<AcademyChildSummary> createState() => _AcademyChildSummaryState();
}

class _AcademyDay {
  const _AcademyDay(this.batches, this.today, this.results);
  final List<Enrollment> batches;
  final List<LearnerAttendance> today;
  final List<LearnerResult> results;
}

class _AcademyChildSummaryState extends State<AcademyChildSummary> {
  late Future<_AcademyDay> _load = _fetch();

  Future<_AcademyDay> _fetch() async {
    final day = isoDate((widget.now ?? DateTime.now)());
    final r = widget.repository;
    // Future.wait: a failure in any call surfaces once, as this load's error
    // (awaiting them one by one left the others' failures unhandled).
    final all = await Future.wait<Object>([
      r.learnerEnrollments(widget.studentId),
      r.learnerAttendance(widget.studentId, day, day),
      r.learnerResults(widget.studentId),
    ]);
    final batches = all[0] as List<Enrollment>;
    final today = all[1] as List<LearnerAttendance>;
    final results = all[2] as List<LearnerResult>;
    final published = [
      for (final x in results)
        if (x.status == 'published') x,
    ]..sort((a, b) => b.assessedOn.compareTo(a.assessedOn));
    return _AcademyDay(
      [
        for (final e in batches)
          if (e.status == 'active') e,
      ],
      today,
      published.take(3).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final meta = AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary);
    return FutureBuilder<_AcademyDay>(
      future: _load,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.only(top: AppSpacing.space4),
            child: LinearProgressIndicator(),
          );
        }
        if (snap.hasError) {
          final f = snap.error;
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f is LoadFailure && f.unreachable
                      ? 'Could not reach the server for course details.'
                      : 'Could not load course details.',
                  style: meta,
                ),
                const SizedBox(height: AppSpacing.space3),
                AppButton(
                  label: 'Retry',
                  semanticsLabel: 'Retry course details',
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.sm,
                  onPressed: () => setState(() {
                    _load = _fetch();
                  }),
                ),
              ],
            ),
          );
        }
        final d = snap.data!;
        if (d.batches.isEmpty) {
          if (widget.hasSchoolRecord) return const SizedBox.shrink();
          return Text(
            'Not enrolled in a class or course batch yet.',
            style: meta,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.space5),
            Semantics(
              header: true,
              child: Text(
                'Courses',
                style: AppTypography.fieldLabel.copyWith(color: t.textPrimary),
              ),
            ),
            const SizedBox(height: AppSpacing.space2),
            for (final b in d.batches)
              Text('${b.courseName} · ${b.batchName}', style: meta),
            const SizedBox(height: AppSpacing.space4),
            Semantics(
              header: true,
              child: Text(
                'Today’s sessions',
                style: AppTypography.fieldLabel.copyWith(color: t.textPrimary),
              ),
            ),
            const SizedBox(height: AppSpacing.space2),
            if (d.today.isEmpty)
              // Not "absent": nothing is recorded until the instructor marks.
              Text('No session attendance recorded today.', style: meta)
            else
              for (final a in d.today)
                MergeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.space2),
                    child: Row(
                      children: [
                        StatusChip(a.status),
                        const SizedBox(width: AppSpacing.space3),
                        Expanded(
                          child: Text(
                            '${a.courseName} · ${a.start}',
                            style: meta,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            if (d.results.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.space4),
              Semantics(
                header: true,
                child: Text(
                  'Latest results',
                  style: AppTypography.fieldLabel.copyWith(
                    color: t.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.space2),
              for (final r in d.results)
                Text(
                  '${r.courseName} · ${r.title}: '
                  '${r.absent ? 'Absent' : '${r.marks ?? '—'} of ${r.maxMarks}'}',
                  style: meta,
                ),
            ],
          ],
        );
      },
    );
  }
}
