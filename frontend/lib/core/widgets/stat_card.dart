import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/sizing.dart';
import '../theme/typography.dart';

enum StatCardTone { neutral, success, warning, danger, info }

/// A number over a label on a tinted background.
///
/// Four uses: the attendance summary strip, admin KPIs, student profile
/// counters, and the CSV import counters.
///
/// The value always uses tabular figures — every style in [AppTypography]
/// enables them, so a column of StatCards aligns.
class StatCard extends StatelessWidget {
  const StatCard({
    required this.value,
    required this.label,
    this.tone = StatCardTone.neutral,
    this.sub,
    this.onTap,
    super.key,
  });

  final String value;
  final String label;
  final StatCardTone tone;
  final String? sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    final (Color bg, Color valueColour) = switch (tone) {
      StatCardTone.neutral => (t.surfaceSunken, t.textPrimary),
      StatCardTone.success => (t.successBg, t.successTextOnBg),
      StatCardTone.warning => (t.warningBg, t.warningTextOnBg),
      StatCardTone.danger => (t.dangerBg, t.dangerTextOnBg),
      StatCardTone.info => (t.infoBg, t.infoTextOnBg),
    };

    // Labels share the value's colour on tinted tones so the whole card stays
    // above 4.5:1; on neutral they step down to textSecondary.
    final labelColour =
        tone == StatCardTone.neutral ? t.textSecondary : valueColour;

    final card = Container(
      padding: const EdgeInsets.all(AppSpacing.space5),
      constraints: const BoxConstraints(minWidth: AppSizing.touchTargetMin),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: AppTypography.screenTitle.copyWith(color: valueColour),
          ),
          const SizedBox(height: AppSpacing.space1),
          Text(
            label,
            style: AppTypography.bodyAdminMeta.copyWith(color: labelColour),
          ),
          if (sub != null) ...[
            const SizedBox(height: AppSpacing.space1),
            Text(
              sub!,
              style: AppTypography.caption.copyWith(color: labelColour),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return Semantics(label: '$label $value', child: card);

    return Semantics(
      button: true,
      label: '$label $value',
      child: GestureDetector(
        onTap: onTap,
        // Opaque so taps anywhere in the card register, including the padding.
        behavior: HitTestBehavior.opaque,
        child: card,
      ),
    );
  }
}
