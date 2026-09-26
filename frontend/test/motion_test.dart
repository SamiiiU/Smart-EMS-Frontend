import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/motion.dart';
import 'package:smartems/core/widgets/motion_reveal.dart';

/// Motion is governed by decisions that were made with the visuals and are
/// easy to erode one convenient exception at a time. These tests pin the
/// parts of D-03/D-04/D-05/D-29 that a future change could quietly break.

Widget _host(Widget child, {bool reducedMotion = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: Scaffold(body: child),
      ),
    );

/// The opacity actually being applied to [finder]'s subtree.
double _opacityOf(WidgetTester tester, Finder finder) {
  final opacities = tester
      .widgetList<Opacity>(find.descendant(
        of: finder,
        matching: find.byType(Opacity),
      ))
      .toList();
  return opacities.isEmpty ? 1 : opacities.first.opacity;
}

void main() {
  group('D-29 durations are the ones that were decided', () {
    test('every expressive moment matches the spec verbatim', () {
      // Transcribed from D-29. If one of these changes, the decision
      // changed — which is a conversation, not a tweak.
      expect(AppMotion.loginEntry.inMilliseconds, 400);
      expect(AppMotion.heroReveal.inMilliseconds, 300);
      expect(AppMotion.checklistTick.inMilliseconds, 300);
      expect(AppMotion.kpiReveal.inMilliseconds, 250);
      expect(AppMotion.confirmation.inMilliseconds, 250);
      expect(AppMotion.emptyStateEntrance.inMilliseconds, 250);
      expect(AppMotion.sectionReveal.inMilliseconds, 200);
      expect(AppMotion.staggerStep.inMilliseconds, 60);
      expect(AppMotion.heroScaleFrom, 0.97);
    });

    test('the functional band stays inside D-04’s 120–180ms', () {
      // High-frequency screens: a 300ms transition on a row tapped 40 times
      // is 12 seconds of a 90-second task.
      expect(AppMotion.fast.inMilliseconds, 120);
      expect(AppMotion.functional.inMilliseconds, 180);
      expect(AppMotion.functional.inMilliseconds, lessThanOrEqualTo(180));
    });

    test('the overshoot curve exists and is used in exactly one place', () {
      // `expressiveSettle` overshoots. D-29 allows it for submit
      // confirmation ONLY — everywhere else it would make the product bouncy.
      final source =
          File('lib/core/widgets/motion_reveal.dart').readAsStringSync();
      // Comments discuss it by name; only real uses count.
      final code = source
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      final uses = 'expressiveSettle'.allMatches(code).length;
      expect(
        uses,
        1,
        reason: 'expressiveSettle overshoots. D-29 allows it for submit '
            'confirmation only — $uses uses means it has started to spread.',
      );
      expect(source.contains('class MotionConfirm'), isTrue);
    });

    test('a stagger is capped so a long list stops arriving', () {
      // Uncapped, item 40 would start 2.4s in and the screen would look
      // broken rather than considered.
      expect(AppMotion.staggerFor(0), Duration.zero);
      expect(AppMotion.staggerFor(3).inMilliseconds, 180);
      expect(
        AppMotion.staggerFor(40).inMilliseconds,
        AppMotion.staggerStep.inMilliseconds * AppMotion.maxStaggeredItems,
      );
    });
  });

  group('D-05 — compositor only', () {
    test('the reveal animates opacity and transform, and nothing else', () {
      final source =
          File('lib/core/widgets/motion_reveal.dart').readAsStringSync();

      // width/height/top/left force a layout pass every frame and are
      // visibly janky on the budget Android this product targets.
      for (final banned in [
        'AnimatedSize',
        'AnimatedContainer',
        'AnimatedPadding',
        'AnimatedPositioned',
      ]) {
        expect(
          source.contains(banned),
          isFalse,
          reason: '$banned animates layout, which D-05 forbids',
        );
      }
      expect(source.contains('Opacity('), isTrue);
      expect(source.contains('Transform.'), isTrue);
    });
  });

  group('MotionReveal', () {
    testWidgets('fades its child in and ends fully opaque', (tester) async {
      await tester.pumpWidget(_host(const MotionReveal(child: Text('hello'))));

      // First frame: present in the tree, not yet visible.
      expect(find.text('hello'), findsOneWidget);
      expect(_opacityOf(tester, find.byType(MotionReveal)), 0);

      await tester.pumpAndSettle();
      expect(_opacityOf(tester, find.byType(MotionReveal)), 1);
    });

    testWidgets('is ONE-SHOT — D-29 bans looping and idle animation',
        (tester) async {
      await tester.pumpWidget(_host(const MotionReveal(child: Text('hello'))));
      await tester.pumpAndSettle();

      // If anything looped, pumpAndSettle would have timed out above. Assert
      // the settled value holds rather than cycling back down.
      await tester.pump(const Duration(seconds: 2));
      expect(_opacityOf(tester, find.byType(MotionReveal)), 1);
    });

    testWidgets('a staggered sibling starts later but still arrives',
        (tester) async {
      await tester.pumpWidget(_host(
        Column(
          children: [
            MotionReveal.staggered(index: 0, child: const Text('first')),
            MotionReveal.staggered(index: 3, child: const Text('fourth')),
          ],
        ),
      ));

      // Part-way through the first one's run, the delayed one has not begun.
      await tester.pump(const Duration(milliseconds: 100));
      final first = _opacityOf(tester, find.byType(MotionReveal).first);
      final fourth = _opacityOf(tester, find.byType(MotionReveal).last);
      expect(first, greaterThan(0));
      expect(fourth, 0);

      await tester.pumpAndSettle();
      expect(_opacityOf(tester, find.byType(MotionReveal).last), 1);
    });

    testWidgets('the child is laid out from the first frame, so nothing '
        'shifts as it arrives', (tester) async {
      await tester.pumpWidget(_host(const MotionReveal(child: Text('hello'))));

      final atStart = tester.getSize(find.text('hello'));
      await tester.pumpAndSettle();
      final atEnd = tester.getSize(find.text('hello'));

      // Opacity and transform do not affect layout — this is what D-05 buys.
      expect(atStart, atEnd);
    });
  });

  group('reduced motion is an accessibility requirement, not an option', () {
    testWidgets('scale and travel are dropped, the fade remains',
        (tester) async {
      await tester.pumpWidget(_host(
        const MotionReveal(scaleFrom: 0.5, child: Text('hello')),
        reducedMotion: true,
      ));
      await tester.pump(const Duration(milliseconds: 1));

      // D-29: "expressive motion off, opacity fades only".
      expect(
        find.descendant(
          of: find.byType(MotionReveal),
          matching: find.byType(Transform),
        ),
        findsNothing,
        reason: 'no scale and no travel under reduced motion',
      );
      expect(find.byType(Opacity), findsWidgets);

      await tester.pumpAndSettle();
      expect(_opacityOf(tester, find.byType(MotionReveal)), 1);
    });

    testWidgets('the confirmation overshoot is dropped too', (tester) async {
      await tester.pumpWidget(_host(
        const MotionConfirm(show: true, child: Text('saved')),
        reducedMotion: true,
      ));
      await tester.pump(const Duration(milliseconds: 1));

      expect(
        find.descendant(
          of: find.byType(MotionConfirm),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );

      await tester.pumpAndSettle();
      expect(find.text('saved'), findsOneWidget);
    });

    testWidgets('content still ends up fully visible and usable',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(_host(
        MotionReveal(
          child: TextButton(
            onPressed: () => tapped = true,
            child: const Text('press me'),
          ),
        ),
        reducedMotion: true,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('press me'));
      expect(tapped, isTrue);
    });
  });

  group('D-29 prohibitions', () {
    test('tab switching has no transition — instant is correct', () {
      // A surface switched dozens of times a day must not cost 200ms each
      // time. The shell uses IndexedStack, which swaps without animating;
      // an animated container here would also break D-30's keep-alive.
      final shell =
          File('lib/core/shell/app_shell.dart').readAsStringSync();
      final code = shell
          .split('\n')
          .where((line) {
            final t = line.trimLeft();
            return !t.startsWith('//') && !t.startsWith('///');
          })
          .join('\n');

      expect(code.contains('IndexedStack'), isTrue);
      for (final banned in [
        'AnimatedSwitcher',
        'PageView',
        'TabBarView',
        'FadeTransition',
      ]) {
        expect(
          code.contains(banned),
          isFalse,
          reason: 'D-29 prohibits transitions on tab switching; $banned '
              'would introduce one',
        );
      }
    });

    test('no reveal is used as a looping or idle animation', () {
      final source =
          File('lib/core/widgets/motion_reveal.dart').readAsStringSync();
      final code = source
          .split('\n')
          .where((line) {
            final t = line.trimLeft();
            return !t.startsWith('//') && !t.startsWith('///');
          })
          .join('\n');

      // D-29 bans looping/idle animation outright, on battery. The skeleton
      // shimmer is the single documented exception and lives elsewhere.
      for (final banned in ['repeat(', 'reverse(']) {
        expect(code.contains(banned), isFalse, reason: '$banned loops');
      }
    });
  });

  group('MotionConfirm', () {
    testWidgets('shows nothing until asked', (tester) async {
      await tester.pumpWidget(
        _host(const MotionConfirm(show: false, child: Text('saved'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('saved'), findsNothing);
    });

    testWidgets('plays once when it turns on', (tester) async {
      await tester.pumpWidget(
        _host(const MotionConfirm(show: false, child: Text('saved'))),
      );
      await tester.pumpWidget(
        _host(const MotionConfirm(show: true, child: Text('saved'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('saved'), findsOneWidget);
      // Settled, not cycling.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('saved'), findsOneWidget);
    });
  });
}
