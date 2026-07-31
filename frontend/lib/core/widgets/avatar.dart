import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/sizing.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'status_pill.dart';

enum AvatarSize { s24, s28, s32, s40, s56 }

enum AvatarTone { neutral, primary, semantic }

extension AvatarSizeDiameter on AvatarSize {
  double get diameter => switch (this) {
        AvatarSize.s24 => AppSizing.avatar24,
        AvatarSize.s28 => AppSizing.avatar28,
        AvatarSize.s32 => AppSizing.avatar32,
        AvatarSize.s40 => AppSizing.avatar40,
        AvatarSize.s56 => AppSizing.avatar56,
      };
}

/// Initials on a tinted circle.
///
/// Tint comes from `primarySubtle` by default ([AvatarTone.primary]), or from
/// the semantic role when the row carries a status ([AvatarTone.semantic] +
/// [status]).
class Avatar extends StatelessWidget {
  const Avatar({
    required this.initials,
    this.size = AvatarSize.s32,
    this.tone = AvatarTone.primary,
    this.status,
    super.key,
  }) : assert(
          tone != AvatarTone.semantic || status != null,
          'AvatarTone.semantic requires a status to take its colour from.',
        );

  final String initials;
  final AvatarSize size;
  final AvatarTone tone;

  /// Required when [tone] is [AvatarTone.semantic]; ignored otherwise.
  final AppStatus? status;

  ({Color fg, Color bg}) _colours(SmartEmsTokens t) {
    switch (tone) {
      case AvatarTone.neutral:
        return (fg: t.textSecondary, bg: t.surfaceSunken);
      case AvatarTone.primary:
        return (fg: t.primaryAction, bg: t.primarySubtle);
      case AvatarTone.semantic:
        // Initials are TEXT, so take the accessible `…TextOnBg` pairing
        // rather than the saturated glyph colour.
        final c = StatusPill.coloursFor(status!, t);
        return (fg: c.text, bg: c.bg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colours = _colours(t);
    final d = size.diameter;

    return Semantics(
      label: initials,
      child: Container(
        width: d,
        height: d,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: colours.bg, shape: BoxShape.circle),
        child: Text(
          initials,
          style: AppTypography.avatarInitials(d).copyWith(color: colours.fg),
        ),
      ),
    );
  }
}
