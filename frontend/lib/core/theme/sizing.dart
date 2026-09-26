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

  /// Fixed width of the number field on a marks-entry row (T15).
  ///
  /// Fixed rather than flexible so a column of forty fields lines up — a
  /// ragged edge makes it much harder to scan for the one that is blank.
  /// Wide enough for "100.00" at a large text scale.
  static const double marksFieldWidth = 88;

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

  // --- Shell and navigation (T5) --------------------------------------------
  /// Below this viewport width: [BottomNav]. Same threshold [AppDataTable]
  /// already collapses at, so the shell's own breakpoint and the composite
  /// layer's breakpoint cannot drift apart into two different "mobile"
  /// definitions.
  static const double navBottomBreakpoint = tableCollapseBreakpoint;

  /// From [navBottomBreakpoint] up to this width: the compact
  /// [DesktopSidebar] (icon rail, no labels). At and above this width: the
  /// full sidebar with labels.
  static const double navRailBreakpoint = 1024;

  /// Height of [BottomNav]. Comfortably above [touchTargetMin] since it packs
  /// an indicator bar, icon and label into one column.
  static const double bottomNavHeight = 64;

  /// Width of the full (labelled) [DesktopSidebar].
  static const double sidebarWidth = 240;

  /// Width of the compact (icon-only) [DesktopSidebar], i.e. the nav rail.
  static const double sidebarCompactWidth = 72;

  /// Thickness of the sidebar's active-item indicator. A BORDER, never a
  /// fill — a fill reads as a button, a border reads as position.
  static const double sidebarActiveBorderWidth = 3;

  // --- Auth (T7) -------------------------------------------------------------
  /// Max width of the sign-in form. Unconstrained, the fields stretch to the
  /// full desktop viewport, which reads as a broken layout rather than a
  /// form.
  static const double authFormMaxWidth = 400;

  // --- Admin import (T10) ----------------------------------------------------
  /// Min height of the CSV paste area. A one-line field invites a one-line
  /// paste; a roster is tens of lines, and the box has to look like it
  /// expects them.
  static const double csvPasteMinHeight = 200;

  // --- Diary (T11) -----------------------------------------------------------
  /// Min height of a diary text area — room for a few lines of classwork or
  /// homework without the box looking like a single-line field.
  static const double diaryFieldMinHeight = 96;
}
