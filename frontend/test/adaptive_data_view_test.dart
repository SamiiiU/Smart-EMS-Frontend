import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/adaptive_data_view.dart';

/// Overhaul M1: one data pattern, table on wide screens and cards on phones.
typedef _Row = ({String name, String code, String amount});

void main() {
  const rows = <_Row>[
    (name: 'Ayesha Khan', code: 'N-A-001', amount: 'PKR 5,000.00'),
    (name: 'Bilal Ahmed', code: 'N-A-002', amount: 'PKR 2,500.00'),
  ];
  Future<List<_Row>> pump(WidgetTester tester, double width) async {
    final tapped = <_Row>[];
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(role: AppRole.admin),
      home: Scaffold(
        body: AdaptiveDataView<_Row>(
          rows: rows,
          semanticLabel: (r) => r.name,
          onTap: tapped.add,
          columns: [
            DataColumnSpec(label: 'Name', value: (r) => r.name, flex: 3),
            DataColumnSpec(label: 'Admission no.', value: (r) => r.code, flex: 2),
            DataColumnSpec(label: 'Outstanding', value: (r) => r.amount, flex: 2, numeric: true),
          ],
        ),
      ),
    ));
    return tapped;
  }

  testWidgets('wide: a table with one header row', (tester) async {
    await pump(tester, 1024);
    expect(find.text('Admission no.'), findsOneWidget, reason: 'header shown once, not per row');
    expect(find.text('N-A-001'), findsOneWidget);
    expect(find.textContaining('Admission no.: '), findsNothing);
  });

  testWidgets('phone: cards with labelled values, no overflow at 320 px', (tester) async {
    await pump(tester, 320);
    expect(tester.takeException(), isNull);
    expect(find.text('Admission no.'), findsNothing, reason: 'no table header on phones');
    expect(find.textContaining('Admission no.: '), findsNWidgets(2));
  });

  testWidgets('same action and accessible name in both layouts', (tester) async {
    for (final w in [1024.0, 390.0]) {
      final tapped = await pump(tester, w);
      expect(find.bySemanticsLabel('Bilal Ahmed'), findsOneWidget, reason: 'width $w');
      await tester.tap(find.bySemanticsLabel('Bilal Ahmed'));
      await tester.pump();
      expect(tapped.single.code, 'N-A-002', reason: 'width $w');
    }
  });
}
