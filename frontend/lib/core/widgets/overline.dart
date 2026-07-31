import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/typography.dart';

/// The small uppercase section label that appears on every composed screen.
///
/// 12/600, textSecondary, 0.06em letter spacing, uppercase.
///
/// COLOUR CORRECTED (T3 RULING 2): was textMuted, which measured 2.39:1 on
/// surface in light mode — far below the 4.5:1 AA floor, and 12px is not
/// "large" text under WCAG. Overline is a section LABEL, not decoration, so
/// textSecondary is both accessible (~7:1) and the more correct semantic.
///
/// Uppercasing happens here rather than at each call site so the same string
/// can be passed to `Semantics` in its natural case — screen readers should
/// not spell out an all-caps label letter by letter.
class Overline extends StatelessWidget {
  const Overline(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      label: text,
      child: ExcludeSemantics(
        child: Text(
          text.toUpperCase(),
          style: AppTypography.overlineTracked.copyWith(color: t.textSecondary),
        ),
      ),
    );
  }
}
