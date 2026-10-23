import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/app_button.dart';
import 'package:smartems/core/widgets/page_header.dart';

/// Overhaul M1: the shared page header.
void main() {
  Future<void> pump(WidgetTester tester, double width, {double textScale = 1}) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(role: AppRole.admin),
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: PageHeader(
            title: 'Students of Rehearsal Academy North Campus A',
            subtitle: 'Everyone enrolled at the campuses you can manage.',
            actions: [AppButton(key: const Key('act'), label: 'Admit learner', onPressed: () {})],
          ),
        ),
      ),
    ));
  }

  testWidgets('the title is a semantic header', (tester) async {
    await pump(tester, 1024);
    expect(find.bySemanticsLabel('Students of Rehearsal Academy North Campus A'), findsOneWidget);
    expect(tester.getSemantics(find.text('Students of Rehearsal Academy North Campus A')), isSemantics(isHeader: true));
  });

  testWidgets('wide: action beside the title', (tester) async {
    await pump(tester, 1024);
    final title = tester.getTopLeft(find.textContaining('Students of'));
    final action = tester.getTopLeft(find.byKey(const Key('act')));
    expect(action.dx, greaterThan(title.dx));
    expect((action.dy - title.dy).abs(), lessThan(40));
  });

  testWidgets('320 px with large text: action wraps BELOW, nothing overflows', (tester) async {
    await pump(tester, 320, textScale: 1.3);
    expect(tester.takeException(), isNull);
    final titleBottom = tester.getBottomLeft(find.textContaining('Students of')).dy;
    expect(tester.getTopLeft(find.byKey(const Key('act'))).dy, greaterThan(titleBottom));
    expect(find.byKey(const Key('act')).hitTestable(), findsOneWidget, reason: 'the action stays reachable');
  });
}
