import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/api_config.dart';
import 'package:smartems/core/network/token_store.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/app_text_field.dart';
import 'package:smartems/core/widgets/keyboard_tap_target.dart';
import 'package:smartems/features/auth/data/auth_repository.dart';
import 'package:smartems/features/auth/presentation/login_screen.dart';

/// Login "Show password" toggle: a 48 x 48 touch target on touch platforms
/// (it was the 20 px icon), with the icon's size and behaviour unchanged.

class _NoNetwork implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async =>
      ResponseBody.fromBytes(utf8.encode('{}'), 500, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
  @override
  void close({bool force = false}) {}
}

AuthRepository _repo() => AuthRepository(
      dio: Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))..httpClientAdapter = _NoNetwork(),
      tokenStore: InMemoryTokenStore(),
    );

Future<void> _pump(WidgetTester tester, TargetPlatform platform, {double width = 390}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(role: AppRole.admin).copyWith(platform: platform),
    home: Scaffold(body: LoginScreen(repository: _repo(), onSignedIn: () {})),
  ));
  await tester.pumpAndSettle();
}

Finder get _toggle => find.ancestor(of: find.byIcon(Icons.visibility_outlined), matching: find.byType(KeyboardTapTarget));
bool get _obscured => (find.byWidgetPredicate((w) => w is EditableText && w.obscureText).evaluate().isNotEmpty);

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('${width.toInt()} px Android: toggle target is at least 48 x 48; icon stays 20 px', (tester) async {
      await _pump(tester, TargetPlatform.android, width: width);
      final size = tester.getSize(_toggle);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(tester.widget<Icon>(find.byIcon(Icons.visibility_outlined)).size, 20, reason: 'icon size unchanged');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a tap near the corner of the target (outside the icon) still toggles', (tester) async {
    await _pump(tester, TargetPlatform.android);
    expect(_obscured, isTrue);
    final rect = tester.getRect(_toggle);
    await tester.tapAt(rect.topLeft + const Offset(3, 3));
    await tester.pump();
    expect(_obscured, isFalse);
    expect(find.bySemanticsLabel('Hide password'), findsOneWidget);
  });

  testWidgets('the target does not overlap the text: field text area ends before it', (tester) async {
    await _pump(tester, TargetPlatform.android);
    final password = find.byWidgetPredicate((w) => w is EditableText && w.obscureText);
    expect(tester.getRect(password).right, lessThanOrEqualTo(tester.getRect(_toggle).left));
  });

  testWidgets('keyboard and semantics unchanged: Tab reaches it, Enter toggles, one named node', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, TargetPlatform.windows, width: 1024);
    await tester.enterText(find.byWidgetPredicate((w) => w is EditableText && w.obscureText), 'x');
    await tester.pump();
    var reached = false;
    for (var i = 0; i < 6 && !reached; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final node = tester.getSemantics(find.bySemanticsLabel('Show password'));
      reached = node.getSemanticsData().flagsCollection.isFocused.toString().contains('isTrue');
    }
    expect(reached, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.bySemanticsLabel('Hide password'), findsOneWidget);
    expect(find.bySemanticsLabel('Show password'), findsNothing);
    handle.dispose();
  });

  testWidgets('other trailing widgets (opt-out) keep the old inline layout', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(role: AppRole.admin),
      home: const Scaffold(body: AppTextField(label: 'Search', trailing: Icon(Icons.close, key: Key('x'), size: 20))),
    ));
    expect(tester.getSize(find.byKey(const Key('x'))), const Size(20, 20));
  });
}
