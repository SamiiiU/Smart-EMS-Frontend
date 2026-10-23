import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/widgets/business_date.dart';

/// M1: business dates are shown human-readably, never shifted through a timezone.
void main() {
  testWidgets('YYYY-MM-DD becomes a localized calendar date; anything else is shown as received', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) { ctx = c; return const SizedBox(); })));
    expect(formatBusinessDate(ctx, '2026-10-14'), 'Oct 14, 2026');
    expect(formatBusinessDate(ctx, '2026-01-01'), 'Jan 1, 2026', reason: 'no timezone shift into the previous day');
    expect(formatBusinessDate(ctx, '14/10/2026'), '14/10/2026');
  });
}
