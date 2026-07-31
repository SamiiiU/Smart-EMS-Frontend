import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography for Smart EMS.
///
/// Typeface: Plus Jakarta Sans, via `google_fonts`.
///
/// FALLBACK NOTE: Inter is the documented fallback if Plus Jakarta Sans
/// proves weak on low-end Android rendering. This is recorded deliberately
/// as a note only — there is NO runtime switch. If the swap becomes
/// necessary, change [_font] here and nowhere else.
///
/// Rules this file enforces:
///  - Nothing below 12px.
///  - Exactly three weights: 400, 500, 600.
///  - Tabular figures on every style, so counts, percentages, and PKR
///    amounts align when stacked in columns.
abstract final class AppTypography {
  /// Tabular figures. Applied to every style in the system — numeric content
  /// (attendance counts, percentages, PKR amounts) appears at every size and
  /// in every role, so there is no style that is safe to leave proportional.
  static const List<FontFeature> tabularFigures = [
    FontFeature.tabularFigures(),
  ];

  static TextStyle _font({
    required double fontSize,
    required FontWeight fontWeight,
  }) {
    return GoogleFonts.plusJakartaSans(
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontFeatures: tabularFigures,
    );
  }

  /// 28/600 — parent status hero.
  static TextStyle get parentStatusHero =>
      _font(fontSize: 28, fontWeight: FontWeight.w600);

  /// 24/600 — screen title.
  static TextStyle get screenTitle =>
      _font(fontSize: 24, fontWeight: FontWeight.w600);

  /// 20/500 — section heading.
  static TextStyle get sectionHeading =>
      _font(fontSize: 20, fontWeight: FontWeight.w500);

  /// 18/500 — card heading.
  static TextStyle get cardHeading =>
      _font(fontSize: 18, fontWeight: FontWeight.w500);

  /// 16/500 — person names, list primary.
  static TextStyle get personName =>
      _font(fontSize: 16, fontWeight: FontWeight.w500);

  /// 16/400 — body for parent and student roles.
  static TextStyle get bodyParentStudent =>
      _font(fontSize: 16, fontWeight: FontWeight.w400);

  /// 15/400 — body for the teacher role.
  static TextStyle get bodyTeacher =>
      _font(fontSize: 15, fontWeight: FontWeight.w400);

  /// 14/400 — body for the admin role, and metadata everywhere.
  static TextStyle get bodyAdminMeta =>
      _font(fontSize: 14, fontWeight: FontWeight.w400);

  // --- The four small styles (RULING 3.2) ----------------------------------
  //
  // These were previously TWO rows — "12/500 overline, caption" and
  // "13/500 secondary label, timestamp" — and each row put two different jobs
  // on one weight. A LABEL needs presence; SUPPORTING TEXT should recede. One
  // weight cannot serve both, which is why the weight kept flip-flopping
  // between T2 and T3. Split into four. Twelve styles now, still three
  // weights — the constraint was ever only the weight count.
  //
  // Do not merge these back together in a "consistency" pass. A test asserts
  // both directions precisely to stop that.

  /// 13/600 — form field labels. Needs presence.
  static TextStyle get fieldLabel =>
      _font(fontSize: 13, fontWeight: FontWeight.w600);

  /// 13/500 — timestamps, e.g. "Marked at 8:52 AM". Should recede.
  static TextStyle get timestamp =>
      _font(fontSize: 13, fontWeight: FontWeight.w500);

  /// 12/600 — uppercase section labels. Needs presence.
  static TextStyle get overline =>
      _font(fontSize: 12, fontWeight: FontWeight.w600);

  /// 12/500 — supporting text, e.g. "86 of 121 school days". Should recede.
  /// The smallest permitted size.
  static TextStyle get caption =>
      _font(fontSize: 12, fontWeight: FontWeight.w500);

  /// The Overline primitive's tracked variant: 12/600 with 0.06em letter
  /// spacing, uppercase applied by the widget.
  static TextStyle get overlineTracked => overline.copyWith(
        letterSpacing: 12 * 0.06,
      );

  /// Initials inside an [Avatar], sized as a fraction of the circle so they
  /// fit at every avatar diameter.
  static TextStyle avatarInitials(double diameter) => GoogleFonts.plusJakartaSans(
        fontSize: diameter * _avatarInitialsRatio,
        fontWeight: FontWeight.w600,
        fontFeatures: tabularFigures,
      );

  static const double _avatarInitialsRatio = 0.4;

  /// Every style with its spec label, in order. For the token gallery.
  static List<(String, String, TextStyle)> get all => [
        ('parentStatusHero', '28/600 parent status hero', parentStatusHero),
        ('screenTitle', '24/600 screen title', screenTitle),
        ('sectionHeading', '20/500 section heading', sectionHeading),
        ('cardHeading', '18/500 card heading', cardHeading),
        ('personName', '16/500 person names, list primary', personName),
        (
          'bodyParentStudent',
          '16/400 body — parent, student',
          bodyParentStudent,
        ),
        ('bodyTeacher', '15/400 body — teacher', bodyTeacher),
        ('bodyAdminMeta', '14/400 body — admin, metadata', bodyAdminMeta),
        ('fieldLabel', '13/600 form field labels', fieldLabel),
        ('timestamp', '13/500 timestamps', timestamp),
        ('overline', '12/600 uppercase section labels', overline),
        ('caption', '12/500 supporting text', caption),
      ];

  /// Builds the [TextTheme] for a role, mapping the styles above onto
  /// Material's slots so `Theme.of(context).textTheme` works normally.
  ///
  /// `bodyLarge`/`bodyMedium`/`bodySmall` are anchored to [AppRole.baseBodySize]
  /// so the base body size varies per role shell (D-24) rather than globally.
  static TextTheme textThemeFor(AppRole role) {
    final base = role.baseBodySize;
    return TextTheme(
      displayLarge: parentStatusHero,
      headlineLarge: screenTitle,
      headlineMedium: sectionHeading,
      titleLarge: cardHeading,
      titleMedium: personName,
      bodyLarge: _font(fontSize: base, fontWeight: FontWeight.w400),
      bodyMedium: _font(fontSize: base, fontWeight: FontWeight.w400),
      bodySmall: bodyAdminMeta,
      labelMedium: fieldLabel,
      labelSmall: overline,
    );
  }
}

/// The four user roles. Each role shell sets its own base body size (D-24)
/// rather than the app setting one globally.
enum AppRole { parent, student, teacher, admin }

extension AppRoleTypography on AppRole {
  /// Base body size for this role's shell.
  ///
  /// This is the mechanism T5 applies per shell. T1 only exposes it — it does
  /// NOT build the shells or decide where they are mounted.
  double get baseBodySize => switch (this) {
        AppRole.parent => 16,
        AppRole.student => 16,
        AppRole.teacher => 15,
        AppRole.admin => 14,
      };

  /// Convenience: the [TextTheme] for this role.
  TextTheme get textTheme => AppTypography.textThemeFor(this);
}
