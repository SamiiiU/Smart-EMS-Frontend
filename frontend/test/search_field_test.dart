import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/search_field.dart';

/// Overhaul M1: the shared search field.
void main() {
  Widget host(Widget child) => MaterialApp(theme: AppTheme.light(role: AppRole.admin), home: Scaffold(body: child));

  testWidgets('empty: a search icon, no clear button, no count', (tester) async {
    await tester.pumpWidget(host(SearchField(label: 'Search', value: '', onChanged: (_) {}, resultCount: 3)));
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byKey(const Key('search-clear')), findsNothing);
    expect(find.byKey(const Key('search-count')), findsNothing);
  });

  testWidgets('typing shows the count; Clear empties it', (tester) async {
    var value = '';
    await tester.pumpWidget(StatefulBuilder(
      builder: (context, setState) => host(SearchField(
        label: 'Search',
        value: value,
        resultCount: value.isEmpty ? 10 : 1,
        onChanged: (v) => setState(() => value = v),
      )),
    ));
    await tester.enterText(find.byType(TextField), 'Ayesha');
    await tester.pump();
    expect(find.text('1 result'), findsOneWidget);
    expect(find.byTooltip('Clear search'), findsOneWidget, reason: 'named for screen readers');
    await tester.tap(find.byKey(const Key('search-clear')));
    await tester.pump();
    expect(value, '');
    expect(find.byKey(const Key('search-count')), findsNothing);
  });

  testWidgets('the count is a polite live region', (tester) async {
    await tester.pumpWidget(host(SearchField(label: 'Search', value: 'a', onChanged: (_) {}, resultCount: 2)));
    expect(tester.getSemantics(find.text('2 results')), isSemantics(isLiveRegion: true));
  });
}
