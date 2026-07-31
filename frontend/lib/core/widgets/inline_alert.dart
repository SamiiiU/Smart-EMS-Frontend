import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/typography.dart';

enum InlineAlertTone { info, warning, danger, success }

/// Icon plus message on a semantic background.
///
/// Five uses: the below-75% warning in three places, the CSV re-import note,
/// and the login error.
///
/// ALWAYS INLINE AND PERSISTENT. This is deliberately NOT a snackbar. Phase 3
/// established that a message the user must act on cannot disappear on a
/// timer. There is intentionally:
///
///  - no `duration` parameter,
///  - no auto-dismiss,
///  - no overlay/floating variant,
///  - no `onDismiss`.
///
/// Do not add them. If a message genuinely does not need action, it is not an
/// InlineAlert.
class InlineAlert extends StatelessWidget {
  const InlineAlert({
    required this.tone,
    required this.message,
    this.icon,
    super.key,
  });

  final InlineAlertTone tone;
  final String message;

  /// Optional override. Each tone has a sensible default icon, so the alert is
  /// never icon-less — the icon is part of how the tone is communicated
  /// without relying on colour alone.
  final IconData? icon;

  IconData get _defaultIcon => switch (tone) {
        InlineAlertTone.info => Icons.info_outline,
        InlineAlertTone.warning => Icons.warning_amber_outlined,
        InlineAlertTone.danger => Icons.error_outline,
        InlineAlertTone.success => Icons.check_circle_outline,
      };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    // Text uses the `…TextOnBg` tokens; the icon may use the saturated
    // semantic colour because an icon is non-text (3:1).
    final (Color bg, Color iconColour, Color textColour) = switch (tone) {
      InlineAlertTone.info => (t.infoBg, t.info, t.infoTextOnBg),
      InlineAlertTone.warning => (t.warningBg, t.warning, t.warningTextOnBg),
      InlineAlertTone.danger => (t.dangerBg, t.danger, t.dangerTextOnBg),
      InlineAlertTone.success => (t.successBg, t.success, t.successTextOnBg),
    };

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.space5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon ?? _defaultIcon, size: AppSpacing.space6, color: iconColour),
            const SizedBox(width: AppSpacing.space4),
            Expanded(
              child: Text(
                message,
                style: AppTypography.bodyAdminMeta.copyWith(color: textColour),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
