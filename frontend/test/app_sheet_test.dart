import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/app_sheet.dart';

/// Overhaul M1: the shared bottom sheet.
void main() {
  Future<void> open(
    WidgetTester tester, {
    int lines = 3,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(role: AppRole.admin),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppSheet<void>(
              context,
              title: 'Fee plan details',
              builder: (_) => Column(
                children: [
                  for (var i = 0; i < lines; i++)
                    SizedBox(height: 60, child: Text('Line $i')),
                ],
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('titled as a heading and closable with a named button', (
    tester,
  ) async {
    await open(tester);
    expect(
      tester.getSemantics(find.text('Fee plan details')),
      isSemantics(isHeader: true),
    );
    expect(find.byTooltip('Close'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sheet-close')));
    await tester.pumpAndSettle();
    expect(find.text('Fee plan details'), findsNothing);
  });

  testWidgets(
    'long content scrolls instead of overflowing, close stays reachable',
    (tester) async {
      await open(tester, lines: 40, size: const Size(320, 640));
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('sheet-close')).hitTestable(),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(find.text('Line 39'), 200);
      expect(find.text('Line 39'), findsOneWidget);
    },
  );
}
