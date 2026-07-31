import 'dart:math' as math;
import 'dart:ui';

/// WCAG 2.1 contrast helpers.
///
/// Contrast has been checked with a throwaway script three times across
/// T1–T3, and each time it found a real failure that the widget tests and the
/// goldens both missed. It belongs in the suite, not in a script someone
/// remembers to run.
///
/// Floors:
///  - [aaText] 4.5:1 — normal-size text. Note that 12px and 16px are BOTH
///    "normal" under WCAG; "large" means 24px, or 18.66px bold.
///  - [aaNonText] 3.0:1 — icons, borders, indicators, shape glyphs.
const double aaText = 4.5;
const double aaNonText = 3.0;

/// Relative luminance per WCAG 2.1.
double relativeLuminance(Color c) {
  final argb = c.toARGB32();
  double channel(int shift) {
    final v = ((argb >> shift) & 0xFF) / 255.0;
    return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) as double;
  }

  return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0);
}

/// Contrast ratio between two opaque colours, 1.0..21.0.
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Formats a ratio the way the handoff tables do.
String ratio(Color fg, Color bg) =>
    '${contrastRatio(fg, bg).toStringAsFixed(2)}:1';
