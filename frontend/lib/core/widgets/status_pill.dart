import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/sizing.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Every status a [StatusPill] can render.
///
/// Split into two families:
///  - ATTENDANCE (present..excused) render colour + letter + shape together.
///  - ENTITY (active..partial) render a label only.
enum AppStatus {
  // Attendance
  present,
  absent,
  late,
  leave,
  excused,
  // Entity
  active,
  inactive,
  complete,
  notStarted,
  partial;

  bool get isAttendance => index <= AppStatus.excused.index;
}

/// The shape half of D-21. Never rendered without its letter and colour.
enum StatusShape { filledCircle, openCircle, halfFilledCircle, dashedRing }

enum StatusPillSize { sm, md }

/// The most-reused component in the product: attendance marking, the admin
/// dashboard table, student profile counters, the calendar legend, the
/// students list, and CSV import.
///
/// D-21 IS LOAD-BEARING. Every attendance status carries colour, letter, AND
/// shape together. A variant that renders colour alone is a defect, not a
/// configuration — which is why [StatusShape] and the letter are derived from
/// [status] and are not constructor parameters. There is no way to build a
/// colour-only attendance pill with this API.
///
/// Reason: roughly 8% of men have some colour vision deficiency, and teachers
/// in Pakistani schools are frequently men. If present and absent differ only
/// by green and red, a 40-student roll is misread and the failure is silent.
class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.status,
    this.size = StatusPillSize.md,
    this.showLabel = true,
    super.key,
  }) : assert(
          // Written as an explicit disjunction rather than via `isAttendance`
          // so the whole expression is const-evaluable — that keeps
          // `const StatusPill(...)` legal AND makes the violation a
          // compile-time error for const call sites, not just a debug assert.
          showLabel ||
              (size == StatusPillSize.md &&
                  (status == AppStatus.present ||
                      status == AppStatus.absent ||
                      status == AppStatus.late ||
                      status == AppStatus.leave ||
                      status == AppStatus.excused)),
          'A pill with no label must carry a letter, and only a MEDIUM '
          'ATTENDANCE pill does (D-37). A small glyph is 12px and cannot hold '
          'a discriminable letter, and entity statuses have no letter at all — '
          'so showLabel: false there would leave colour as the only signal, '
          'which D-21 forbids.',
        );

  final AppStatus status;
  final StatusPillSize size;
  final bool showLabel;

  /// Whether this pill renders a letter. Only medium attendance pills do —
  /// the small glyph carries shape only (D-37).
  static bool letterFitsAt(StatusPillSize size) => size == StatusPillSize.md;

  /// The single-character (or two-character) marker shown inside the shape.
  /// Attendance statuses only — entity statuses have no letter.
  static String? letterFor(AppStatus status) => switch (status) {
        AppStatus.present => 'P',
        AppStatus.absent => 'A',
        AppStatus.late => '—',
        AppStatus.leave => 'Lv',
        AppStatus.excused => 'E',
        _ => null,
      };

  static StatusShape? shapeFor(AppStatus status) => switch (status) {
        AppStatus.present => StatusShape.filledCircle,
        AppStatus.absent => StatusShape.openCircle,
        AppStatus.late => StatusShape.halfFilledCircle,
        AppStatus.leave => StatusShape.filledCircle,
        AppStatus.excused => StatusShape.dashedRing,
        _ => null,
      };

  static String labelFor(AppStatus status) => switch (status) {
        AppStatus.present => 'Present',
        AppStatus.absent => 'Absent',
        AppStatus.late => 'Late',
        AppStatus.leave => 'Leave',
        AppStatus.excused => 'Excused',
        AppStatus.active => 'Active',
        AppStatus.inactive => 'Inactive',
        AppStatus.complete => 'Complete',
        AppStatus.notStarted => 'Not started',
        AppStatus.partial => 'Partial',
      };

  /// Colours for a status, resolved from the token set.
  ///
  /// Three roles, deliberately separate (T3 RULING 2):
  ///  - [bg]    the pill's tinted background.
  ///  - [text]  the LABEL colour. Uses the `…TextOnBg` tokens, which exist for
  ///            exactly this pairing — a dark foreground on a pale background.
  ///            T2 wrongly used [glyph] here, which measured 3.73:1 for Late
  ///            and 4.45:1 for Present in light mode, both under the 4.5:1 AA
  ///            floor.
  ///  - [glyph] the SHAPE fill. A shape is non-text, so it only needs 3:1, and
  ///            the saturated semantic colour is what makes the marker read at
  ///            a glance on a dense roll.
  static ({Color glyph, Color text, Color bg}) coloursFor(
    AppStatus status,
    SmartEmsTokens t,
  ) =>
      switch (status) {
        AppStatus.present =>
          (glyph: t.success, text: t.successTextOnBg, bg: t.successBg),
        AppStatus.absent =>
          (glyph: t.danger, text: t.dangerTextOnBg, bg: t.dangerBg),
        AppStatus.late =>
          (glyph: t.warning, text: t.warningTextOnBg, bg: t.warningBg),
        AppStatus.leave =>
          (glyph: t.info, text: t.infoTextOnBg, bg: t.infoBg),
        // No `…TextOnBg` token exists for the neutral pairing, and none is
        // needed: textSecondary on surfaceSunken already measures ~6:1.
        AppStatus.excused =>
          (glyph: t.textSecondary, text: t.textSecondary, bg: t.surfaceSunken),
        AppStatus.active =>
          (glyph: t.success, text: t.successTextOnBg, bg: t.successBg),
        AppStatus.inactive =>
          (glyph: t.textSecondary, text: t.textSecondary, bg: t.surfaceSunken),
        AppStatus.complete =>
          (glyph: t.success, text: t.successTextOnBg, bg: t.successBg),
        AppStatus.notStarted =>
          (glyph: t.textSecondary, text: t.textSecondary, bg: t.surfaceSunken),
        AppStatus.partial =>
          (glyph: t.warning, text: t.warningTextOnBg, bg: t.warningBg),
      };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colours = coloursFor(status, t);
    final isSm = size == StatusPillSize.sm;

    final textStyle = (isSm ? AppTypography.overline : AppTypography.fieldLabel)
        .copyWith(color: colours.text);

    final shape = shapeFor(status);
    // The small glyph carries shape only — 12px cannot hold a discriminable
    // letter (D-37), so the word does that job instead.
    final letter = letterFitsAt(size) ? letterFor(status) : null;

    return Semantics(
      label: labelFor(status),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isSm ? AppSpacing.space3 : AppSpacing.space4,
          vertical: isSm ? AppSpacing.space1 : AppSpacing.space2,
        ),
        decoration: BoxDecoration(
          color: colours.bg,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (shape != null)
              _StatusGlyph(
                shape: shape,
                letter: letter,
                colour: colours.glyph,
                // D-38: inverts with its background — white in light,
                // the status's own `…Bg` in dark.
                letterOnFill: t.onFilledGlyph(colours.bg),
                diameter:
                    isSm ? AppSizing.statusGlyphSm : AppSizing.statusGlyphMd,
              ),
            if (shape != null && showLabel)
              SizedBox(width: isSm ? AppSpacing.space2 : AppSpacing.space3),
            if (showLabel) Text(labelFor(status), style: textStyle),
          ],
        ),
      ),
    );
  }
}

/// The shape + letter glyph. Both are drawn together, never independently.
class _StatusGlyph extends StatelessWidget {
  const _StatusGlyph({
    required this.shape,
    required this.letter,
    required this.colour,
    required this.letterOnFill,
    required this.diameter,
  });

  final StatusShape shape;
  final String? letter;
  final Color colour;

  /// Letter colour when the shape is FILLED, i.e. when the letter sits on
  /// [colour] rather than on the pill background.
  ///
  /// This is the pill's own background token, which inverts correctly by mode:
  /// in light, a pale `…Bg` on a saturated fill; in dark, a very dark `…Bg` on
  /// a light fill. Using a fixed white here (as T2 did) is wrong in dark mode,
  /// where `success` is #6FCF8B and white on it is unreadable.
  final Color letterOnFill;

  final double diameter;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: diameter,
      height: diameter,
      child: CustomPaint(
        painter: _StatusShapePainter(shape: shape, colour: colour),
        child: letter == null
            ? null
            : Center(
                child: Text(
                  letter!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    // 13px on a 22px glyph (D-37) — an explicit size, above
                    // the 12px floor. The old ratio produced 9.28px here.
                    fontSize: AppSizing.statusGlyphLetterMd,
                    height: 1,
                    fontWeight: FontWeight.w600,
                    color: shape == StatusShape.filledCircle
                        ? letterOnFill
                        : colour,
                  ),
                ),
              ),
      ),
    );
  }
}

class _StatusShapePainter extends CustomPainter {
  const _StatusShapePainter({required this.shape, required this.colour});

  final StatusShape shape;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    switch (shape) {
      case StatusShape.filledCircle:
        canvas.drawCircle(centre, radius, Paint()..color = colour);

      case StatusShape.openCircle:
        canvas.drawCircle(
          centre,
          radius - AppSizing.borderThick / 2,
          Paint()
            ..color = colour
            ..style = PaintingStyle.stroke
            ..strokeWidth = AppSizing.borderThick,
        );

      case StatusShape.halfFilledCircle:
        // Ring, plus the lower half filled — reads as "partially there".
        canvas.drawCircle(
          centre,
          radius - AppSizing.borderThick / 2,
          Paint()
            ..color = colour
            ..style = PaintingStyle.stroke
            ..strokeWidth = AppSizing.borderThick,
        );
        canvas.drawArc(
          Rect.fromCircle(center: centre, radius: radius),
          0,
          math.pi,
          true,
          Paint()..color = colour,
        );

      case StatusShape.dashedRing:
        const dashes = 8;
        final sweep = (math.pi * 2) / (dashes * 2);
        final paint = Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = AppSizing.borderThick;
        for (var i = 0; i < dashes; i++) {
          canvas.drawArc(
            Rect.fromCircle(
              center: centre,
              radius: radius - AppSizing.borderThick / 2,
            ),
            i * sweep * 2,
            sweep,
            false,
            paint,
          );
        }
    }
  }

  @override
  bool shouldRepaint(_StatusShapePainter old) =>
      old.shape != shape || old.colour != colour;
}
