import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/typography.dart';

/// The two hero variants. The distinction is LOAD-BEARING per D-23:
///
///  - [HeroCardBrand]  — `brandSurface`,   carries NO action.
///    Used for the parent status hero and the login header.
///  - [HeroCardTinted] — `primarySubtle`,  carries an action.
///    Used for the teacher and student current-period cards.
///
/// A primary button on `#0A5D4E` fails contrast, so an action-carrying hero
/// MUST use the tinted variant.
///
/// This is enforced STRUCTURALLY, not by documentation: [HeroCardBrand] has no
/// action parameter at all, so `HeroCardBrand(action: ...)` does not compile.
/// [HeroCardTinted] makes `action` REQUIRED, so an action-carrying hero cannot
/// accidentally be built without one either. There is no single class with an
/// optional action, because that is exactly the shape that would let a button
/// land on brandSurface.
sealed class HeroCard extends StatelessWidget {
  const HeroCard({super.key});
}

/// Brand hero — decorative surface, NO action.
///
/// There is deliberately no `action`, `onTap`, `button`, or `trailing`
/// parameter. If you need an action, you need [HeroCardTinted].
class HeroCardBrand extends HeroCard {
  const HeroCardBrand({
    required this.title,
    this.eyebrow,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.space7),
      decoration: BoxDecoration(
        color: t.brandSurface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (eyebrow != null) ...[
            Text(
              eyebrow!.toUpperCase(),
              style: AppTypography.overlineTracked.copyWith(
                color: t.onBrandMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.space3),
          ],
          Text(
            title,
            style: AppTypography.parentStatusHero.copyWith(color: t.onBrand),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.space2),
            Text(
              subtitle!,
              style: AppTypography.bodyParentStudent.copyWith(
                color: t.onBrandMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tinted hero — `primarySubtle`, carries a required action.
class HeroCardTinted extends HeroCard {
  const HeroCardTinted({
    required this.title,
    required this.action,
    this.eyebrow,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;

  /// REQUIRED. The tinted variant exists precisely because it can carry an
  /// action at adequate contrast; one without an action should be a
  /// [HeroCardBrand] or a SectionCard.
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.space7),
      decoration: BoxDecoration(
        color: t.primarySubtle,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (eyebrow != null) ...[
            Text(
              eyebrow!.toUpperCase(),
              style: AppTypography.overlineTracked.copyWith(
                color: t.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.space3),
          ],
          Text(
            title,
            style: AppTypography.cardHeading.copyWith(color: t.textPrimary),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.space2),
            Text(
              subtitle!,
              style: AppTypography.bodyAdminMeta.copyWith(
                color: t.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.space6),
          action,
        ],
      ),
    );
  }
}
