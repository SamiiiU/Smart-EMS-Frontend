import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/composites_gallery.dart';
import 'package:smartems/core/theme/primitives_gallery.dart';
import 'package:smartems/core/theme/scales.dart';
import 'package:smartems/core/theme/states_gallery.dart';
import 'package:smartems/core/theme/token_gallery.dart';
import 'package:smartems/core/theme/typography.dart';
import 'package:smartems/core/widgets/app_data_table.dart';
import 'package:smartems/core/widgets/list_row.dart';
import 'package:smartems/core/widgets/status_pill.dart';

/// Renders the gallery to PNG in both modes so tokens and primitives can be
/// reviewed as real pixels.
///
/// Regenerate with:  flutter test --update-goldens test/golden_test.dart
///
/// These goldens are meaningful now that Plus Jakarta Sans is BUNDLED
/// (assets/fonts/) rather than fetched at runtime — the text renders in the
/// real typeface, so the images prove colour, layout AND type.
void main() {
  setUpAll(() {
    // Belt and braces: main() sets this too, but tests do not run main().
    // With the font bundled there is no network path either way.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget app({required bool isDark, required Widget home}) {
    return MaterialApp(
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      theme: AppTheme.light(role: AppRole.teacher),
      darkTheme: AppTheme.dark(role: AppRole.teacher),
      home: home,
    );
  }

  for (final isDark in [false, true]) {
    final mode = isDark ? 'dark' : 'light';

    testWidgets('token gallery golden — $mode', (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        app(
          isDark: isDark,
          home: TokenGalleryScreen(
            isDark: isDark,
            onToggleBrightness: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(TokenGalleryScreen),
        matchesGoldenFile('goldens/token_gallery_$mode.png'),
      );
    });

    testWidgets('primitives golden — $mode', (tester) async {
      tester.view.physicalSize = const Size(900, 4200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        app(
          isDark: isDark,
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(AppSpacing.space6),
              child: PrimitivesGallerySection(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(PrimitivesGallerySection),
        matchesGoldenFile('goldens/primitives_$mode.png'),
      );
    });

    testWidgets('composites golden — $mode', (tester) async {
      tester.view.physicalSize = const Size(900, 5200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        app(
          isDark: isDark,
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(AppSpacing.space6),
              child: CompositesGallerySection(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(CompositesGallerySection),
        matchesGoldenFile('goldens/composites_$mode.png'),
      );
    });

    testWidgets('states golden — $mode', (tester) async {
      tester.view.physicalSize = const Size(900, 7000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        app(
          isDark: isDark,
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(AppSpacing.space6),
              child: StatesGallerySection(),
            ),
          ),
        ),
      );
      // Settle the shimmer to a deterministic frame — otherwise the golden
      // captures a random point in the opacity cycle and never matches.
      await tester.pump(const Duration(milliseconds: 450));

      await expectLater(
        find.byType(StatesGallerySection),
        matchesGoldenFile('goldens/states_$mode.png'),
      );
    });

    // The collapsed table is a distinct visual state worth reviewing.
    testWidgets('data table collapsed golden — $mode', (tester) async {
      tester.view.physicalSize = const Size(360, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        app(
          isDark: isDark,
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(AppSpacing.space5),
              child: AppDataTable(
                columns: ['Student', 'Class', 'Present %'],
                rows: [
                  AppDataRow(
                    cells: ['Ayesha Khan', '9-C', '96%'],
                    status: AppStatus.active,
                  ),
                  AppDataRow(
                    cells: ['Bilal Mehmood', '9-C', '71%'],
                    status: AppStatus.partial,
                    tint: RowTint.warning,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(AppDataTable),
        matchesGoldenFile('goldens/data_table_collapsed_$mode.png'),
      );
    });
  }
}
