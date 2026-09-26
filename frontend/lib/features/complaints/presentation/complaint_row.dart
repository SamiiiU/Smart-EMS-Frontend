import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/status_pill.dart';
import '../domain/complaint_models.dart';

/// One complaint, as a row. Shared by the complainant's list and the admin
/// worklist so the same thing reads the same way in both.
class ComplaintRow extends StatelessWidget {
  const ComplaintRow({
    required this.complaint,
    required this.today,
    this.onTap,
    this.showRaiser = false,
    super.key,
  });

  final Complaint complaint;
  final DateTime today;
  final VoidCallback? onTap;

  /// Admin list only. Never renders an identity for an anonymous complaint —
  /// there is none to render, because the backend stores none.
  final bool showRaiser;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final overdue = complaint.isOverdue(today);
    final age = complaint.ageInDays(today);

    final row = Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space3),
      padding: const EdgeInsets.all(AppSpacing.space5),
      constraints: const BoxConstraints(minHeight: AppSizing.listRowMinHeight),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: overdue ? t.danger : t.border,
          width: AppSizing.borderThin,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap, not Row: a subject, a pill and two meta strings cannot
          // share one line on a 360px phone at a large text scale.
          Wrap(
            spacing: AppSpacing.space4,
            runSpacing: AppSpacing.space2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                complaint.subject,
                style: AppTypography.personName.copyWith(color: t.textPrimary),
              ),
              StatusPill(
                status: complaint.status.pill,
                size: StatusPillSize.sm,
              ),
              // The status word is in the pill's label already; the pill
              // vocabulary is generic, so the complaint's own wording is
              // spelled out rather than left to a colour.
              Text(
                complaint.status.label,
                style: AppTypography.bodyAdminMeta
                    .copyWith(color: t.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space2),
          Wrap(
            spacing: AppSpacing.space4,
            runSpacing: AppSpacing.space2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                complaint.categoryLabel,
                style: AppTypography.bodyAdminMeta
                    .copyWith(color: t.textSecondary),
              ),
              Text(
                age == 0 ? 'Today' : '$age ${age == 1 ? 'day' : 'days'} old',
                style: AppTypography.bodyAdminMeta
                    .copyWith(color: t.textSecondary),
              ),
              if (complaint.priority == ComplaintPriority.high)
                Text(
                  'High priority',
                  style: AppTypography.bodyAdminMeta
                      .copyWith(color: t.warningTextOnBg),
                ),
              if (overdue)
                Text(
                  'Overdue',
                  style: AppTypography.bodyAdminMeta
                      .copyWith(color: t.dangerTextOnBg),
                ),
              if (showRaiser)
                Text(
                  // An anonymous complaint has no identity anywhere in the
                  // payload, so this states the fact rather than a blank.
                  complaint.isAnonymous ? 'Sent anonymously' : 'Named',
                  style: AppTypography.bodyAdminMeta
                      .copyWith(color: t.textSecondary),
                ),
              if (showRaiser && !complaint.isAssigned)
                Text(
                  'Unassigned',
                  style: AppTypography.bodyAdminMeta
                      .copyWith(color: t.warningTextOnBg),
                ),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: '${complaint.subject}, ${complaint.status.label}'
          '${overdue ? ', overdue' : ''}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(child: row),
      ),
    );
  }
}
