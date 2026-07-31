import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/typography.dart';
import 'status_pill.dart';

enum ContextStripTone { primary, neutral, semantic }

/// Icon, text, optional trailing action, on a tinted background.
///
/// Four uses: the login school strip, the diary editing strip, the wizard link
/// strip, and the CSV file row.
class ContextStrip extends StatelessWidget {
  const ContextStrip({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.tone = ContextStripTone.primary,
    this.status,
    super.key,
  }) : assert(
          tone != ContextStripTone.semantic || status != null,
          'ContextStripTone.semantic requires a status to take its colour from.',
        );

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final ContextStripTone tone;

  /// Required when [tone] is [ContextStripTone.semantic].
  final AppStatus? status;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    final (Color bg, Color fg, Color titleColour) = switch (tone) {
      ContextStripTone.primary => (
          t.primarySubtle,
          t.primaryAction,
          t.textPrimary,
        ),
      ContextStripTone.neutral => (
          t.surfaceSunken,
          t.textSecondary,
          t.textPrimary,
        ),
      ContextStripTone.semantic => () {
          final c = StatusPill.coloursFor(status!, t);
          return (c.bg, c.glyph, c.text);
        }(),
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.space5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          Icon(icon, size: AppSpacing.space7, color: fg),
          const SizedBox(width: AppSpacing.space5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTypography.personName.copyWith(color: titleColour),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.space1),
                  Text(
                    subtitle!,
                    style: AppTypography.bodyAdminMeta.copyWith(
                      color: tone == ContextStripTone.semantic
                          ? titleColour
                          : t.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.space5),
            trailing!,
          ],
        ],
      ),
    );
  }
}
