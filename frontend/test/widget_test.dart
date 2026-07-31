import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/tokens.dart';
import 'package:smartems/core/theme/typography.dart';

void main() {
  group('SmartEmsTokens resolve per mode', () {
    testWidgets('light theme resolves light token values', (tester) async {
      SmartEmsTokens? resolved;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(role: AppRole.teacher),
          home: Builder(
            builder: (context) {
              resolved = context.tokens;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(resolved, isNotNull);
      expect(resolved!.page, SmartEmsTokens.light.page);
      expect(resolved!.surface, SmartEmsTokens.light.surface);
      expect(resolved!.textPrimary, SmartEmsTokens.light.textPrimary);
    });

    testWidgets('dark theme resolves dark token values', (tester) async {
      SmartEmsTokens? resolved;

      await tester.pumpWidget(
        MaterialApp(
          themeMode: ThemeMode.dark,
          theme: AppTheme.light(role: AppRole.teacher),
          darkTheme: AppTheme.dark(role: AppRole.teacher),
          home: Builder(
            builder: (context) {
              resolved = context.tokens;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(resolved, isNotNull);
      expect(resolved!.page, SmartEmsTokens.dark.page);
      expect(resolved!.surface, SmartEmsTokens.dark.surface);
      expect(resolved!.textPrimary, SmartEmsTokens.dark.textPrimary);
    });

    test('primaryAction is identical in both modes (D-23)', () {
      expect(SmartEmsTokens.light.primaryAction,
          SmartEmsTokens.dark.primaryAction);
      expect(SmartEmsTokens.light.primaryPressed,
          SmartEmsTokens.dark.primaryPressed);
    });

    test('lerp returns a valid instance at both ends', () {
      final atStart = SmartEmsTokens.light.lerp(SmartEmsTokens.dark, 0);
      final atEnd = SmartEmsTokens.light.lerp(SmartEmsTokens.dark, 1);
      expect(atStart.page, SmartEmsTokens.light.page);
      expect(atEnd.page, SmartEmsTokens.dark.page);
    });

    test('copyWith overrides only the named token', () {
      const override = Color(0xFF123456);
      final result = SmartEmsTokens.light.copyWith(page: override);
      expect(result.page, override);
      expect(result.surface, SmartEmsTokens.light.surface);
    });
  });

  group('Typography', () {
    test('every style has tabular figures enabled', () {
      for (final (name, _, style) in AppTypography.all) {
        expect(
          style.fontFeatures,
          contains(const FontFeature.tabularFigures()),
          reason: '$name is missing FontFeature.tabularFigures()',
        );
      }
    });

    test('no style is below 12px', () {
      for (final (name, _, style) in AppTypography.all) {
        expect(
          style.fontSize,
          greaterThanOrEqualTo(12),
          reason: '$name is below the 12px floor',
        );
      }
    });

    test('only weights 400, 500, 600 are used', () {
      final allowed = {FontWeight.w400, FontWeight.w500, FontWeight.w600};
      for (final (name, _, style) in AppTypography.all) {
        expect(
          allowed,
          contains(style.fontWeight),
          reason: '$name uses a weight outside {400, 500, 600}',
        );
      }
    });

    test('base body size per role matches D-24', () {
      expect(AppRole.parent.baseBodySize, 16);
      expect(AppRole.student.baseBodySize, 16);
      expect(AppRole.teacher.baseBodySize, 15);
      expect(AppRole.admin.baseBodySize, 14);
    });
  });
}
