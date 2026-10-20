import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../router/auth_state.dart';
import 'firebase_bootstrap.dart';

@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessage(RemoteMessage message) async {
  // Notification payloads are displayed by the OS. Never log payloads or
  // run authenticated API calls in a background isolate.
  await FirebaseBootstrap.initialize();
}

abstract interface class PushDeviceClient {
  Future<bool> ready();
  Future<bool> authorized();
  Future<bool> requestPermission();
  Future<String?> token();
  Future<void> deleteToken();
  Future<void> setAutoInit(bool enabled);
  Stream<String> get tokenRefresh;
  Stream<void> get foreground;
}

class FirebasePushDeviceClient implements PushDeviceClient {
  @override
  Future<bool> ready() async =>
      await FirebaseBootstrap.initialize().timeout(
        const Duration(seconds: 10),
      ) &&
      await FirebaseMessaging.instance.isSupported();
  @override
  Future<bool> authorized() async =>
      (await FirebaseMessaging.instance.getNotificationSettings())
          .authorizationStatus ==
      AuthorizationStatus.authorized;
  @override
  Future<bool> requestPermission() async =>
      (await FirebaseMessaging.instance.requestPermission())
          .authorizationStatus ==
      AuthorizationStatus.authorized;
  @override
  // Cold registration establishes a browser push-provider channel; allow a
  // bounded 45 seconds so a valid first subscription is not rejected at 10s.
  Future<String?> token() => FirebaseMessaging.instance
      .getToken(vapidKey: kIsWeb ? DevicePushService.vapidKey : null)
      .timeout(const Duration(seconds: 45));
  @override
  Future<void> deleteToken() => FirebaseMessaging.instance
      .deleteToken()
      .timeout(const Duration(seconds: 10));
  @override
  Future<void> setAutoInit(bool enabled) async {
    if (!kIsWeb) await FirebaseMessaging.instance.setAutoInitEnabled(enabled);
  }

  @override
  Stream<String> get tokenRefresh => FirebaseMessaging.instance.onTokenRefresh;
  @override
  Stream<void> get foreground => FirebaseMessaging.onMessage.map((_) {});
}

class DevicePushService {
  DevicePushService(this.auth, this.dio, {PushDeviceClient? client})
    : _client = client ?? FirebasePushDeviceClient() {
    auth.addListener(_sessionChanged);
  }

  final AuthState auth;
  final Dio dio;
  final PushDeviceClient _client;
  static const vapidKey =
      'BDwh6DNaqqnVby-GWUceC3IU3auZ_rDEoYD6rK14McqU2dY3hf5roPzaQ1ORukUh6LSDdTWg4WitdjP8qLoZn4k';
  final _messages = StreamController<void>.broadcast();
  Stream<void> get messages => _messages.stream;
  StreamSubscription<String>? _refresh;
  StreamSubscription<void>? _foreground;
  Future<void> _pending = Future.value();
  String? _session;
  String? _registeredToken;
  String? _deviceToken;
  static const _enabledKey = 'notifications.device_enabled';
  int _generation = 0;
  bool _suspended = false;
  bool _disposed = false;

  String? get _currentSession {
    final identity = auth.identity;
    if (!auth.isSignedIn ||
        auth.mustChangePassword ||
        identity?.userId == null) {
      return null;
    }
    return '${identity?.tenantId}/${identity?.userId}';
  }

  void _sessionChanged() {
    final session = _currentSession;
    if (session == _session || _disposed) return;
    _session = session;
    _generation++;
    _registeredToken = null;
    if (session == null) return;
    _suspended = false;
    final generation = _generation;
    _queue(() async {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(_enabledKey) ?? false)) return;
      if (!await _ready()) return;
      if (await _client.authorized()) {
        await _register(generation);
      }
    });
  }

  Future<bool> _ready() async {
    if (_disposed || !await _client.ready()) {
      return false;
    }
    _refresh ??= _client.tokenRefresh.listen((_) {
      final generation = _generation;
      _queue(() => _register(generation));
    }, onError: (Object _) {});
    _foreground ??= _client.foreground.listen((_) {
      if (!_disposed && _currentSession != null && !_suspended) {
        _messages.add(null);
      }
    });
    return true;
  }

  void _queue(Future<void> Function() operation) {
    _pending = _pending.then((_) async {
      try {
        await operation();
      } catch (_) {
        // Retry is available through the explicit enable button. Never log tokens.
      }
    });
  }

  bool _valid(int generation) =>
      !_disposed &&
      !_suspended &&
      generation == _generation &&
      _session != null &&
      _session == _currentSession;

  Future<void> _register(int generation) async {
    if (!_valid(generation)) return;
    final enabled =
        (await SharedPreferences.getInstance()).getBool(_enabledKey) ?? false;
    if (!enabled || !_valid(generation)) return;
    final token = await _client.token();
    _deviceToken = token;
    if (!_valid(generation) || token == null || token == _registeredToken) {
      return;
    }
    await dio.post<dynamic>(
      '/api/users/fcm-token',
      data: {'fcmToken': token, 'userId': auth.identity!.userId},
    );
    if (_valid(generation)) _registeredToken = token;
  }

  Future<String> enable() async {
    final generation = _generation;
    final session = _currentSession;
    if (_currentSession == null) {
      return 'Sign in before enabling notifications.';
    }
    try {
      if (!await _ready()) return 'Device notifications are unavailable here.';
      // This path is invoked only from the user's button press.
      if (!await _client.requestPermission()) {
        return 'Permission was not granted. You can change it in device settings.';
      }
      if (_currentSession == null) {
        return 'Sign in before enabling notifications.';
      }
      if (generation != _generation ||
          session != _currentSession ||
          _disposed) {
        return 'Session changed. Enable notifications after signing in.';
      }
      var registered = false;
      _queue(() async {
        if (generation != _generation ||
            session != _currentSession ||
            _disposed) {
          return;
        }
        await (await SharedPreferences.getInstance()).setBool(
          _enabledKey,
          true,
        );
        await _client.setAutoInit(true);
        if (generation != _generation ||
            session != _currentSession ||
            _disposed) {
          return;
        }
        _suspended = false;
        await _register(generation);
        registered = _valid(generation) && _registeredToken != null;
      });
      await _pending;
      return registered
          ? 'This device is registered for notifications.'
          : 'Registration could not finish. Check your connection and try again.';
    } catch (_) {
      return 'Registration could not finish. Check your connection and try again.';
    }
  }

  /// Run before clearing the JWT. Drain registrations so logout cannot race POST.
  Future<void> unregister() async {
    _suspended = true;
    _generation++;
    await _pending;
    await (await SharedPreferences.getInstance()).setBool(_enabledKey, false);
    final token = _deviceToken ?? _registeredToken;
    _deviceToken = null;
    _registeredToken = null;
    if (token != null) {
      try {
        await dio.delete<dynamic>(
          '/api/users/fcm-token',
          data: {'fcmToken': token},
        );
      } catch (_) {
        // Firebase deletion independently invalidates the old device token.
      }
    }
    try {
      if (await _client.ready()) {
        await _client.setAutoInit(false);
        await _client.deleteToken();
      }
    } catch (_) {
      // Offline logout still clears the app session. Provider cleanup is best effort.
    }
  }

  Future<String> disable() async {
    await unregister();
    return 'Device notification cleanup requested. Offline cleanup may be delayed.';
  }

  void dispose() {
    _disposed = true;
    _generation++;
    auth.removeListener(_sessionChanged);
    unawaited(_refresh?.cancel());
    unawaited(_foreground?.cancel());
    unawaited(_messages.close());
  }
}
