/// Fixed interactive sizes for Smart EMS.
///
/// Separate from [AppSpacing] on purpose: spacing is the gaps BETWEEN things,
/// sizing is how big an interactive thing itself is. They are different
/// scales with different constraints, and conflating them is how a 44px
/// touch target quietly becomes a 40px one.
///
/// [touchTargetMin] is not an arbitrary number — it is the Phase 0
/// accessibility NFR: minimum 44x44 on all interactive elements.
///
/// `tool/check_tokens.sh` rejects bare numeric `width:`/`height:` outside
/// `lib/core/theme/`, so consumers must reach for these names.
library;

abstract final class AppSizing {
  // --- Touch target (Phase 0 NFR) -----------------------------------------
  /// Minimum interactive dimension, both axes. Never render an interactive
  /// element smaller than this on mobile.
  static const double touchTargetMin = 44;

  // --- Button heights ------------------------------------------------------
  /// 36. Below [touchTargetMin], so it is a desktop/compact-web size only —
  /// on mobile, AppButton raises it to [touchTargetMin].
  static const double buttonSm = 36;
  static const double buttonMd = 44;
  static const double buttonLg = 48;

  // --- Field heights -------------------------------------------------------
  /// 40 on desktop, where pointer precision is higher.
  static const double fieldDesktop = 40;

  /// 48 on mobile — comfortably above [touchTargetMin].
  static const double fieldMobile = 48;

  // --- Avatar diameters ----------------------------------------------------
  // 24/32/40 coincide with the spacing scale, but 28 and 56 do not, so all
  // five live here rather than being split across two scales.
  static const double avatar24 = 24;
  static const double avatar28 = 28;
  static const double avatar32 = 32;
  static const double avatar40 = 40;
  static const double avatar56 = 56;

  // --- Border widths -------------------------------------------------------
  /// Default hairline border.
  static const double borderThin = 1;

  /// The heavier ring used by StatusPill's "open circle" (absent) shape.
  static const double borderThick = 2;

  // --- Status pill (D-37) --------------------------------------------------
  /// Small glyph. Carries SHAPE ONLY — at 12px no font size produces a
  /// discriminable letter, so the small pill has no letter and must show its
  /// word instead (`showLabel: true`, enforced by assertion in `StatusPill`).
  static const double statusGlyphSm = 12;

  /// Medium glyph. Raised from 16 to 22 by D-37 so its letter can be 13px and
  /// clear the 12px type floor.
  static const double statusGlyphMd = 22;

  /// Letter inside the medium glyph. An explicit size, not a ratio — the old
  /// ratio produced 6.96px and 9.28px, both under the floor, which is the
  /// D-21 failure D-37 fixes.
  static const double statusGlyphLetterMd = 13;

  // --- Progress bar --------------------------------------------------------
  /// Track and fill height.
  static const double progressBarHeight = 8;

  // --- Composites (T3) -----------------------------------------------------
  /// Minimum height of a [ListRow]. Comfortably above [touchTargetMin]
  /// because the WHOLE row is the tap target.
  static const double listRowMinHeight = 56;

  /// Fixed width of the time column in a PeriodRow. Shared by Teacher today
  /// and Student timetable so the two read as the same object.
  static const double periodTimeColumnWidth = 44;

  /// Below this viewport width the data table collapses to stacked cards.
  /// It NEVER scrolls horizontally.
  static const double tableCollapseBreakpoint = 600;

  /// Width of a StatCard skeleton block, matched to a typical StatCard so the
  /// row does not reflow when data arrives.
  static const double statCardSkeletonWidth = 140;

  /// Thickness of the Tabs underline indicator.
  static const double tabIndicatorHeight = 2;

  // --- Global states (T4) --------------------------------------------------
  /// The single static icon at the top of every state surface.
  static const double stateIconSize = 40;
}
