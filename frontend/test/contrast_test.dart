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
}
