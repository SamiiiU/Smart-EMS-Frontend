import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/network_identity_resolver.dart';
import 'package:smartems/core/network/token_store.dart';
import 'package:smartems/core/router/auth_state.dart';
import 'package:smartems/core/router/offline_restore_screen.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;

/// S3 (M1 screen sprint): a cold start answered with HTTP 429 must keep the
/// stored session and say "busy", not "offline" and not "signed out".
/// Wires the REAL resolver and AuthState; only the HTTP transport is scripted.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.status);
  int? status; // null = no response (connection failure)
  int calls = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    calls++;
    final code = status;
    if (code == null) {
      throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
    }
    return ResponseBody.fromString('{"message":"x"}', code, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

Future<(AuthState, InMemoryTokenStore, _Adapter)> _coldStart(int? status) async {
  final adapter = _Adapter(status);
  final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))..httpClientAdapter = adapter;
  final store = InMemoryTokenStore(accessToken: 'a', refreshToken: 'r');
  final auth = AuthState(tokenStore: store, identityResolver: NetworkIdentityResolver(dio));
  await auth.restore();
  return (auth, store, adapter);
}

/// Same composition as the router's offline route.
Widget _gate(AuthState auth) => MaterialApp(
      theme: AppTheme.light(role: AppRole.teacher),
      home: ListenableBuilder(
        listenable: auth,
        builder: (context, _) => OfflineRestoreScreen(
          onRetry: auth.retryRestore,
          serverBusy: auth.restoreServerBusy,
          backoff: const [Duration(hours: 1)],
        ),
      ),
    );

void main() {
  testWidgets('429 at cold start: session kept, gate says server busy', (tester) async {
    late AuthState auth;
    late InMemoryTokenStore store;
    await tester.runAsync(() async {
      (auth, store, _) = await _coldStart(429);
    });
    expect(auth.offlineRestore, isTrue, reason: 'rate limiting is not a sign-out');
    expect(auth.isSignedIn, isFalse, reason: 'no unverified identity is granted');
    expect(auth.restoreServerBusy, isTrue);
    expect(store.accessToken, 'a');
    expect(store.refreshToken, 'r');

    await tester.pumpWidget(_gate(auth));
    expect(find.text('Server busy'), findsOneWidget);
    expect(find.text("You're offline"), findsNothing);
    expect(find.textContaining('too many requests'), findsOneWidget);
    expect(find.text('Retrying automatically. You do not need to do anything.'), findsOneWidget);
    expect(find.text('Try again now'), findsOneWidget);
  });

  testWidgets('no response at cold start keeps the offline wording', (tester) async {
    late AuthState auth;
    await tester.runAsync(() async {
      (auth, _, _) = await _coldStart(null);
    });
    expect(auth.offlineRestore, isTrue);
    expect(auth.restoreServerBusy, isFalse);

    await tester.pumpWidget(_gate(auth));
    expect(find.text("You're offline"), findsOneWidget);
    expect(find.text('Server busy'), findsNothing);
  });

  testWidgets('401 at cold start still signs out (no gate)', (tester) async {
    late AuthState auth;
    await tester.runAsync(() async {
      (auth, _, _) = await _coldStart(401);
    });
    expect(auth.offlineRestore, isFalse);
    expect(auth.restoreServerBusy, isFalse);
    expect(auth.isSignedIn, isFalse);
  });

  testWidgets('wording follows the latest failure: busy, then offline', (tester) async {
    late AuthState auth;
    late _Adapter adapter;
    await tester.runAsync(() async {
      (auth, _, adapter) = await _coldStart(429);
    });
    await tester.pumpWidget(_gate(auth));
    expect(find.text('Server busy'), findsOneWidget);

    adapter.status = null;
    await tester.runAsync(auth.retryRestore);
    await tester.pump();
    expect(auth.offlineRestore, isTrue);
    expect(find.text("You're offline"), findsOneWidget);
  });
}
