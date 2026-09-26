import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/tokens.dart';

import 'support/contrast.dart';

/// Every colour pairing the product actually renders, asserted against its
/// WCAG floor in BOTH modes.
///
/// This exists because contrast failures are invisible to every other kind of
/// test: the widget tests pass, the goldens render, and nothing errors. Three
/// separate real failures were found by measuring across T1–T3 — the Overline
/// at 2.39:1, the StatusPill labels using the glyph colour, and the primary
/// ramp's dark-mode text — and each had already shipped through a green suite.
void main() {
  const light = SmartEmsTokens.light;
  const dark = SmartEmsTokens.dark;

  /// Asserts a pairing in both modes, reporting the measured value on failure.
  void bothModes(
    String label,
    Color Function(SmartEmsTokens) fg,
    Color Function(SmartEmsTokens) bg, {
    double floor = aaText,
  }) {
    for (final (mode, t) in [('light', light), ('dark', dark)]) {
      final r = contrastRatio(fg(t), bg(t));
      expect(
        r,
        greaterThanOrEqualTo(floor),
        reason: '$label in $mode is ${r.toStringAsFixed(2)}:1, '
            'below the $floor floor',
      );
    }
  }

  group('Text pairings — 4.5:1', () {
    test('body and label text on surfaces', () {
      bothModes('textPrimary on surface', (t) => t.textPrimary, (t) => t.surface);
      bothModes('textPrimary on page', (t) => t.textPrimary, (t) => t.page);
      bothModes('textSecondary on surface', (t) => t.textSecondary, (t) => t.surface);
      bothModes('textSecondary on page', (t) => t.textSecondary, (t) => t.page);
      bothModes(
        'textSecondary on surfaceSunken',
        (t) => t.textSecondary,
        (t) => t.surfaceSunken,
      );
    });

    test('Overline uses textSecondary, not textMuted (RULING 2.1)', () {
      // The regression this guards: textMuted on surface measured 2.39:1.
      bothModes('Overline on surface', (t) => t.textSecondary, (t) => t.surface);
      expect(
        contrastRatio(light.textMuted, light.surface),
        lessThan(aaText),
        reason: 'textMuted now passes on surface — if the palette changed, '
            'revisit RULING 2.1 rather than silently reverting Overline',
      );
    });

    test('primary action ramp (D-23, D-32, D-35)', () {
      bothModes(
        'filled button label',
        (t) => t.onPrimary,
        (t) => t.primaryAction,
      );
      bothModes(
        'filled button label, pressed',
        (t) => t.onPrimary,
        (t) => t.primaryPressed,
      );
      bothModes(
        'secondary/ghost label on surface',
        (t) => t.primaryTextOnSurface,
        (t) => t.surface,
      );
      bothModes(
        'secondary/ghost label on page',
        (t) => t.primaryTextOnSurface,
        (t) => t.page,
      );
    });

    test('StatusPill labels use the ...TextOnBg tokens (RULING 2.2)', () {
      bothModes('Present', (t) => t.successTextOnBg, (t) => t.successBg);
      bothModes('Absent', (t) => t.dangerTextOnBg, (t) => t.dangerBg);
      bothModes('Late', (t) => t.warningTextOnBg, (t) => t.warningBg);
      bothModes('Leave', (t) => t.infoTextOnBg, (t) => t.infoBg);
      bothModes('Excused', (t) => t.textSecondary, (t) => t.surfaceSunken);
      // T16 staff attendance. Info pairing, shared with Leave.
      bothModes('Half day', (t) => t.infoTextOnBg, (t) => t.infoBg);
      // T14 fee statuses. `Unpaid` is deliberately the neutral pairing, not
      // a danger one: an unpaid invoice is the normal state of a fee on the
      // day it is issued, and a freshly-generated class rendering as a wall
      // of red would train the admin to ignore the colour.
      bothModes('Unpaid', (t) => t.textSecondary, (t) => t.surfaceSunken);
      bothModes('Paid', (t) => t.successTextOnBg, (t) => t.successBg);
    });

    // D-38 — the filled-glyph letter uses onFilledGlyph, which INVERTS with
    // its background: white in light, the status's own `…Bg` in dark. This
    // closed the 4.45:1 light-mode shortfall that the T3 implementation had
    // (it used `…Bg` in both modes, and `#E8F3EA` is near-white but not white).
    // The previous known-exception range is gone — these now clear normally.
    test('D-38: the filled-glyph letter clears 4.5:1 in BOTH modes', () {
      for (final (mode, t) in [('light', light), ('dark', dark)]) {
        for (final (name, glyph, bg) in [
          ('Present', t.success, t.successBg),
          ('Leave', t.info, t.infoBg),
        ]) {
          final letter = t.onFilledGlyph(bg);
          final r = contrastRatio(letter, glyph);
          expect(
            r,
            greaterThanOrEqualTo(aaText),
            reason: '$name letter on its filled glyph in $mode is '
                '${r.toStringAsFixed(2)}:1',
          );
        }
      }
    });

    test('D-38: onFilledGlyph is white in light and the ...Bg in dark', () {
      expect(light.onFilledGlyph(light.successBg), const Color(0xFFFFFFFF));
      expect(dark.onFilledGlyph(dark.successBg), dark.successBg);

      // Measured: white on success #1B7F3B is 5.07:1. (RULING 5.2 stated
      // 4.72; the conclusion is right and the margin is larger than stated.
      // The same formula reproduces the ruling's other figure — the 4.45:1
      // it replaced — exactly, so 4.72 looks like the outlier.)
      expect(
        contrastRatio(light.onFilledGlyph(light.successBg), light.success),
        closeTo(5.07, 0.02),
      );

      // The value it replaced would still fail, so the fix cannot be quietly
      // reverted to "use ...Bg in both modes".
      expect(
        contrastRatio(light.successBg, light.success),
        closeTo(4.45, 0.01),
      );
      expect(contrastRatio(light.successBg, light.success), lessThan(aaText));

      // And white in DARK would be catastrophic (1.91:1) — which is exactly
      // why onFilledGlyph inverts instead of being pinned to white.
      expect(
        contrastRatio(const Color(0xFFFFFFFF), dark.success),
        lessThan(aaNonText),
      );
    });

    test('semantic messages on surfaces', () {
      bothModes('error message', (t) => t.danger, (t) => t.surface);
    });

    test('brand surfaces (RULING 3.3)', () {
      bothModes('brand hero title', (t) => t.onBrand, (t) => t.brandSurface);
      bothModes(
        'app bar / hero sub-text',
        (t) => t.onBrandMuted,
        (t) => t.brandSurface,
      );
      bothModes(
        'brand sub-text on the deeper brand surface',
        (t) => t.onBrandMuted,
        (t) => t.brandSurfaceDeep,
      );
    });

    test('InlineAlert and StatCard tinted text', () {
      bothModes('info', (t) => t.infoTextOnBg, (t) => t.infoBg);
      bothModes('warning', (t) => t.warningTextOnBg, (t) => t.warningBg);
      bothModes('danger', (t) => t.dangerTextOnBg, (t) => t.dangerBg);
      bothModes('success', (t) => t.successTextOnBg, (t) => t.successBg);
    });

    test('row tints do not break the text on top of them', () {
      bothModes('title on danger row', (t) => t.textPrimary,
          (t) => t.rowTintDanger);
      bothModes('title on warning row', (t) => t.textPrimary,
          (t) => t.rowTintWarning);
      bothModes('subtitle on danger row', (t) => t.textSecondary,
          (t) => t.rowTintDanger);
      bothModes('subtitle on warning row', (t) => t.textSecondary,
          (t) => t.rowTintWarning);
    });
  });

  group('Non-text pairings — 3:1', () {
    test('focused ring and Tabs indicator use primaryAccent (D-T3-05)', () {
      bothModes('focused ring on surface', (t) => t.primaryAccent,
          (t) => t.surface, floor: aaNonText);
      bothModes('Tabs indicator on page', (t) => t.primaryAccent,
          (t) => t.page, floor: aaNonText);
      bothModes('Tabs indicator on surface', (t) => t.primaryAccent,
          (t) => t.surface, floor: aaNonText);
    });

    test('secondary button border uses primaryAccent (D-35)', () {
      bothModes('secondary border on surface', (t) => t.primaryAccent,
          (t) => t.surface, floor: aaNonText);
      bothModes('secondary border on page', (t) => t.primaryAccent,
          (t) => t.page, floor: aaNonText);

      // The regression D-35 fixes: primaryAction as this border measured
      // 2.91:1 in dark, so the no-fill button had no perceivable edge.
      expect(
        contrastRatio(dark.primaryAction, dark.surface),
        lessThan(aaNonText),
        reason: 'primaryAction now clears 3:1 on the dark surface — if the '
            'palette changed, revisit D-35 rather than silently reverting '
            'the secondary border',
      );
    });

    test('StatusPill glyph shapes', () {
      bothModes('Present glyph', (t) => t.success, (t) => t.successBg,
          floor: aaNonText);
      bothModes('Absent glyph', (t) => t.danger, (t) => t.dangerBg,
          floor: aaNonText);
      bothModes('Late glyph', (t) => t.warning, (t) => t.warningBg,
          floor: aaNonText);
      bothModes('Leave glyph', (t) => t.info, (t) => t.infoBg,
          floor: aaNonText);
    });

    test('borders are discernible against their surfaces', () {
      bothModes('borderStrong on surface', (t) => t.borderStrong,
          (t) => t.surface, floor: 1.2);
      bothModes('border on surface', (t) => t.border, (t) => t.surface,
          floor: 1.05);
    });
  });

  group('D-36 — primaryTextOnSurface placement is constrained', () {
    test('valid on surface and page', () {
      for (final (mode, t) in [('light', light), ('dark', dark)]) {
        expect(contrastRatio(t.primaryTextOnSurface, t.surface),
            greaterThanOrEqualTo(aaText),
            reason: 'primaryTextOnSurface on surface failed in $mode');
        expect(contrastRatio(t.primaryTextOnSurface, t.page),
            greaterThanOrEqualTo(aaText),
            reason: 'primaryTextOnSurface on page failed in $mode');
      }
    });

    test('NOT valid on surfaceSunken — this is why the placement is banned',
        () {
      final r = contrastRatio(dark.primaryTextOnSurface, dark.surfaceSunken);
      expect(
        r,
        lessThan(aaText),
        reason: 'primaryTextOnSurface now clears 4.5:1 on surfaceSunken in '
            'dark (${r.toStringAsFixed(2)}:1). The palette must have changed — '
            'revisit D-36 deliberately rather than assuming the ban is stale.',
      );
    });

    test('textPrimary IS the correct choice on surfaceSunken', () {
      bothModes('textPrimary on surfaceSunken', (t) => t.textPrimary,
          (t) => t.surfaceSunken);
    });

    test('the guarded accessor rejects surfaceSunken', () {
      expect(
        () => dark.primaryTextOn(dark.surfaceSunken),
        throwsAssertionError,
      );
      expect(
        () => light.primaryTextOn(light.surfaceSunken),
        throwsAssertionError,
      );
    });

    test('the guarded accessor allows surface and page', () {
      expect(dark.primaryTextOn(dark.surface), dark.primaryTextOnSurface);
      expect(dark.primaryTextOn(dark.page), dark.primaryTextOnSurface);
      expect(light.primaryTextOn(light.surface), light.primaryTextOnSurface);
    });
  });

  group('The impossibility that D-32 rests on', () {
    test('no single colour can be primary-as-text at 4.5:1 in both modes', () {
      // Encoded so the reasoning survives: if the surfaces are ever
      // re-tuned, this either still holds or D-32 needs revisiting.
      final maxLightL = (relativeLuminance(light.surface) + 0.05) / aaText - 0.05;
      final minDarkL = aaText * (relativeLuminance(dark.surface) + 0.05) - 0.05;

      expect(
        maxLightL,
        lessThan(minDarkL),
        reason: 'the luminance windows now overlap, so a single '
            'primary-as-text colour is possible — D-32 can be simplified',
      );
    });

    test('but a single colour IS possible at the 3:1 non-text floor', () {
      final maxLightL =
          (relativeLuminance(light.surface) + 0.05) / aaNonText - 0.05;
      final minDarkL =
          aaNonText * (relativeLuminance(dark.surface) + 0.05) - 0.05;

      expect(maxLightL, greaterThan(minDarkL));
      // ...which is why primaryAccent can be mode-fixed and still pass.
      expect(light.primaryAccent, dark.primaryAccent);
    });
  });

  group('T5 — shell and navigation', () {
    // These reuse combinations already verified above under their own names;
    // named again here so the SHELL's specific usage is traceable and cannot
    // silently decouple from the underlying pair if either changes.

    test('SyncIndicator: synced (successBg/successTextOnBg)', () {
      bothModes('synced label', (t) => t.successTextOnBg, (t) => t.successBg);
      bothModes('synced icon', (t) => t.success, (t) => t.successBg,
          floor: aaNonText);
    });

    test('SyncIndicator: syncing (textSecondary/surfaceSunken)', () {
      bothModes(
          'syncing label', (t) => t.textSecondary, (t) => t.surfaceSunken);
      bothModes(
          'syncing icon', (t) => t.textSecondary, (t) => t.surfaceSunken,
          floor: aaNonText);
    });

    test('SyncIndicator: offline (warningBg/warningTextOnBg)', () {
      bothModes(
          'offline label', (t) => t.warningTextOnBg, (t) => t.warningBg);
      bothModes('offline icon', (t) => t.warning, (t) => t.warningBg,
          floor: aaNonText);
    });

    test('BottomNav selected label/icon (primaryTextOnSurface on surface)',
        () {
      bothModes('selected tab label', (t) => t.primaryTextOnSurface,
          (t) => t.surface);
    });

    test('BottomNav indicator bar (primaryAccent, non-text)', () {
      bothModes('indicator bar', (t) => t.primaryAccent, (t) => t.surface,
          floor: aaNonText);
    });

    test('BottomNav unselected label/icon (textSecondary on surface)', () {
      bothModes(
          'unselected tab', (t) => t.textSecondary, (t) => t.surface);
    });

    test('DesktopSidebar selected item label (textPrimary on primarySubtle)',
        () {
      // NOT primaryTextOnSurface: D-36 confines it to surface/page, and
      // primarySubtle is neither — that pairing measured 3.88:1 in dark,
      // caught here before it shipped. See the comment in desktop_sidebar.dart.
      bothModes(
          'sidebar selected label', (t) => t.textPrimary, (t) => t.primarySubtle);
      expect(
        contrastRatio(dark.primaryTextOnSurface, dark.primarySubtle),
        lessThan(aaText),
        reason: 'primaryTextOnSurface now clears primarySubtle in dark — if '
            'the palette changed, this is fine to use again; otherwise the '
            'guard above is still doing real work',
      );
    });

    test('DesktopSidebar active border (primaryAccent, non-text)', () {
      bothModes('sidebar active border', (t) => t.primaryAccent,
          (t) => t.surface, floor: aaNonText);
    });

    test('DesktopSidebar unselected item (textSecondary on surface)', () {
      bothModes('sidebar unselected label', (t) => t.textSecondary,
          (t) => t.surface);
    });

    test('MobileAppBar title (textPrimary on surface)', () {
      bothModes('app bar title', (t) => t.textPrimary, (t) => t.surface);
    });

    test('MobileAppBar unread dot is non-text and needs only 3:1', () {
      bothModes('unread dot', (t) => t.danger, (t) => t.surface,
          floor: aaNonText);
    });
  });

  // ==========================================================================
  // T8 — attendance marking.
  // ==========================================================================
  group('T8 — attendance and today', () {
    test('selected status choice label (textPrimary on primarySubtle)', () {
      // textPrimary, NOT primaryTextOnSurface: D-36 confines that token to
      // `surface`/`page`, and primarySubtle is neither — the same trap the
      // DesktopSidebar hit in T5.
      bothModes('status choice selected', (t) => t.textPrimary,
          (t) => t.primarySubtle);
    });

    test('unselected status choice label (textSecondary on surface)', () {
      bothModes('status choice unselected', (t) => t.textSecondary,
          (t) => t.surface);
    });

    test('SELECTED status choice border clears the non-text floor', () {
      // Only the selected border is load-bearing: it is what distinguishes
      // the chosen status. The idle border is deliberately NOT asserted at
      // 3:1 — `border` measures ~1.28:1 and is used that way for every card
      // and sidebar in the app. It is decorative refinement; the chip is
      // identified by its own text label, so WCAG 1.4.11 does not bind it.
      // Asserting 3:1 there would not find a bug, it would just force a
      // design change the spec never asked for.
      bothModes('status choice selected border', (t) => t.primaryAccent,
          (t) => t.surface, floor: aaNonText);
    });

    test('roster student name (textPrimary on page)', () {
      bothModes('roster name', (t) => t.textPrimary, (t) => t.page);
    });

    test('Today current-period card: heading and meta on primarySubtle', () {
      bothModes('today current heading', (t) => t.textPrimary,
          (t) => t.primarySubtle);
      bothModes('today current meta', (t) => t.textSecondary,
          (t) => t.primarySubtle);
    });

    test('Today non-current period card on surface', () {
      bothModes('today heading', (t) => t.textPrimary, (t) => t.surface);
      bothModes('today meta', (t) => t.textSecondary, (t) => t.surface);
    });

    test('Today current-period left border is non-text', () {
      bothModes('today current border', (t) => t.primaryAccent,
          (t) => t.page, floor: aaNonText);
    });
  });

  // ==========================================================================
  // T9 — parent landing and child attendance.
  // ==========================================================================
  group('T9 — parent screens', () {
    test('selected child chip label (textPrimary on primarySubtle)', () {
      // Same D-36 trap as the sidebar and the status chips: primarySubtle is
      // neither `surface` nor `page`, so primaryTextOnSurface is banned here.
      bothModes('child chip selected', (t) => t.textPrimary,
          (t) => t.primarySubtle);
    });

    test('unselected child chip label (textSecondary on surface)', () {
      bothModes('child chip unselected', (t) => t.textSecondary,
          (t) => t.surface);
    });

    test('selected child chip border clears the non-text floor', () {
      bothModes('child chip selected border', (t) => t.primaryAccent,
          (t) => t.surface, floor: aaNonText);
    });

    test('child name and class on the today card (surface)', () {
      bothModes('child name', (t) => t.textPrimary, (t) => t.surface);
      bothModes('child class', (t) => t.textSecondary, (t) => t.surface);
    });

    test('"not marked yet" copy and its icon on surface', () {
      // This message replaces a StatusPill, so it carries the whole answer
      // and must be as legible as the pill would have been.
      bothModes('not-marked copy', (t) => t.textSecondary, (t) => t.surface);
    });

    test('attendance day row: date on surface, over the page', () {
      bothModes('day row date', (t) => t.textPrimary, (t) => t.surface);
      bothModes('day row card border', (t) => t.border, (t) => t.page,
          floor: 1);
    });

    test('history link chevron is non-text', () {
      bothModes('history chevron', (t) => t.textSecondary, (t) => t.surface,
          floor: aaNonText);
    });
  });

  group('T11 — diary and student surfaces', () {
    test('diary field label (textSecondary) and text (textPrimary)', () {
      bothModes('diary field label on page', (t) => t.textSecondary,
          (t) => t.page);
      bothModes('diary text on surface', (t) => t.textPrimary,
          (t) => t.surface);
      bothModes('diary text while saving (surfaceSunken)',
          (t) => t.textPrimary, (t) => t.surfaceSunken);
    });

    test('"not available yet" state: info icon on the page', () {
      // Same pairing UnlinkedProfileState has used since T4 without ever
      // being asserted. A 40px glyph — non-text, so 3:1.
      bothModes('info state icon on page', (t) => t.info, (t) => t.page,
          floor: aaNonText);
      bothModes('state title on page', (t) => t.textPrimary, (t) => t.page);
      bothModes('state message on page', (t) => t.textSecondary,
          (t) => t.page);
    });
  });
}
