import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/shell/no_access_screen.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;

/// Hard-QA BUG-QA-21: no developer placeholder for an account with no role.
void main() {
  testWidgets('explains, checks again and signs out; never shows a placeholder', (tester) async {
    var checks = 0;
    var signOuts = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(role: AppRole.admin),
      home: Scaffold(
        body: NoAccessScreen(
          onSignOut: () async => signOuts++,
          onCheckAgain: () async => checks++,
        ),
      ),
    ));
    expect(find.textContaining('built in a later task'), findsNothing);
    expect(find.text('Your account has no access here yet'), findsOneWidget);
    await tester.tap(find.byKey(const Key('no-access-check')));
    await tester.pumpAndSettle();
    expect(checks, 1);
    await tester.tap(find.byKey(const Key('no-access-sign-out')));
    await tester.pumpAndSettle();
    expect(signOuts, 1);
  });

  testWidgets('fits a 320 px phone with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(role: AppRole.admin),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(1.3)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: NoAccessScreen(onSignOut: () async {}, onCheckAgain: () async {}),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });
}
