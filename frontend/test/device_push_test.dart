import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart';
import 'package:smartems/features/notifications/data/notifications_repository.dart';
import 'package:smartems/features/notifications/presentation/notifications_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartems/core/network/device_push_service.dart';
import 'package:smartems/core/network/token_store.dart';
import 'package:smartems/core/router/auth_state.dart';
import 'package:smartems/core/shell/identity_resolver.dart';
import 'package:smartems/features/auth/data/auth_repository.dart';

class FakePush implements PushDeviceClient {
  final refresh = StreamController<String>.broadcast();
  final messages = StreamController<void>.broadcast();
  bool granted = true;
  bool deleted = false;
  bool autoInit = false;
  String currentToken = 'fixture-device-token';
  Completer<bool>? permission;
  final permissionStarted = Completer<void>();
  @override
  Future<bool> ready() async => true;
  @override
  Future<bool> authorized() async => granted;
  @override
  Future<bool> requestPermission() async {
    if (!permissionStarted.isCompleted) permissionStarted.complete();
    return permission == null ? granted : permission!.future;
  }

  @override
  Future<String?> token() async => currentToken;
  @override
  Future<void> deleteToken() async {
    deleted = true;
  }

  @override
  Future<void> setAutoInit(bool enabled) async {
    autoInit = enabled;
  }

  @override
  Stream<String> get tokenRefresh => refresh.stream;
  @override
  Stream<void> get foreground => messages.stream;
}

class PushAdapter implements HttpClientAdapter {
  final calls = <String>[];
  final bodies = <dynamic>[];
  final postStarted = Completer<void>();
  Completer<void>? holdPost;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? stream,
    Future<void>? cancel,
  ) async {
    calls.add(options.method);
    bodies.add(options.data);
    if (options.method == 'POST') {
      if (!postStarted.isCompleted) postStarted.complete();
      await holdPost?.future;
    }
    return ResponseBody.fromString(
      jsonEncode({'status': 'ok'}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late AuthState auth;
  late FakePush client;
  late PushAdapter adapter;
  late DevicePushService service;
  late InMemoryTokenStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = InMemoryTokenStore(accessToken: 'fixture-access');
    auth = AuthState(
      tokenStore: store,
      identityResolver: const StaticIdentityResolver(
        IdentityResult(
          IdentityResultKind.linked,
          userId: 'fixture-user',
          tenantId: 'fixture-tenant',
        ),
      ),
    );
    client = FakePush();
    adapter = PushAdapter();
    service = DevicePushService(
      auth,
      Dio()..httpClientAdapter = adapter,
      client: client,
    );
    await auth.refreshIdentity();
  });
  tearDown(() async {
    service.dispose();
    auth.dispose();
    await client.refresh.close();
    await client.messages.close();
  });
  test(
    'permission denied never registers or enables auto initialization',
    () async {
      client.granted = false;
      expect(await service.enable(), contains('not granted'));
      expect(adapter.calls, isEmpty);
      expect(client.autoInit, isFalse);
    },
  );
  test(
    'logout drains in-flight registration then conditionally deletes its token',
    () async {
      adapter.holdPost = Completer<void>();
      final enabled = service.enable();
      await adapter.postStarted.future;
      final cleanup = service.unregister();
      adapter.holdPost!.complete();
      await enabled;
      await cleanup;
      expect(adapter.calls, ['POST', 'DELETE']);
      expect(adapter.bodies.last, {'fcmToken': 'fixture-device-token'});
      expect(client.deleted, isTrue);
      expect(client.autoInit, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'notifications.device_enabled',
        ),
        isFalse,
      );
    },
  );
  test(
    'permission resolving after logout cannot register another token',
    () async {
      client.permission = Completer<bool>();
      final enabling = service.enable();
      await client.permissionStarted.future;
      await service.unregister();
      client.permission!.complete(true);
      expect(await enabling, contains('Session changed'));
      expect(adapter.calls, isEmpty);
      expect(client.autoInit, isFalse);
    },
  );
  test(
    'disabled preference prevents automatic registration after reload',
    () async {
      await service.enable();
      await service.disable();
      adapter.calls.clear();
      service.dispose();
      service = DevicePushService(
        auth,
        Dio()..httpClientAdapter = adapter,
        client: client,
      );
      await auth.refreshIdentity();
      await Future<void>.delayed(Duration.zero);
      expect(adapter.calls, isEmpty);
    },
  );
  test('cleanup failure cannot prevent local logout', () async {
    final repository = AuthRepository(
      dio: Dio()..httpClientAdapter = adapter,
      tokenStore: store,
      beforeLogout: () async {
        throw StateError('fixture cleanup failure');
      },
    );
    await repository.logout();
    expect(await store.readAccessToken(), isNull);
  });
  testWidgets('notification enable control appears once and shows the result', (
    tester,
  ) async {
    var enabled = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(role: AppRole.admin),
        home: NotificationsScreen(
          repository: NotificationsRepository(
            Dio()..httpClientAdapter = adapter,
            enablePush: () async {
              enabled = true;
              return 'Fixture device registered.';
            },
            disablePush: () async => 'Fixture disabled.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Enable device notifications'), findsOneWidget);
    await tester.tap(find.text('Enable device notifications'));
    await tester.pumpAndSettle();
    expect(enabled, isTrue);
    expect(find.text('Fixture device registered.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test(
    'a refreshed token after a new sign-in cannot override device opt-out',
    () async {
      await service.enable();
      await service.unregister();
      auth.clear();
      await auth.refreshIdentity();
      adapter.calls.clear();
      client.refresh.add('refreshed-fixture-token');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(adapter.calls, isEmpty);
    },
  );
}
