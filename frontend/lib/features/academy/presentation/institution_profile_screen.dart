import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/section_card.dart';
import '../data/academy_repository.dart';
import '../domain/academy_models.dart';
import 'academy_common.dart';

/// Institution profile (SCHOOL / PRE_UNIVERSITY_COLLEGE / ACADEMY). Shows the
/// capabilities the server says are implemented — no aspirational ones.
/// Changing it needs an institution-wide campus.manage grant and a reason;
/// leaving ACADEMY once academy records exist is refused by the server.
/// A profile is never a permission.
class InstitutionProfileScreen extends StatefulWidget {
  const InstitutionProfileScreen({
    required this.repository,
    required this.canChange,
    this.onChanged,
    super.key,
  });
  final AcademyRepository repository;

  /// Institution-wide campus.manage (owners / institution admins).
  final bool canChange;

  /// Lets the shell re-read the profile so Academy navigation appears/disappears.
  final Future<void> Function()? onChanged;

  @override
  State<InstitutionProfileScreen> createState() =>
      _InstitutionProfileScreenState();
}

class _InstitutionProfileScreenState extends State<InstitutionProfileScreen> {
  final _loader = GlobalKey<AcademyLoaderState<InstitutionProfile>>();

  static const _capabilityLabels = {
    'CLASS_SECTION_ENROLLMENT': 'Class and section enrollment',
    'DAILY_ATTENDANCE': 'Daily attendance',
    'EXAMS': 'Exams and results',
    'TIMETABLE_SOLVER': 'Timetable generation',
    'CLASS_FEE_PLANS': 'Class fee plans',
    'OFFLINE_ATTENDANCE': 'Offline attendance',
    'COURSE_CATALOGUE': 'Course catalogue',
    'COURSE_OFFERINGS': 'Campus course offerings',
    'BATCHES': 'Batches',
    'MULTI_BATCH_ENROLLMENT': 'Learners in several batches',
    'BATCH_INSTRUCTORS': 'Batch instructors',
    'BATCH_SCHEDULES': 'Batch schedules and sessions',
    'SESSION_ATTENDANCE_ONLINE': 'Session attendance (online only)',
    'BATCH_ASSESSMENTS': 'Batch assessments',
    'BATCH_FEES': 'Batch fees',
  };

  Future<void> _change(InstitutionProfile current) async {
    var profile = current.profile, reason = '';
    final ok = await showFormDialog(
      context,
      title: 'Change institution profile',
      submitLabel: 'Change profile',
      canSubmit: () => profile != current.profile && reason.trim().length >= 3,
      fields: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          dropdown<String>('Profile', profile, [
            for (final e in InstitutionProfile.labels.entries) (e.key, e.value),
          ], (v) => setState(() => profile = v ?? current.profile)),
          if (profile == 'PRE_UNIVERSITY_COLLEGE')
            const InlineAlert(
              tone: InlineAlertTone.info,
              message:
                  'Pre-university colleges use the same class and section workflows as schools. No separate college workflow exists.',
            ),
          if (profile == 'ACADEMY')
            const InlineAlert(
              tone: InlineAlertTone.info,
              message:
                  'Adds courses, batches, sessions and batch fees. Existing classes, sections and records are not changed.',
            ),
          const SizedBox(height: AppSpacing.space5),
          field(
            'Reason (recorded in the audit log)',
            reason,
            (v) => setState(() => reason = v),
            required: true,
          ),
        ],
      ),
      submit: () => attempt(
        () => widget.repository.changeProfile(profile, reason.trim()),
      ),
    );
    if (ok) {
      await _loader.currentState?.reload();
      await widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          title: 'Institution profile',
          subtitle: 'Decides which workflows this institution uses',
        ),
        Expanded(
          child: AcademyLoader<InstitutionProfile>(
            key: _loader,
            load: widget.repository.profile,
            emptyTitle: '',
            emptyMessage: '',
            builder: (context, p, _) => ListView(
              padding: const EdgeInsets.all(AppSpacing.space6),
              children: [
                SectionCard(
                  title: 'Current profile',
                  trailing: widget.canChange
                      ? AppButton(
                          label: 'Change',
                          size: AppButtonSize.sm,
                          onPressed: () => _change(p),
                        )
                      : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        InstitutionProfile.labels[p.profile] ?? p.profile,
                        style: AppTypography.cardHeading.copyWith(
                          color: t.textPrimary,
                        ),
                      ),
                      if (!widget.canChange)
                        Text(
                          'Only owners and institution administrators can change this.',
                          style: AppTypography.bodyAdminMeta.copyWith(
                            color: t.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.space6),
                SectionCard(
                  title: 'Available workflows',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final c in p.capabilities)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.space2,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                size: 18,
                                color: t.success,
                              ),
                              const SizedBox(width: AppSpacing.space4),
                              Expanded(child: Text(_capabilityLabels[c] ?? c)),
                            ],
                          ),
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
