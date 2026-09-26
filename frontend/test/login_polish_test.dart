import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/api_config.dart';
import 'package:smartems/core/network/token_store.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/app_button.dart';
import 'package:smartems/core/widgets/app_text_field.dart';
import 'package:smartems/features/auth/data/auth_repository.dart';
import 'package:smartems/features/auth/presentation/login_screen.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.responder);

  final ResponseBody Function(RequestOptions o) responder;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    requests.add(o);
    return responder(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromBytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

AuthRepository _repo([_Adapter? adapter]) => AuthRepository(
      dio: Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))
        ..httpClientAdapter = adapter ??
            _Adapter((o) => _json(200, {
                  'accessToken': 'a',
                  'refreshToken': 'r',
                  'expiresIn': 900,
                })),
      tokenStore: InMemoryTokenStore(),
    );

Widget host(
  Widget child, {
  bool reduceMotion = false,
  double textScale = 1.0,
}) {
  return MaterialApp(
    theme: AppTheme.light(role: AppRole.admin),
    builder: (context, mqChild) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: reduceMotion,
        textScaler: TextScaler.linear(textScale),
      ),
      child: mqChild!,
    ),
    home: child,
  );
}

Widget _screen({AuthRepository? repository, VoidCallback? onSignedIn}) =>
    LoginScreen(
      repository: repository ?? _repo(),
      onSignedIn: onSignedIn ?? () {},
    );

TextField _passwordField(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).at(2));

/// Reveal opacity for a specific element.
///
/// Reads the `FadeTransition` that wraps it. Targeted rather than scanning
/// the whole tree: the framework contributes its own opacity layers, so a
/// blanket assertion would be testing Flutter, not this screen.
double _opacityOf(WidgetTester tester, Finder target) => tester
    .widget<FadeTransition>(
      find.ancestor(of: target, matching: find.byType(FadeTransition)).first,
    )
    .opacity
    .value;

/// Vertical slide offset still remaining, as a fraction of the element's
/// own height. Zero once settled.
double _slideOf(WidgetTester tester, Finder target) => tester
    .widget<SlideTransition>(
      find.ancestor(of: target, matching: find.byType(SlideTransition)).first,
    )
    .position
    .value
    .dy;

Finder get _subtitle => find.text('Sign in to your institution');

/// The flying wordmark lives in an overlay; the settled heading does not.
/// Two `Smart EMS` texts exist only mid-flight.
int _wordmarkCount(WidgetTester tester) =>
    find.text('Smart EMS').evaluate().length;

void main() {
  group('Password visibility toggle', () {
    testWidgets('starts hidden, flips obscureText, and flips back',
        (tester) async {
      await tester.pumpWidget(host(_screen()));
      await tester.pumpAndSettle();

      expect(_passwordField(tester).obscureText, isTrue);

      await tester.tap(find.bySemanticsLabel('Show password'));
      await tester.pumpAndSettle();
      expect(_passwordField(tester).obscureText, isFalse);

      await tester.tap(find.bySemanticsLabel('Hide password'));
      await tester.pumpAndSettle();
      expect(_passwordField(tester).obscureText, isTrue);
    });

    testWidgets('the SEMANTIC label changes with state, not just the glyph',
        (tester) async {
      // A screen reader user cannot see which eye is drawn; the label is
      // the only thing telling them what the control will do.
      await tester.pumpWidget(host(_screen()));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Show password'), findsOneWidget);
      expect(find.bySemanticsLabel('Hide password'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Show password'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Hide password'), findsOneWidget);
      expect(find.bySemanticsLabel('Show password'), findsNothing);
    });

    testWidgets('only the password field is ever obscured', (tester) async {
      await tester.pumpWidget(host(_screen()));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(find.byType(TextField).at(0)).obscureText,
          isFalse);
      expect(tester.widget<TextField>(find.byType(TextField).at(1)).obscureText,
          isFalse);
    });
  });

  group('Focus flow', () {
    testWidgets('institution code autofocuses on entry', (tester) async {
      await tester.pumpWidget(host(_screen()));
      await tester.pumpAndSettle();

      expect(
        tester.widget<AppTextField>(find.byType(AppTextField).at(0)).autofocus,
        isTrue,
      );
    });

    testWidgets('next moves code -> username -> password, and the last field '
        'submits instead of adding a newline', (tester) async {
      final fields = <AppTextField>[];
      await tester.pumpWidget(host(_screen()));
      await tester.pumpAndSettle();

      for (var i = 0; i < 3; i++) {
        fields.add(tester.widget<AppTextField>(find.byType(AppTextField).at(i)));
      }

      expect(fields[0].textInputAction, TextInputAction.next);
      expect(fields[1].textInputAction, TextInputAction.next);
      expect(
        fields[2].textInputAction,
        TextInputAction.done,
        reason: 'the password field ends the form',
      );
    });

    testWidgets('pressing done on the password field submits a valid form',
        (tester) async {
      final adapter = _Adapter((o) => _json(200, {
            'accessToken': 'a',
            'refreshToken': 'r',
          }));
      var signedIn = 0;

      await tester.pumpWidget(host(_screen(
        repository: _repo(adapter),
        onSignedIn: () => signedIn++,
      )));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'test-school');
      await tester.enterText(find.byType(TextField).at(1), 'admin');
      await tester.enterText(find.byType(TextField).at(2), 'Test1234!');
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(signedIn, 1);
      expect(adapter.requests.single.path, ApiConfig.loginPath);
    });

    testWidgets('done on an INCOMPLETE form does nothing — the submit guard '
        'still holds', (tester) async {
      final adapter = _Adapter((o) => _json(200, {'accessToken': 'a'}));
      await tester.pumpWidget(host(_screen(repository: _repo(adapter))));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'test-school');
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(adapter.requests, isEmpty);
      expect(
        tester.widget<AppButton>(find.byType(AppButton)).onPressed,
        isNull,
        reason: 'Part A item 4: the disabled-until-complete rule must survive '
            'the polish',
      );
    });
  });

  group('Entrance animation', () {
    testWidgets('plays: the form is not fully visible on the first frame, '
        'and is once settled', (tester) async {
      await tester.pumpWidget(host(_screen()));
      await tester.pump();

      // Mid-flight: the staggered content has not arrived yet.
      expect(
        _opacityOf(tester, _subtitle),
        lessThan(1),
        reason: 'the subtitle should still be animating in on frame one',
      );

      await tester.pumpAndSettle();

      // Settled: the form content is fully present.
      expect(_opacityOf(tester, _subtitle), 1);
      expect(_opacityOf(tester, find.text('Institution code')), 1);
    });

    testWidgets('"Welcome to" appears during the intro and is gone once '
        'settled', (tester) async {
      await tester.pumpWidget(host(_screen()));
      // The intro measures in a post-frame callback and starts the controller
      // there, so this first pump is the START frame and advances no time.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Welcome to'), findsOneWidget);

      await tester.pumpAndSettle();

      // The whole flight overlay is torn down on hand-off, so the intro
      // word leaves the tree entirely rather than lingering invisibly.
      expect(find.text('Welcome to'), findsNothing);
    });

    testWidgets('the wordmark FLIES: it exists twice mid-flight (overlay + '
        'real heading) and once when settled', (tester) async {
      await tester.pumpWidget(host(_screen()));
      // Past the measure frame, into the flight.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        _wordmarkCount(tester),
        2,
        reason: 'the flying overlay copy and the real heading it lands on',
      );

      await tester.pumpAndSettle();

      expect(
        _wordmarkCount(tester),
        1,
        reason: 'after hand-off only the real heading remains',
      );
    });

    testWidgets('it HOLDS centred for a beat before flying — the pause is '
        'the point, not dead time', (tester) async {
      await tester.pumpWidget(host(_screen()));
      await tester.pump();

      // Wordmark has faded in by 700ms.
      await tester.pump(const Duration(milliseconds: 800));
      final atRest = tester.getCenter(find.text('Smart EMS').last);

      // Still inside the hold (flight starts at 1700ms).
      await tester.pump(const Duration(milliseconds: 800));
      final stillAtRest = tester.getCenter(find.text('Smart EMS').last);

      expect(
        stillAtRest.dy,
        atRest.dy,
        reason: 'a full second should pass with the wordmark stationary',
      );
    });

    testWidgets('the wordmark actually MOVES once the hold ends, and lands '
        'on the real heading', (tester) async {
      await tester.pumpWidget(host(_screen()));
      await tester.pump();

      // Just before the flight begins.
      await tester.pump(const Duration(milliseconds: 1650));
      final beforeFlight = tester.getCenter(find.text('Smart EMS').last);

      // Mid-flight.
      await tester.pump(const Duration(milliseconds: 400));
      final midFlight = tester.getCenter(find.text('Smart EMS').last);

      expect(
        midFlight.dy,
        lessThan(beforeFlight.dy),
        reason: 'it should be travelling upward toward the heading slot',
      );

      await tester.pumpAndSettle();
      final settled = tester.getCenter(find.text('Smart EMS'));
      expect(
        settled.dy,
        lessThan(beforeFlight.dy),
        reason: 'and it ends above where it started',
      );
    });

    testWidgets('an error does NOT replay the intro', (tester) async {
      // The intro is a first-impression, not a response to failure. Replaying
      // it on every wrong password would be both slow and insulting.
      final adapter = _Adapter((o) {
        throw DioException(
          requestOptions: o,
          response: Response(
            requestOptions: o,
            statusCode: 401,
            data: const {'message': 'Invalid credentials'},
          ),
        );
      });

      await tester.pumpWidget(host(_screen(repository: _repo(adapter))));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'c');
      await tester.enterText(find.byType(TextField).at(1), 'u');
      await tester.enterText(find.byType(TextField).at(2), 'bad');
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid credentials'), findsOneWidget);
      // Still settled — nothing dropped back to a partial opacity, and the
      // intro word did not come back.
      expect(_opacityOf(tester, _subtitle), 1);
      expect(_opacityOf(tester, find.text('Institution code')), 1);
      expect(find.text('Welcome to'), findsNothing);
      expect(_wordmarkCount(tester), 1);
    });

    testWidgets('fields are interactive WHILE the intro is still running',
        (tester) async {
      // The requirement: animation must never gate interaction. Typing on
      // frame one must land.
      await tester.pumpWidget(host(_screen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(find.byType(TextField).at(0), 'typed-early');
      await tester.pump();

      expect(find.text('typed-early'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('typed-early'), findsOneWidget);
    });
  });

  group('Reduced motion (D-29) — plays NONE of it', () {
    testWidgets('renders the final state on the very first frame', (tester) async {
      await tester.pumpWidget(host(_screen(), reduceMotion: true));
      // Deliberately a single pump: no settling allowed. If any of the
      // sequence were playing, something would still be faded here.
      await tester.pump();

      expect(
        _opacityOf(tester, _subtitle),
        1,
        reason: 'reduced motion must skip the sequence entirely, not play a '
            'faster version of it',
      );
      expect(_opacityOf(tester, find.text('Institution code')), 1);
      expect(_opacityOf(tester, find.text('Password')), 1);

      // The flight never happens at all: no overlay, no intro word, and the
      // heading is simply already in place.
      expect(find.text('Welcome to'), findsNothing);
      expect(_wordmarkCount(tester), 1);
      expect(find.text('Smart EMS'), findsOneWidget);
      expect(find.text('Sign in to your institution'), findsOneWidget);
      expect(find.byType(AppTextField), findsNWidgets(3));
    });

    testWidgets('no slide displacement remains on the first frame',
        (tester) async {
      await tester.pumpWidget(host(_screen(), reduceMotion: true));
      await tester.pump();

      // Every reveal ends at zero offset; a remaining slide would mean the
      // sequence is mid-flight.
      expect(_slideOf(tester, _subtitle), 0);
      expect(_slideOf(tester, find.text('Institution code')), 0);
      expect(_slideOf(tester, find.text('Password')), 0);
    });

    testWidgets('POSITIVE PAIR: with motion enabled, the first frame IS '
        'displaced — proving the reduced-motion assertion is meaningful',
        (tester) async {
      await tester.pumpWidget(host(_screen()));
      await tester.pump();

      expect(_slideOf(tester, _subtitle), greaterThan(0));
    });

    testWidgets('the form is fully usable under reduced motion',
        (tester) async {
      var signedIn = 0;
      await tester.pumpWidget(
        host(_screen(onSignedIn: () => signedIn++), reduceMotion: true),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField).at(0), 'test-school');
      await tester.enterText(find.byType(TextField).at(1), 'admin');
      await tester.enterText(find.byType(TextField).at(2), 'pw');
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(signedIn, 1);
    });
  });

  group('No overflow at 360, 768 and 1366px', () {
    for (final width in [360.0, 768.0, 1366.0]) {
      testWidgets('during AND after the intro at ${width.toInt()}px',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(host(_screen()));

        // Sampled through the sequence: the heading is largest mid-flight,
        // so checking only the end state would miss an overflow.
        for (final ms in [0, 100, 300, 500, 700, 900]) {
          await tester.pump(Duration(milliseconds: ms == 0 ? 0 : 200));
          expect(tester.takeException(), isNull, reason: 'at ~${ms}ms');
        }

        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('at 2x text scale on a 360px phone, during the intro',
        (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(_screen(), textScale: 2));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
