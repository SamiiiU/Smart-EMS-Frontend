import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Reads a script-visible cookie (only the CSRF cookie is; the refresh cookie
/// is HttpOnly and never reachable from here).
String? readCookie(String name) {
  for (final part in web.document.cookie.split(';')) {
    final index = part.indexOf('=');
    if (index > 0 && part.substring(0, index).trim() == name) {
      return Uri.decodeComponent(part.substring(index + 1).trim());
    }
  }
  return null;
}

/// Serializes [action] across every tab of this origin with the Web Locks API.
/// All tabs share one refresh cookie, and the server rotates it on use: two
/// tabs refreshing at once would look like token replay and revoke the
/// session. Falls back to a plain call where the API is unavailable.
Future<T> withCrossTabLock<T>(String name, Future<T> Function() action) async {
  final web.LockManager locks;
  try {
    locks = web.window.navigator.locks;
  } catch (_) {
    return action();
  }
  final result = Completer<T>();
  JSPromise<JSAny?> granted(web.Lock? lock) => (() async {
        try {
          result.complete(await action());
        } catch (error, stack) {
          result.completeError(error, stack);
        }
      })().toJS;
  await locks.request(name, granted.toJS).toDart;
  return result.future;
}
