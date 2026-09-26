import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../setup/presentation/setup_scaffold.dart';

/// The two screens of this batch that have **no backend at all**.
///
/// Confirmed by listing every one of the API's 130 published paths: there is
/// no grade-scheme endpoint of any kind, and no subject-resource or
/// file-upload endpoint anywhere.
///
/// They still ship, and they still sit in the hub, because the standing rule
/// is to name the limitation rather than hide the control: an admin looking
/// for "where do I set up grades" gets an answer instead of an absence they
/// have to ask about. What they do NOT get is a form that cannot save, or a
/// greyed-out button with no explanation (D-19).
class UnavailableScreen extends StatelessWidget {
  const UnavailableScreen({
    required this.title,
    required this.headline,
    required this.body,
    required this.icon,
    super.key,
  });

  final String title;
  final String headline;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return SetupScaffold(
      title: title,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.space6),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: t.border, width: AppSizing.borderThin),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: t.textSecondary),
              const SizedBox(height: AppSpacing.space4),
              Text(
                headline,
                style:
                    AppTypography.cardHeading.copyWith(color: t.textPrimary),
              ),
              const SizedBox(height: AppSpacing.space3),
              Text(
                body,
                style: AppTypography.bodyAdminMeta
                    .copyWith(color: t.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Screen 1 of the batch — grade schemes and bands.
///
/// Grades ARE assigned (85 → A / 3.70), from a scheme seeded somewhere the
/// API does not expose. So the honest statement is not "grading does not
/// work" but "grading works and cannot be configured here".
class GradeSchemesScreen extends StatelessWidget {
  const GradeSchemesScreen({super.key});

  @override
  Widget build(BuildContext context) => const UnavailableScreen(
        title: 'Grade scheme',
        icon: Icons.workspace_premium_outlined,
        headline: 'Grades are applied automatically',
        body: 'Marks are turned into grades and grade points by the system, '
            'and results show them straight away. The bands behind that — '
            'which percentage earns which grade — cannot be viewed or '
            'changed from the app yet, so a change to them has to go '
            'through your system administrator.',
      );
}

/// Screen 8 of the batch — subject resources.
class SubjectResourcesScreen extends StatelessWidget {
  const SubjectResourcesScreen({super.key});

  @override
  Widget build(BuildContext context) => const UnavailableScreen(
        title: 'Subject resources',
        icon: Icons.folder_outlined,
        headline: 'Not available yet',
        body: 'Books, notes, links and videos for a subject cannot be stored '
            'yet — this system has nowhere to keep them, and no way to '
            'receive an uploaded file. Share material through the diary for '
            'now. This screen will fill in once the school system supports '
            'it; nothing you do here is needed in the meantime.',
      );
}
