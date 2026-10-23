import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/loading_skeleton.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../setup/presentation/setup_scaffold.dart';
import '../data/academics_repository.dart';
import '../domain/academic_models.dart';

/// The two screens of this batch that have **no backend at all**.
///
/// Confirmed by listing every one of the API's 130 published paths: there is
/// no grade-scheme endpoint of any kind, and no subject-resource or
/// subject-resource catalogue endpoint. Shared private /api/files storage now exists;
/// its upload/gallery UI is separate from this unavailable subject catalogue.
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
                style: AppTypography.cardHeading.copyWith(color: t.textPrimary),
              ),
              const SizedBox(height: AppSpacing.space3),
              Text(
                body,
                style: AppTypography.bodyAdminMeta.copyWith(
                  color: t.textSecondary,
                ),
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
///
/// D-20: once the proposed read-only `GET /api/grade-schemes/default` exists,
/// the bands are shown (view only — grading rules are unchanged). Until then,
/// or on any failure, the honest explanation below is shown instead.
class GradeSchemesScreen extends StatefulWidget {
  const GradeSchemesScreen({this.repository, super.key});

  final AcademicsRepository? repository;

  @override
  State<GradeSchemesScreen> createState() => GradeSchemesScreenState();
}

class GradeSchemesScreenState extends State<GradeSchemesScreen> {
  GradeSchemeLoad? _result;
  String? _failure;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = widget.repository;
    if (repo == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final r = await repo.loadDefaultGradeScheme();
      if (!mounted) return;
      setState(() {
        _result = r;
        _loading = false;
      });
    } on LoadFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _failure = f.unreachable
            ? 'Could not reach the server. Check the connection and try again.'
            : (f.message ?? 'The grade scheme could not be loaded.');
        _loading = false;
      });
    } on Object catch (_) {
      if (!mounted) return;
      setState(() {
        _failure = 'The grade scheme could not be loaded.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SetupScaffold(
        title: 'Grade scheme',
        children: [LoadingSkeleton.listRows(count: 5)],
      );
    }
    // Network or server failure: say so and offer Retry. Never disguised as
    // "not available".
    if (_failure != null) {
      return SetupScaffold(
        title: 'Grade scheme',
        children: [
          InlineAlert(tone: InlineAlertTone.danger, message: _failure!),
          const SizedBox(height: AppSpacing.space4),
          AppButton(label: 'Try again', onPressed: _load),
        ],
      );
    }
    switch (_result?.outcome) {
      case GradeSchemeOutcome.notConfigured:
        return const UnavailableScreen(
          title: 'Grade scheme',
          icon: Icons.workspace_premium_outlined,
          headline: 'No grade scheme is set up',
          body:
              'This institution has no default grade scheme yet, so the '
              'bands cannot be shown. Ask your system administrator to set '
              'one up.',
        );
      case GradeSchemeOutcome.notPermitted:
        return const UnavailableScreen(
          title: 'Grade scheme',
          icon: Icons.lock_outline,
          headline: 'Not available for your role',
          body:
              'The grade bands are visible to staff who set up or mark '
              'exams.',
        );
      case GradeSchemeOutcome.loaded:
      case GradeSchemeOutcome.unsupported:
      case null:
        break;
    }
    final scheme = _result?.scheme;
    if (scheme != null && scheme.bands.isEmpty) {
      return const UnavailableScreen(
        title: 'Grade scheme',
        icon: Icons.workspace_premium_outlined,
        headline: 'The grade scheme has no bands',
        body:
            'A default scheme exists but has no grade bands. Ask your '
            'system administrator to complete it.',
      );
    }
    if (scheme == null) {
      // Older backend without the endpoint (or no repository): the
      // original explanation, which is accurate there.
      return const UnavailableScreen(
        title: 'Grade scheme',
        icon: Icons.workspace_premium_outlined,
        headline: 'Grades are applied automatically',
        body:
            'Marks are turned into grades and grade points by the system, '
            'and results show them straight away. The bands behind that — '
            'which percentage earns which grade — cannot be viewed or '
            'changed from the app yet, so a change to them has to go '
            'through your system administrator.',
      );
    }
    final t = context.tokens;
    return SetupScaffold(
      title: 'Grade scheme',
      children: [
        Text(
          '${scheme.name}. View only — a change to the bands goes through '
          'your system administrator.',
          style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space4),
        for (final b in scheme.bands)
          Semantics(
            container: true,
            label:
                'Grade ${b.grade}: ${b.minPercentage} to '
                '${b.maxPercentage} percent, grade point ${b.gradePoint}'
                '${b.remark == null ? '' : ', ${b.remark}'}',
            child: ExcludeSemantics(
              child: Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.space3),
                padding: const EdgeInsets.all(AppSpacing.space5),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(
                    color: t.border,
                    width: AppSizing.borderThin,
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: AppSpacing.space10,
                      child: Text(
                        b.grade,
                        style: AppTypography.cardHeading.copyWith(
                          color: t.textPrimary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${b.minPercentage}% – ${b.maxPercentage}%'
                        '${b.remark == null ? '' : ' · ${b.remark}'}',
                        style: AppTypography.bodyAdminMeta.copyWith(
                          color: t.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      'GP ${b.gradePoint}',
                      style: AppTypography.bodyAdminMeta.copyWith(
                        color: t.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// Subject resources (D-21) is now a real screen: subject_resources_screen.dart.
