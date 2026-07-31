import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/sizing.dart';
import '../theme/typography.dart';

/// Bordered container with an optional header row and trailing action.
///
/// Used for parent sections, student profile cards, and dashboard panels.
///
/// Border, never shadow (D-28) — structure is carried by the border so the
/// card keeps its shape against a near-black dark surface.
class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.child,
    this.title,
    this.trailing,
    this.padded = true,
    super.key,
  });

  final Widget child;
  final String? title;
  final Widget? trailing;

  /// Set false when the child manages its own padding — e.g. a list of
  /// [ListRow]s that should run edge to edge.
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hasHeader = title != null || trailing != null;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border, width: AppSizing.borderThin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space6,
                AppSpacing.space5,
                AppSpacing.space5,
                AppSpacing.space4,
              ),
              child: Row(
                children: [
                  if (title != null)
                    Expanded(
                      child: Text(
                        title!,
                        style: AppTypography.cardHeading.copyWith(
                          color: t.textPrimary,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  ?trailing,
                ],
              ),
            ),
          if (hasHeader)
            Divider(
              height: AppSizing.borderThin,
              thickness: AppSizing.borderThin,
              color: t.border,
            ),
          Padding(
            padding: padded
                ? const EdgeInsets.all(AppSpacing.space6)
                : EdgeInsets.zero,
            child: child,
          ),
        ],
      ),
    );
  }
}
