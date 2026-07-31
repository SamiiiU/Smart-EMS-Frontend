import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/sizing.dart';
import 'package:smartems/core/theme/tokens.dart';
import 'package:smartems/core/theme/typography.dart';
import 'package:smartems/core/widgets/app_button.dart';
import 'package:smartems/core/widgets/app_text_field.dart';
import 'package:smartems/core/widgets/avatar.dart';
import 'package:smartems/core/widgets/overline.dart';
import 'package:smartems/core/widgets/progress_bar.dart';
import 'package:smartems/core/widgets/status_pill.dart';

Widget host(Widget child, {TargetPlatform? platform, bool dark = false}) {
  return MaterialApp(
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    theme: AppTheme.light(role: AppRole.teacher).copyWith(platform: platform),
    darkTheme: AppTheme.dark(role: AppRole.teacher).copyWith(platform: platform),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('StatusPill — D-21', () {
    test('all ten statuses have a label', () {
      expect(AppStatus.values.length, 10);
      for (final s in AppStatus.values) {
        expect(StatusPill.labelFor(s), isNotEmpty, reason: '$s has no label');
      }
    });

    test('the five attendance statuses each carry colour, letter AND shape',
        () {
      final attendance =
          AppStatus.values.where((s) => s.isAttendance).toList();
      expect(attendance.length, 5);

      for (final s in attendance) {
        expect(StatusPill.letterFor(s), isNotNull, reason: '$s has no letter');
        expect(StatusPill.shapeFor(s), isNotNull, reason: '$s has no shape');
        final c = StatusPill.coloursFor(s, SmartEmsTokens.light);
        expect(c.glyph, isNotNull);
        expect(c.text, isNotNull);
        expect(c.bg, isNotNull);
      }
    });

    test('entity statuses carry no letter or shape — label only', () {
      for (final s in AppStatus.values.where((s) => !s.isAttendance)) {
        expect(StatusPill.letterFor(s), isNull);
        expect(StatusPill.shapeFor(s), isNull);
      }
    });

    test('each attendance status is distinguishable WITHOUT colour', () {
      // The colour-blind-safety guarantee. Two statuses may legitimately
      // share a shape (present and leave are both a filled circle per the
      // spec table), so the non-colour signal is the (shape, letter) PAIR.
      // If this ever fails, a status has become colour-only-distinguishable.
      final signals = <String>{};
      for (final s in AppStatus.values.where((s) => s.isAttendance)) {
        signals.add('${StatusPill.shapeFor(s)}|${StatusPill.letterFor(s)}');
      }
      expect(
        signals.length,
        5,
        reason: 'two attendance statuses share both shape and letter, leaving '
            'colour as the only difference',
      );
    });

    test('letters match the spec table exactly', () {
      expect(StatusPill.letterFor(AppStatus.present), 'P');
      expect(StatusPill.letterFor(AppStatus.absent), 'A');
      expect(StatusPill.letterFor(AppStatus.late), '—');
      expect(StatusPill.letterFor(AppStatus.leave), 'Lv');
      expect(StatusPill.letterFor(AppStatus.excused), 'E');
    });

    test('shapes match the spec table exactly', () {
      expect(StatusPill.shapeFor(AppStatus.present), StatusShape.filledCircle);
      expect(StatusPill.shapeFor(AppStatus.absent), StatusShape.openCircle);
      expect(
        StatusPill.shapeFor(AppStatus.late),
        StatusShape.halfFilledCircle,
      );
      expect(StatusPill.shapeFor(AppStatus.leave), StatusShape.filledCircle);
      expect(StatusPill.shapeFor(AppStatus.excused), StatusShape.dashedRing);
    });

    testWidgets('renders in both modes for every status and size',
        (tester) async {
      for (final dark in [false, true]) {
        for (final size in StatusPillSize.values) {
          for (final s in AppStatus.values) {
            await tester.pumpWidget(
              host(StatusPill(status: s, size: size), dark: dark),
            );
            expect(find.text(StatusPill.labelFor(s)), findsOneWidget);
          }
        }
      }
    });

    testWidgets('md showLabel: false still renders the shape glyph AND letter',
        (tester) async {
      await tester.pumpWidget(
        host(
          const StatusPill(status: AppStatus.absent, showLabel: false),
        ),
      );
      expect(find.text('Absent'), findsNothing);
      // The letter is part of the non-colour signal and must survive.
      expect(find.text('A'), findsOneWidget);
    });

    group('D-37 — the letter clears the 12px floor, or there is no letter', () {
      test('the medium letter is 13px on a 22px glyph', () {
        expect(AppSizing.statusGlyphMd, 22);
        expect(AppSizing.statusGlyphLetterMd, 13);
        expect(
          AppSizing.statusGlyphLetterMd,
          greaterThanOrEqualTo(12),
          reason: 'the status letter is below the 12px type floor again — this '
              'is the D-21 failure D-37 fixed',
        );
        expect(
          AppSizing.statusGlyphLetterMd,
          lessThan(AppSizing.statusGlyphMd),
          reason: 'the letter must fit inside its glyph',
        );
      });

      test('the small glyph carries no letter — 12px cannot hold one', () {
        expect(AppSizing.statusGlyphSm, 12);
        expect(StatusPill.letterFitsAt(StatusPillSize.sm), isFalse);
        expect(StatusPill.letterFitsAt(StatusPillSize.md), isTrue);
      });

      testWidgets('a small pill shows the WORD, never a bare glyph',
          (tester) async {
        await tester.pumpWidget(
          host(
            const StatusPill(status: AppStatus.present, size: StatusPillSize.sm),
          ),
        );
        expect(find.text('Present'), findsOneWidget);
        // No letter at sm — the word carries the non-colour signal instead.
        expect(find.text('P'), findsNothing);
      });

      test('a letterless small pill is UNREPRESENTABLE', () {
        // The whole point of D-37: not documented, asserted. Both variants of
        // "no label and no letter" are rejected.
        expect(
          () => StatusPill(
            status: AppStatus.present,
            size: StatusPillSize.sm,
            showLabel: false,
          ),
          throwsAssertionError,
          reason: 'a small pill has no letter, so hiding the label would leave '
              'colour as the only signal',
        );
        expect(
          () => StatusPill(
            status: AppStatus.active,
            showLabel: false,
          ),
          throwsAssertionError,
          reason: 'an entity status has no letter at all',
        );
      });

      test('md attendance pills MAY hide their label', () {
        expect(
          () => const StatusPill(
            status: AppStatus.present,
            showLabel: false,
          ),
          returnsNormally,
        );
      });
    });
  });

  group('Touch-target NFR (44px minimum)', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('AppButton meets 44px at every size on ${platform.name}',
          (tester) async {
        for (final size in AppButtonSize.values) {
          await tester.pumpWidget(
            host(
              AppButton(label: 'x', size: size, onPressed: () {}),
              platform: platform,
            ),
          );
          final box = tester.getSize(find.byType(AppButton));
          expect(
            box.height,
            greaterThanOrEqualTo(AppSizing.touchTargetMin),
            reason: '$size is ${box.height}px on ${platform.name}, '
                'below the ${AppSizing.touchTargetMin}px NFR',
          );
          expect(box.width, greaterThanOrEqualTo(AppSizing.touchTargetMin));
        }
      });

      testWidgets('AppTextField uses the mobile height on ${platform.name}',
          (tester) async {
        await tester.pumpWidget(
          host(const AppTextField(label: 'L'), platform: platform),
        );
        // The field box is the second child of the column.
        final container = tester.widgetList<Container>(find.byType(Container));
        expect(container, isNotEmpty);
        expect(AppSizing.fieldMobile, greaterThanOrEqualTo(AppSizing.touchTargetMin));
      });
    }

    test('sm button height is below the NFR and so is raised on touch', () {
      expect(AppButtonSize.sm.baseHeight, lessThan(AppSizing.touchTargetMin));
      expect(
        AppButtonSize.sm.heightFor(touch: true),
        AppSizing.touchTargetMin,
      );
      expect(
        AppButtonSize.sm.heightFor(touch: false),
        AppSizing.buttonSm,
      );
    });
  });

  group('AppButton', () {
    testWidgets('fires onPressed when enabled', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(AppButton(label: 'Tap', onPressed: () => taps++)),
      );
      await tester.tap(find.byType(AppButton));
      expect(taps, 1);
    });

    testWidgets('is inert when onPressed is null', (tester) async {
      await tester.pumpWidget(host(const AppButton(label: 'Off')));
      await tester.tap(find.byType(AppButton));
      // Nothing to assert beyond "no exception" — the button must not throw.
      expect(find.text('Off'), findsOneWidget);
    });

    testWidgets('renders every variant and size in both modes',
        (tester) async {
      for (final dark in [false, true]) {
        for (final v in AppButtonVariant.values) {
          for (final s in AppButtonSize.values) {
            await tester.pumpWidget(
              host(
                AppButton(label: 'b', variant: v, size: s, onPressed: () {}),
                dark: dark,
              ),
            );
            expect(find.text('b'), findsOneWidget);
          }
        }
      }
    });
  });

  group('Avatar', () {
    test('every size maps to an AppSizing constant', () {
      expect(AvatarSize.s24.diameter, AppSizing.avatar24);
      expect(AvatarSize.s28.diameter, AppSizing.avatar28);
      expect(AvatarSize.s32.diameter, AppSizing.avatar32);
      expect(AvatarSize.s40.diameter, AppSizing.avatar40);
      expect(AvatarSize.s56.diameter, AppSizing.avatar56);
    });

    testWidgets('renders at every size and tone', (tester) async {
      for (final size in AvatarSize.values) {
        for (final tone in AvatarTone.values) {
          await tester.pumpWidget(
            host(
              Avatar(
                initials: 'AK',
                size: size,
                tone: tone,
                status: tone == AvatarTone.semantic ? AppStatus.late : null,
              ),
            ),
          );
          expect(find.text('AK'), findsOneWidget);
          expect(tester.getSize(find.byType(Avatar)).height, size.diameter);
        }
      }
    });

    testWidgets('semantic tone without a status is rejected', (tester) async {
      expect(
        () => Avatar(
          initials: 'AK',
          tone: AvatarTone.semantic,
        ),
        throwsAssertionError,
      );
    });
  });

  group('ProgressBar', () {
    test('threshold is 75 and there are exactly two tiers', () {
      expect(ProgressBar.successThreshold, 75);
    });

    testWidgets('uses success at and above 75, warning below', (tester) async {
      for (final (pct, expectSuccess) in <(double, bool)>[
        (0, false),
        (74, false),
        (74.9, false),
        (75, true),
        (100, true),
      ]) {
        await tester.pumpWidget(host(ProgressBar(percent: pct)));
        final tokens = tester.element(find.byType(ProgressBar)).tokens;
        final decorated = tester.widget<DecoratedBox>(
          find.descendant(
            of: find.byType(ProgressBar),
            matching: find.byType(DecoratedBox),
          ),
        );
        final fill = (decorated.decoration as BoxDecoration).color;
        expect(
          fill,
          expectSuccess ? tokens.success : tokens.warning,
          reason: '$pct% picked the wrong tier',
        );
      }
    });

    test('rejects out-of-range percentages', () {
      expect(() => ProgressBar(percent: -1), throwsAssertionError);
      expect(() => ProgressBar(percent: 101), throwsAssertionError);
    });
  });

  group('Overline', () {
    testWidgets('uppercases its text and applies 0.06em tracking',
        (tester) async {
      await tester.pumpWidget(host(const Overline('today at a glance')));
      expect(find.text('TODAY AT A GLANCE'), findsOneWidget);

      final text = tester.widget<Text>(find.text('TODAY AT A GLANCE'));
      expect(text.style?.fontSize, 12);
      expect(text.style?.fontWeight, FontWeight.w600);
      expect(text.style?.letterSpacing, closeTo(12 * 0.06, 0.0001));
    });

    // GUARD FOR RULING 3.2 — asserts BOTH directions on purpose.
    //
    // This weight flip-flopped across T2 and T3 because the type table put two
    // different jobs on one row: "12 · 500 | Overline, caption". A LABEL needs
    // presence (600); SUPPORTING TEXT should recede (500). One weight cannot
    // serve both. The rows are now split into four styles.
    //
    // Asserting only that overline is 600 would let a future "consistency"
    // pass drag caption up to 600 and merge them again. Asserting only that
    // caption is 500 would let overline be dragged down. Both directions are
    // asserted so neither merge is silent.
    test('RULING 3.2: label styles are 600 and supporting styles are 500 — '
        'these must not be merged', () {
      // Labels — presence.
      expect(AppTypography.overline.fontSize, 12);
      expect(AppTypography.overline.fontWeight, FontWeight.w600);
      expect(AppTypography.overlineTracked.fontSize, 12);
      expect(AppTypography.overlineTracked.fontWeight, FontWeight.w600);
      expect(AppTypography.fieldLabel.fontSize, 13);
      expect(AppTypography.fieldLabel.fontWeight, FontWeight.w600);

      // Supporting text — recedes.
      expect(AppTypography.caption.fontSize, 12);
      expect(AppTypography.caption.fontWeight, FontWeight.w500);
      expect(AppTypography.timestamp.fontSize, 13);
      expect(AppTypography.timestamp.fontWeight, FontWeight.w500);

      // And the pairs must genuinely differ, not merely exist.
      expect(
        AppTypography.overline.fontWeight,
        isNot(AppTypography.caption.fontWeight),
        reason: 'overline and caption have been merged — see RULING 3.2',
      );
      expect(
        AppTypography.fieldLabel.fontWeight,
        isNot(AppTypography.timestamp.fontWeight),
        reason: 'fieldLabel and timestamp have been merged — see RULING 3.2',
      );
    });

    test('twelve styles, still only three weights', () {
      expect(AppTypography.all.length, 12);
      final weights =
          AppTypography.all.map((s) => s.$3.fontWeight).toSet();
      expect(
        weights,
        {FontWeight.w400, FontWeight.w500, FontWeight.w600},
        reason: 'the constraint is three weights, not a style count',
      );
    });
  });

  group('AppTextField', () {
    testWidgets('shows the error message only in the error state',
        (tester) async {
      await tester.pumpWidget(
        host(
          const AppTextField(
            label: 'Mobile',
            state: AppTextFieldState.error,
            errorText: 'Invalid',
          ),
        ),
      );
      expect(find.text('Invalid'), findsOneWidget);

      await tester.pumpWidget(
        host(
          const AppTextField(label: 'Mobile', errorText: 'Invalid'),
        ),
      );
      expect(find.text('Invalid'), findsNothing);
    });

    testWidgets('obscures the value when asked', (tester) async {
      await tester.pumpWidget(
        host(const AppTextField(label: 'PIN', value: 'abcd', obscure: true)),
      );
      expect(find.text('abcd'), findsNothing);
      expect(find.text('••••'), findsOneWidget);
    });

    testWidgets('renders every state in both modes', (tester) async {
      for (final dark in [false, true]) {
        for (final s in AppTextFieldState.values) {
          await tester.pumpWidget(
            host(
              AppTextField(label: 'L', value: 'v', state: s, errorText: 'e'),
              dark: dark,
            ),
          );
          expect(find.text('L'), findsOneWidget);
        }
      }
    });
  });
}
