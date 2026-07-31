import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/scales.dart';
import 'package:smartems/core/theme/token_gallery.dart';
import 'package:smartems/core/theme/tokens.dart';
import 'package:smartems/core/theme/typography.dart';

/// One rendered text element, reduced to the properties that must NOT change
/// when only the theme brightness changes.
///
/// Colour is deliberately excluded — colour is the one thing that IS allowed
/// to differ between modes.
typedef _TextShape = ({
  String text,
  Rect rect,
  double? fontSize,
  FontWeight? fontWeight,
  String? fontFamily,
});

List<_TextShape> _shapes(WidgetTester tester) {
  final out = <_TextShape>[];
  for (final element in find.byType(Text).evaluate()) {
    final widget = element.widget as Text;
    final box = element.renderObject as RenderBox?;
    if (box == null || !box.hasSize) continue;
    final topLeft = box.localToGlobal(Offset.zero);
    out.add((
      text: widget.data ?? '',
      rect: Rect.fromLTWH(
        topLeft.dx,
        topLeft.dy,
        box.size.width,
        box.size.height,
      ),
      fontSize: widget.style?.fontSize,
      fontWeight: widget.style?.fontWeight,
      fontFamily: widget.style?.fontFamily,
    ));
  }
  return out;
}

Widget _gallery({required bool isDark}) {
  return MaterialApp(
    themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
    theme: AppTheme.light(role: AppRole.teacher),
    darkTheme: AppTheme.dark(role: AppRole.teacher),
    home: TokenGalleryScreen(isDark: isDark, onToggleBrightness: () {}),
  );
}

void main() {
  // A viewport tall enough that the ListView builds every row, so "renders
  // every token" is actually checked rather than only the visible slice.
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 26000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  for (final isDark in [false, true]) {
    final mode = isDark ? 'dark' : 'light';

    testWidgets('gallery renders every colour token in $mode mode',
        (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(_gallery(isDark: isDark));
      await tester.pump();

      final tokens = isDark ? SmartEmsTokens.dark : SmartEmsTokens.light;
      var count = 0;
      for (final group in tokens.colourGroups) {
        for (final (name, _) in group.$2) {
          expect(
            find.text(name),
            findsOneWidget,
            reason: 'colour token "$name" is not rendered in $mode mode',
          );
          count++;
        }
      }
      // Self-checking: the gallery must render EVERY token listed in
      // colourGroups, so this catches a token added to the class but not to
      // the gallery list. Expressed against the source of truth rather than a
      // magic number, which otherwise breaks on every legitimate addition.
      final declared =
          tokens.colourGroups.fold<int>(0, (n, g) => n + g.$2.length);
      expect(
        count,
        declared,
        reason: 'a token in colourGroups is not rendered in the gallery',
      );

      // Floor, so tokens cannot be quietly DELETED either: 31 from the spec
      // table + primaryAccent (RULING 2) + primaryTextOnSurface (RULING 3.1).
      expect(declared, greaterThanOrEqualTo(33));
    });

    testWidgets('gallery renders every spacing and radius step in $mode mode',
        (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(_gallery(isDark: isDark));
      await tester.pump();

      for (final (name, _) in AppSpacing.all) {
        expect(find.text(name), findsOneWidget, reason: 'missing $name');
      }
      for (final (name, _) in AppRadius.all) {
        expect(find.text(name), findsOneWidget, reason: 'missing $name');
      }
    });

    testWidgets('gallery renders every typography style in $mode mode',
        (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(_gallery(isDark: isDark));
      await tester.pump();

      for (final (name, label, _) in AppTypography.all) {
        expect(
          find.text('$name — $label'),
          findsOneWidget,
          reason: 'typography style "$name" is not rendered in $mode mode',
        );
      }
    });
  }

  testWidgets('toggling brightness changes colour only — no layout or font shift',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 26000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_gallery(isDark: false));
    await tester.pump();
    final lightShapes = _shapes(tester);

    await tester.pumpWidget(_gallery(isDark: true));
    await tester.pump();
    final darkShapes = _shapes(tester);

    expect(lightShapes, isNotEmpty);

    // The mode banner label is the one string that intentionally differs.
    const intentionallyDifferent = {'Light mode', 'Dark mode'};

    final light = lightShapes
        .where((s) => !intentionallyDifferent.contains(s.text))
        .toList();
    final dark = darkShapes
        .where((s) => !intentionallyDifferent.contains(s.text))
        .toList();

    expect(
      dark.length,
      light.length,
      reason: 'a different number of text elements rendered between modes',
    );

    for (var i = 0; i < light.length; i++) {
      final l = light[i];
      final d = dark[i];
      expect(d.text, l.text, reason: 'text changed at index $i');
      expect(d.rect, l.rect, reason: 'LAYOUT SHIFT on "${l.text}"');
      expect(d.fontSize, l.fontSize, reason: 'SIZE CHANGE on "${l.text}"');
      expect(d.fontWeight, l.fontWeight, reason: 'WEIGHT CHANGE on "${l.text}"');
      expect(d.fontFamily, l.fontFamily, reason: 'FONT CHANGE on "${l.text}"');
    }
  });

  testWidgets('no raw Colors.* or hardcoded colour reaches the gallery theme',
      (tester) async {
    // Guards the D-23 invariant: the action colour is the same in both modes,
    // so a mode-dependent action colour would mean someone hardcoded one.
    await tester.pumpWidget(_gallery(isDark: false));
    final lightAction = tester
        .element(find.byType(TokenGalleryScreen))
        .tokens
        .primaryAction;

    await tester.pumpWidget(_gallery(isDark: true));
    final darkAction = tester
        .element(find.byType(TokenGalleryScreen))
        .tokens
        .primaryAction;

    expect(darkAction, lightAction);
  });
}
