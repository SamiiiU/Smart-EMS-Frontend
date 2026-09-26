/// Spacing and radius scales for Smart EMS.
///
/// These are FIXED SETS. A value outside them is a defect, not a choice.
/// They are mode-independent (a gap is the same width in light and dark), so
/// they are plain compile-time constants rather than part of the
/// [SmartEmsTokens] ThemeExtension — there is nothing to lerp.
///
/// `tool/check_tokens.sh` rejects `EdgeInsets` / `BorderRadius` built from
/// bare numeric literals outside `lib/core/theme/`, so consumers must reach
/// for these names.
library;

/// Spacing scale. Use for padding, margins, and gaps.
abstract final class AppSpacing {
  /// No spacing.
  ///
  /// Not a step on the scale — it is the ABSENCE of one, which is why it is
  /// excluded from [all] and from the gallery. It exists so a zero edge in
  /// a multi-sided `EdgeInsets` can be written without a bare literal, and
  /// so the token rule needs no "except zero" exception for anyone to
  /// remember. `EdgeInsets.zero` remains the right choice when every side
  /// is zero.
  static const double none = 0;

  static const double space1 = 2;
  static const double space2 = 4;
  static const double space3 = 6;
  static const double space4 = 8;
  static const double space5 = 12;
  static const double space6 = 16;
  static const double space7 = 20;
  static const double space8 = 24;
  static const double space9 = 32;
  static const double space10 = 40;

  /// Every step, in order. For the token gallery and for tests.
  static const List<(String, double)> all = [
    ('space1', space1),
    ('space2', space2),
    ('space3', space3),
    ('space4', space4),
    ('space5', space5),
    ('space6', space6),
    ('space7', space7),
    ('space8', space8),
    ('space9', space9),
    ('space10', space10),
  ];
}

/// Corner radius scale.
abstract final class AppRadius {
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 10;
  static const double xl = 12;
  static const double xl2 = 14;

  /// Pill / circle. Deliberately larger than any component it is used on.
  static const double full = 999;

  /// Every step, in order. For the token gallery and for tests.
  static const List<(String, double)> all = [
    ('radiusSm', sm),
    ('radiusMd', md),
    ('radiusLg', lg),
    ('radiusXl', xl),
    ('radius2xl', xl2),
    ('radiusFull', full),
  ];
}
