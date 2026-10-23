import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/adaptive_data_view.dart';

/// Android TalkBack finding (report 11): an AdaptiveDataView row excluded ALL
/// child semantics, so editable cells (Academy marks field, Absent checkbox)
/// were unreachable by screen readers. Interactive columns must stay
/// accessible; display-only cells (status chips) stay folded into the row label.
typedef _Row = ({String id, String name});

const _rows = <_Row>[(id: 'a', name: 'Ayesha Khan')];

Future<void> _pump(
  WidgetTester tester,
  double width, {
  bool interactive = true,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(role: AppRole.admin),
      home: Scaffold(
        body: AdaptiveDataView<_Row>(
          rows: _rows,
          semanticLabel: (r) => '${r.name}, marks none',
          columns: [
            DataColumnSpec(label: 'Learner', value: (r) => r.name, flex: 2),
            DataColumnSpec(
              label: 'Marks',
              value: (r) => '',
              interactive: interactive,
              cell: (r) => SizedBox(
                width: 120,
                child: TextFormField(
                  key: Key('marks-${r.id}'),
                  decoration: const InputDecoration(hintText: '0–25'),
                ),
              ),
            ),
            DataColumnSpec(
              label: 'Absent',
              value: (r) => 'no',
              interactive: interactive,
              cell: (r) => Checkbox(
                key: Key('absent-${r.id}'),
                value: false,
                onChanged: (_) {},
              ),
            ),
            DataColumnSpec(
              label: 'Status',
              value: (r) => 'draft',
              cell: (r) => const Text('draft-chip'),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

List<SemanticsNode> _all(WidgetTester tester) {
  final out = <SemanticsNode>[];
  void walk(SemanticsNode n) {
    out.add(n);
    n.visitChildren((c) {
      walk(c);
      return true;
    });
  }

  walk(tester.getSemantics(find.byType(Scaffold)));
  return out;
}

void main() {
  for (final width in [390.0, 1024.0]) {
    testWidgets(
      '${width.toInt()} px: editable cells are reachable by screen readers',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, width);
        final nodes = _all(tester);
        expect(
          nodes.where((n) => n.flagsCollection.isTextField).length,
          1,
          reason: 'marks field exposed',
        );
        expect(
          nodes
              .where((n) => n.flagsCollection.isChecked != CheckedState.none)
              .length,
          1,
          reason: 'absent checkbox exposed',
        );
        // The field's node sits on the field, not on the whole row.
        final field = tester.getSemantics(find.byKey(const Key('marks-a')));
        expect(field.flagsCollection.isTextField, isTrue);
        // Each input names its column and row, not just "edit box"/"checkbox".
        String labelOf(bool Function(SemanticsNode) p) =>
            nodes.where(p).single.getSemanticsData().label;
        expect(
          labelOf((n) => n.flagsCollection.isTextField),
          contains('Marks, Ayesha Khan'),
        );
        expect(
          labelOf((n) => n.flagsCollection.isChecked != CheckedState.none),
          contains('Absent, Ayesha Khan'),
        );
        // The row still has its single summary label; static text is not read twice.
        expect(
          find.bySemanticsLabel('Ayesha Khan, marks none'),
          findsOneWidget,
        );
        expect(nodes.where((n) => n.label == 'Ayesha Khan'), isEmpty);
        expect(
          nodes.where((n) => n.label.contains('draft-chip')),
          isEmpty,
          reason: 'display-only cells stay folded',
        );
        handle.dispose();
      },
    );
  }

  testWidgets(
    'default (non-interactive) columns keep the previous fully folded row',
    (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, 390, interactive: false);
      final nodes = _all(tester);
      expect(nodes.where((n) => n.flagsCollection.isTextField), isEmpty);
      expect(find.bySemanticsLabel('Ayesha Khan, marks none'), findsOneWidget);
      handle.dispose();
    },
  );
}
