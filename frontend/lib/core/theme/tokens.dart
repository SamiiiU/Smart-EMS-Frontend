import 'package:flutter/material.dart';

/// Semantic colour tokens for Smart EMS.
///
/// This file is one of the only places in the codebase permitted to contain
/// raw colour literals (`tool/check_tokens.sh` exempts `lib/core/theme/`).
/// Everywhere else, colours come from `Theme.of(context).extension<
/// SmartEmsTokens>()`.
///
/// Names are semantic: a screen asks for `surface`, never for `white`.
@immutable
class SmartEmsTokens extends ThemeExtension<SmartEmsTokens> {
  const SmartEmsTokens({
    required this.page,
    required this.surface,
    required this.surfaceSunken,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textDisabled,
    required this.primaryAction,
    required this.primaryPressed,
    required this.primaryAccent,
    required this.primaryTextOnSurface,
    required this.primarySubtle,
    required this.onPrimary,
    required this.brandSurface,
    required this.brandSurfaceDeep,
    required this.onBrand,
    required this.onBrandMuted,
    required this.success,
    required this.successBg,
    required this.warning,
    required this.warningBg,
    required this.danger,
    required this.dangerBg,
    required this.info,
    required this.infoBg,
    required this.successTextOnBg,
    required this.warningTextOnBg,
    required this.dangerTextOnBg,
    required this.infoTextOnBg,
    required this.rowTintDanger,
    required this.rowTintWarning,
    required this.shadowOverlay,
    required this.brightness,
  });

  // --- Surface -------------------------------------------------------------
  final Color page;
  final Color surface;
  final Color surfaceSunken;
  final Color border;
  final Color borderStrong;

  // --- Text ----------------------------------------------------------------
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textDisabled;

  // --- Action --------------------------------------------------------------
  /// Identical in light and dark (D-23).
  ///
  /// RULING 2 (T3) shifted this ramp one step darker — `primaryAction` was
  /// `#158A76` and `primaryPressed` was `#0F7462`. Reason: white on `#158A76`
  /// measured 4.26:1, and a 16/500 button label is not "large" text under
  /// WCAG, so it missed the 4.5:1 AA floor. The shift also fixes the
  /// secondary and ghost labels, which render this colour as text.
  final Color primaryAction;
  final Color primaryPressed;
  final Color primarySubtle;

  /// `#158A76` — the previous `primaryAction`, retained by RULING 2 for
  /// NON-TEXT use only: accents, borders, indicators. Non-text contrast needs
  /// 3:1, which it passes comfortably.
  ///
  /// Never put text on this and never use it AS text. If you need a
  /// foreground colour, use [primaryTextOnSurface].
  final Color primaryAccent;

  /// Primary colour used AS TEXT sitting on a surface — the secondary and
  /// ghost button labels, and any future primary-coloured text.
  ///
  /// This is the ONE part of the primary ramp that remaps between modes, and
  /// that is D-23's own scope rule rather than an exception to it: D-23 fixes
  /// the primary action AS A FILL (`primaryAction` + `onPrimary`, 5.68:1 in
  /// both modes). Anything sitting ON a surface remaps, exactly as
  /// `successTextOnBg` remaps. See D-32.
  ///
  /// light `#0F7462` (L=0.1348) -> 5.68:1 on `#FFFFFF`
  /// dark  `#3F9E8D` (L=0.2750) -> 5.17:1 on `#1F1F1C`
  ///
  /// `#3F9E8D` is primary 400 and measures only 3.24:1 on white, which is
  /// why it is dark-only. No single colour can clear 4.5:1 against both
  /// surfaces — the required luminance windows do not overlap.
  ///
  /// VALID ON [surface] AND [page] ONLY (D-36). On [surfaceSunken] — the table
  /// header band and the break-row fill — it measures 4.39:1 in dark, a 2.4%
  /// shortfall. Use [textPrimary] there instead. Reach for
  /// [primaryTextOn] when the background is known and you want that
  /// constraint enforced rather than remembered.
  final Color primaryTextOnSurface;

  /// Guarded accessor for [primaryTextOnSurface] (D-36).
  ///
  /// Returns the token, but asserts that [background] is a surface the token
  /// actually clears 4.5:1 against. `surfaceSunken` is the trap this exists to
  /// catch: primary-coloured text on a table header band silently misses the
  /// floor in dark mode.
  ///
  /// Use this wherever the background is known. `AppButton`'s secondary and
  /// ghost variants have no fill of their own and so cannot know their
  /// background — they use [primaryTextOnSurface] directly and are covered by
  /// the contrast tests instead.
  Color primaryTextOn(Color background) {
    assert(
      background == surface || background == page,
      'primaryTextOnSurface is valid on surface and page only (D-36). '
      'On surfaceSunken it measures 4.39:1 in dark, below the 4.5:1 floor — '
      'use textPrimary there instead.',
    );
    return primaryTextOnSurface;
  }

  /// Stays a token despite being equal in both modes.
  final Color onPrimary;

  /// Which theme these tokens are. Needed by [onFilledGlyph], which inverts
  /// rather than being pinned to either end.
  final Brightness brightness;

  /// The letter inside a FILLED status glyph, given the pill's `…Bg` (D-38).
  ///
  /// Inverts with its background rather than being pinned:
  ///  - light -> `#FFFFFF`. White on `success` `#1B7F3B` measures 4.72:1 and
  ///    clears the floor. The T3 implementation used the pill's `…Bg`, which is
  ///    near-white but not white, and came to 4.45:1 — right in principle,
  ///    1.1% short in practice.
  ///  - dark  -> the status's own `…Bg`, keeping the T3 behaviour that fixed
  ///    the original hardcoded-white bug (white on dark-mode `success`
  ///    `#6FCF8B` is unreadable).
  ///
  /// Same shape as [onPrimary]: a foreground that follows its background.
  ///
  /// Rejected alternative: darkening the success ramp. It would ripple through
  /// every success pairing already passing at 9.75:1 to fix one glyph.
  Color onFilledGlyph(Color statusBg) =>
      brightness == Brightness.light ? const Color(0xFFFFFFFF) : statusBg;

  // --- Brand ---------------------------------------------------------------
  // Decorative surfaces only. No actions ever sit on these.
  final Color brandSurface;
  final Color brandSurfaceDeep;
  final Color onBrand;
  final Color onBrandMuted;

  // --- Semantic ------------------------------------------------------------
  final Color success;
  final Color successBg;
  final Color warning;
  final Color warningBg;
  final Color danger;
  final Color dangerBg;
  final Color info;
  final Color infoBg;
  final Color successTextOnBg;
  final Color warningTextOnBg;
  final Color dangerTextOnBg;
  final Color infoTextOnBg;

  // --- Row tint ------------------------------------------------------------
  final Color rowTintDanger;
  final Color rowTintWarning;

  // --- Elevation (D-28) ----------------------------------------------------
  /// The ONLY shadow token in the system. Borders carry structure everywhere
  /// else — cards, tables, panels, rows. Shadow is reserved for genuine
  /// overlays: bottom sheets, dropdowns, dialogs.
  ///
  /// Rationale: shadows cost render time on low-end Android, read poorly at
  /// small sizes, and are nearly invisible against a near-black dark surface —
  /// a dark theme built on shadows loses its structure.
  ///
  /// PROVENANCE: these values were DERIVED, not specified. The design spec
  /// required this token to exist ("expose exactly one shadow token") but gave
  /// no value for it, unlike all 31 colours above which are spec-exact. The
  /// light/dark values below were chosen during T1 and approved as-is in
  /// review — dark is deeper because a near-black surface swallows a soft
  /// shadow. See DECISIONS.md D-T1-01. Treat any future change here as a
  /// design decision, not a tweak.
  final List<BoxShadow> shadowOverlay;

  /// The absence of a fill, not a design token. Named here so widgets never
  /// reach for `Colors.transparent` or a raw literal — both of which the
  /// token checker correctly rejects outside this directory.
  static const Color transparent = Color(0x00000000);

  static const SmartEmsTokens light = SmartEmsTokens(
    page: Color(0xFFFAFAF8),
    surface: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFF2F2EE),
    border: Color(0xFFE4E4DE),
    borderStrong: Color(0xFFCFCFC7),
    textPrimary: Color(0xFF171715),
    textSecondary: Color(0xFF5C5C56),
    textMuted: Color(0xFFA8A8A0),
    textDisabled: Color(0xFFCFCFC7),
    primaryAction: Color(0xFF0F7462),
    primaryPressed: Color(0xFF0A5D4E),
    primaryAccent: Color(0xFF158A76),
    primaryTextOnSurface: Color(0xFF0F7462),
    primarySubtle: Color(0xFFE6F2EF),
    onPrimary: Color(0xFFFFFFFF),
    brandSurface: Color(0xFF0A5D4E),
    brandSurfaceDeep: Color(0xFF06463A),
    onBrand: Color(0xFFFFFFFF),
    onBrandMuted: Color(0xFFC0DFD8),
    success: Color(0xFF1B7F3B),
    successBg: Color(0xFFE8F3EA),
    warning: Color(0xFFB26B00),
    warningBg: Color(0xFFFBF0DE),
    danger: Color(0xFFB3261E),
    dangerBg: Color(0xFFFBEAE9),
    info: Color(0xFF1B5E9E),
    infoBg: Color(0xFFE7F0F8),
    successTextOnBg: Color(0xFF0E4520),
    warningTextOnBg: Color(0xFF5E3800),
    dangerTextOnBg: Color(0xFF5E1410),
    infoTextOnBg: Color(0xFF0E3253),
    rowTintDanger: Color(0xFFFEF9F9),
    rowTintWarning: Color(0xFFFFFCF6),
    shadowOverlay: [
      BoxShadow(
        color: Color(0x1F171715),
        blurRadius: 16,
        offset: Offset(0, 4),
      ),
    ],
    brightness: Brightness.light,
  );

  static const SmartEmsTokens dark = SmartEmsTokens(
    page: Color(0xFF191916),
    surface: Color(0xFF1F1F1C),
    surfaceSunken: Color(0xFF2B2B28),
    border: Color(0xFF2B2B28),
    borderStrong: Color(0xFF33332F),
    textPrimary: Color(0xFFFAFAF8),
    textSecondary: Color(0xFFA8A8A0),
    textMuted: Color(0xFF7C7C74),
    textDisabled: Color(0xFF5C5C56),
    primaryAction: Color(0xFF0F7462),
    primaryPressed: Color(0xFF0A5D4E),
    primaryAccent: Color(0xFF158A76),
    primaryTextOnSurface: Color(0xFF3F9E8D),
    primarySubtle: Color(0xFF0F3A31),
    onPrimary: Color(0xFFFFFFFF),
    brandSurface: Color(0xFF0A5D4E),
    brandSurfaceDeep: Color(0xFF06463A),
    onBrand: Color(0xFFFFFFFF),
    onBrandMuted: Color(0xFFC0DFD8),
    success: Color(0xFF6FCF8B),
    successBg: Color(0xFF12301C),
    warning: Color(0xFFE0A24A),
    warningBg: Color(0xFF331F04),
    danger: Color(0xFFF09490),
    dangerBg: Color(0xFF351310),
    info: Color(0xFF7FB3E0),
    infoBg: Color(0xFF12283D),
    successTextOnBg: Color(0xFF8FDDA5),
    warningTextOnBg: Color(0xFFEBBE7A),
    dangerTextOnBg: Color(0xFFF5B3B0),
    infoTextOnBg: Color(0xFFA8CBEA),
    rowTintDanger: Color(0xFF241412),
    rowTintWarning: Color(0xFF231C11),
    shadowOverlay: [
      BoxShadow(
        color: Color(0x66000000),
        blurRadius: 16,
        offset: Offset(0, 4),
      ),
    ],
    brightness: Brightness.dark,
  );

  /// Every colour token, grouped and labelled with its token name.
  ///
  /// The token gallery renders from this, so a token added above but not
  /// listed here is visibly missing from the gallery.
  List<(String, List<(String, Color)>)> get colourGroups => [
        ('Surface', [
          ('page', page),
          ('surface', surface),
          ('surfaceSunken', surfaceSunken),
          ('border', border),
          ('borderStrong', borderStrong),
        ]),
        ('Text', [
          ('textPrimary', textPrimary),
          ('textSecondary', textSecondary),
          ('textMuted', textMuted),
          ('textDisabled', textDisabled),
        ]),
        ('Action', [
          ('primaryAction', primaryAction),
          ('primaryPressed', primaryPressed),
          ('primaryAccent', primaryAccent),
          ('primaryTextOnSurface', primaryTextOnSurface),
          ('primarySubtle', primarySubtle),
          ('onPrimary', onPrimary),
        ]),
        ('Brand — decorative surfaces only, no actions ever sit on these', [
          ('brandSurface', brandSurface),
          ('brandSurfaceDeep', brandSurfaceDeep),
          ('onBrand', onBrand),
          ('onBrandMuted', onBrandMuted),
        ]),
        ('Semantic', [
          ('success', success),
          ('successBg', successBg),
          ('warning', warning),
          ('warningBg', warningBg),
          ('danger', danger),
          ('dangerBg', dangerBg),
          ('info', info),
          ('infoBg', infoBg),
          ('successTextOnBg', successTextOnBg),
          ('warningTextOnBg', warningTextOnBg),
          ('dangerTextOnBg', dangerTextOnBg),
          ('infoTextOnBg', infoTextOnBg),
        ]),
        ('Row tint', [
          ('rowTintDanger', rowTintDanger),
          ('rowTintWarning', rowTintWarning),
        ]),
      ];

  @override
  SmartEmsTokens copyWith({
    Color? page,
    Color? surface,
    Color? surfaceSunken,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textDisabled,
    Color? primaryAction,
    Color? primaryPressed,
    Color? primaryAccent,
    Color? primaryTextOnSurface,
    Color? primarySubtle,
    Color? onPrimary,
    Color? brandSurface,
    Color? brandSurfaceDeep,
    Color? onBrand,
    Color? onBrandMuted,
    Color? success,
    Color? successBg,
    Color? warning,
    Color? warningBg,
    Color? danger,
    Color? dangerBg,
    Color? info,
    Color? infoBg,
    Color? successTextOnBg,
    Color? warningTextOnBg,
    Color? dangerTextOnBg,
    Color? infoTextOnBg,
    Color? rowTintDanger,
    Color? rowTintWarning,
    List<BoxShadow>? shadowOverlay,
    Brightness? brightness,
  }) {
    return SmartEmsTokens(
      page: page ?? this.page,
      surface: surface ?? this.surface,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textDisabled: textDisabled ?? this.textDisabled,
      primaryAction: primaryAction ?? this.primaryAction,
      primaryPressed: primaryPressed ?? this.primaryPressed,
      primaryAccent: primaryAccent ?? this.primaryAccent,
      primaryTextOnSurface: primaryTextOnSurface ?? this.primaryTextOnSurface,
      primarySubtle: primarySubtle ?? this.primarySubtle,
      onPrimary: onPrimary ?? this.onPrimary,
      brandSurface: brandSurface ?? this.brandSurface,
      brandSurfaceDeep: brandSurfaceDeep ?? this.brandSurfaceDeep,
      onBrand: onBrand ?? this.onBrand,
      onBrandMuted: onBrandMuted ?? this.onBrandMuted,
      success: success ?? this.success,
      successBg: successBg ?? this.successBg,
      warning: warning ?? this.warning,
      warningBg: warningBg ?? this.warningBg,
      danger: danger ?? this.danger,
      dangerBg: dangerBg ?? this.dangerBg,
      info: info ?? this.info,
      infoBg: infoBg ?? this.infoBg,
      successTextOnBg: successTextOnBg ?? this.successTextOnBg,
      warningTextOnBg: warningTextOnBg ?? this.warningTextOnBg,
      dangerTextOnBg: dangerTextOnBg ?? this.dangerTextOnBg,
      infoTextOnBg: infoTextOnBg ?? this.infoTextOnBg,
      rowTintDanger: rowTintDanger ?? this.rowTintDanger,
      rowTintWarning: rowTintWarning ?? this.rowTintWarning,
      shadowOverlay: shadowOverlay ?? this.shadowOverlay,
      brightness: brightness ?? this.brightness,
    );
  }

  @override
  SmartEmsTokens lerp(ThemeExtension<SmartEmsTokens>? other, double t) {
    if (other is! SmartEmsTokens) return this;
    return SmartEmsTokens(
      page: Color.lerp(page, other.page, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      primaryAction: Color.lerp(primaryAction, other.primaryAction, t)!,
      primaryPressed: Color.lerp(primaryPressed, other.primaryPressed, t)!,
      primaryAccent: Color.lerp(primaryAccent, other.primaryAccent, t)!,
      primaryTextOnSurface:
          Color.lerp(primaryTextOnSurface, other.primaryTextOnSurface, t)!,
      primarySubtle: Color.lerp(primarySubtle, other.primarySubtle, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      brandSurface: Color.lerp(brandSurface, other.brandSurface, t)!,
      brandSurfaceDeep: Color.lerp(brandSurfaceDeep, other.brandSurfaceDeep, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
      onBrandMuted: Color.lerp(onBrandMuted, other.onBrandMuted, t)!,
      success: Color.lerp(success, other.success, t)!,
      successBg: Color.lerp(successBg, other.successBg, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningBg: Color.lerp(warningBg, other.warningBg, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerBg: Color.lerp(dangerBg, other.dangerBg, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoBg: Color.lerp(infoBg, other.infoBg, t)!,
      successTextOnBg: Color.lerp(successTextOnBg, other.successTextOnBg, t)!,
      warningTextOnBg: Color.lerp(warningTextOnBg, other.warningTextOnBg, t)!,
      dangerTextOnBg: Color.lerp(dangerTextOnBg, other.dangerTextOnBg, t)!,
      infoTextOnBg: Color.lerp(infoTextOnBg, other.infoTextOnBg, t)!,
      rowTintDanger: Color.lerp(rowTintDanger, other.rowTintDanger, t)!,
      rowTintWarning: Color.lerp(rowTintWarning, other.rowTintWarning, t)!,
      shadowOverlay:
          BoxShadow.lerpList(shadowOverlay, other.shadowOverlay, t)!,
      // Brightness is discrete; snap at the midpoint.
      brightness: t < 0.5 ? brightness : other.brightness,
    );
  }
}
