import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/router/offline_restore_screen.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;

/// Hard-QA BUG-QA-16: the offline start screen recovers on its own.
void main() {
  Widget host(Future<void> Function() onRetry) => MaterialApp(
    theme: AppTheme.light(role: AppRole.teacher),
    home: OfflineRestoreScreen(
      onRetry: onRetry,
      backoff: const [
        Duration(seconds: 5),
        Duration(seconds: 10),
        Duration(seconds: 20),
      ],
    ),
  );

  testWidgets('retries automatically on a growing, bounded interval', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      host(() async {
        calls++;
        throw Exception('still offline');
      }),
    );
    expect(calls, 0, reason: 'no request storm on the first frame');
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 9));
    expect(calls, 1, reason: 'the second wait is 10 s');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(calls, 2);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 20));
      await tester.pump();
    }
    expect(calls, 5, reason: 'the last delay repeats; never faster');
    expect(
      find.text('Reconnecting automatically. You do not need to do anything.'),
      findsOneWidget,
    );
  });

  testWidgets('resume retries immediately, and only one attempt runs at a time', (
    tester,
  ) async {
    var calls = 0;
    var inFlight = 0;
    var maxInFlight = 0;
    await tester.pumpWidget(
      host(() async {
        calls++;
        inFlight++;
        if (inFlight > maxInFlight) maxInFlight = inFlight;
        await Future<void>.delayed(const Duration(seconds: 3));
        inFlight--;
        throw Exception('offline');
      }),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, 1, reason: 'resume retries at once');
    // A tap and another resume while the first attempt is in flight are ignored.
    await tester.tap(
      find.byKey(const Key('offline-retry')),
      warnIfMissed: false,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(maxInFlight, 1, reason: 'single flight');
    expect(calls, 1);
  });

  testWidgets('no further attempts once the screen is replaced', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(host(() async => calls++));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(calls, 1);
    await tester.pumpWidget(const MaterialApp(home: Text('signed in')));
    await tester.pump(const Duration(minutes: 5));
    expect(calls, 1, reason: 'timer cancelled on dispose');
  });
}
