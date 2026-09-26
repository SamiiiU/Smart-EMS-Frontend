import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartems/main.dart' as app;

/// The proof three batches have been missing.
///
/// `flutter test` replaces the clock with a fake one, so an HTTP call started
/// by a widget never completes — a screen sits on "Saving…" for ever. Every
/// batch so far has therefore been proven in two halves: screens hermetically
/// against a stub, and the network separately through the repository, with a
/// manual pass bridging them. That manual pass is no longer free — the fee and
/// exam modules create records this backend cannot delete.
///
/// This runs the REAL widgets, on a REAL event loop, against the REAL backend.
///
/// **Deliberately small.** It is not coverage: `academics_test.dart` and the
/// rest cover behaviour far better and far faster. This answers one question
/// the hermetic suite structurally cannot — *do the screens actually work when
/// the network is real?* Three steps: sign in, load a screen, perform a write.
///
/// ```
/// flutter test integration_test/app_smoke_test.dart -d chrome --web-port=3000
/// ```
/// Chrome on port 3000 specifically: the backend's CORS allowlist is
/// origin-exact, so any other port is blocked by the browser. It also runs on
/// an Android device or emulator with no port constraint.
///
/// It needs the backend up, and it signs in as `admin` / `test-school`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Start signed out every time. A token left by a previous run would skip
    // the login screen and quietly test something else.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('sign in, load a screen, and write — against the real backend',
      (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 10));

    // --- 1 · Sign in -------------------------------------------------------
    expect(find.text('Sign in'), findsWidgets,
        reason: 'the app should start at the login screen');

    final fields = find.byType(TextField);
    expect(fields, findsAtLeast(3));

    await tester.enterText(fields.at(0), 'test-school');
    await tester.enterText(fields.at(1), 'admin');
    await tester.enterText(fields.at(2), 'Test1234!');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ButtonStyleButton, 'Sign in').last);

    // A real round trip. pumpAndSettle would give up while it is in flight,
    // so poll until the shell appears instead.
    await _settleUntil(
      tester,
      () => find.text('Dashboard').evaluate().isNotEmpty,
      what: 'the admin shell after sign-in',
    );

    // --- 2 · A screen that loads from the network --------------------------
    expect(find.text('Dashboard'), findsWidgets);

    // --- 3 · A write, end to end -------------------------------------------
    // Fee heads is the cheapest real write in the product: one required
    // field, no dependencies, and it is visible in the list immediately.
    await _openTab(tester, 'Fees');
    await _settleUntil(
      tester,
      () => find.text('Fee heads').evaluate().isNotEmpty,
      what: 'the Fees hub',
    );

    await tester.tap(find.text('Fee heads').first);
    await _settleUntil(
      tester,
      () => find.text('Add a fee head').evaluate().isNotEmpty,
      what: 'the fee heads screen',
    );

    await tester.tap(find.text('Add a fee head'));
    await tester.pumpAndSettle();

    final name = 'IT ${DateTime.now().millisecondsSinceEpoch}';
    await tester.enterText(find.byType(TextField).first, name);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await _settleUntil(
      tester,
      () => find.text(name).evaluate().isNotEmpty,
      what: 'the newly created fee head in the list',
    );

    // It came back from the server, through the real repository, into the
    // real list. That is the whole point of this file.
    expect(find.text(name), findsWidgets);
  });
}

/// Pumps until [condition] holds, or fails with a readable message.
///
/// `pumpAndSettle` cannot be used across a real network call: it settles when
/// the frame scheduler is idle, which happens while the request is still in
/// flight, and then the assertion runs too early.
Future<void> _settleUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String what,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (condition()) return;
  }
  fail('Timed out after ${timeout.inSeconds}s waiting for: $what');
}

/// Taps a destination by label, whichever chrome the viewport is showing —
/// the shell renders a bottom bar, a rail or a drawer depending on width.
Future<void> _openTab(WidgetTester tester, String label) async {
  final drawerButton = find.byTooltip('Open navigation menu');
  if (drawerButton.evaluate().isNotEmpty) {
    await tester.tap(drawerButton);
    await tester.pumpAndSettle();
  }

  var target = find.text(label);
  if (target.evaluate().isEmpty) {
    // Behind More on a narrow viewport.
    final more = find.text('More');
    if (more.evaluate().isNotEmpty) {
      await tester.tap(more.last);
      await tester.pumpAndSettle();
      target = find.text(label);
    }
  }

  expect(target, findsWidgets, reason: 'no destination labelled "$label"');
  await tester.tap(target.last);
  await tester.pumpAndSettle();
}
